import CloudKit
import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingOwnerShareProvenanceRecoveryTests: XCTestCase {
  func testOwnerAbsenceLookupRejectsAccountChangeBeforeReturningAbsent() async throws {
    var accountRecordNames = ["owner-account", "different-account"]
    var recordLookupCount = 0
    let verifier = CloudKitHerdSharingRemoteOwnerShareVerifier(
      currentAccountRecordNameProvider: {
        accountRecordNames.removeFirst()
      },
      privateRecordProvider: { _ -> CKRecord in
        recordLookupCount += 1
        throw CKError(.unknownItem)
      }
    )
    let reference = HerdSharingRemoteOwnerShareReference(
      shareURL: nil,
      shareIdentifier: "owner-share",
      shareRecordZoneName: "owner-zone",
      shareRecordOwnerName: "__defaultOwner__",
      shareOwnerAccountRecordName: "owner-account"
    )

    do {
      _ = try await verifier.status(for: reference)
      XCTFail("Expected an account change during owner-share lookup to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(recordLookupCount, 1)
    XCTAssertTrue(accountRecordNames.isEmpty)
  }

  func testAccountWideOwnerAbsenceRejectsAccountChangeBeforeRetirement() async throws {
    var accountRecordNames = ["owner-account", "different-account"]
    var zoneLookupCount = 0
    let verifier = CloudKitHerdSharingRemoteOwnerShareVerifier(
      currentAccountRecordNameProvider: {
        accountRecordNames.removeFirst()
      },
      recordZonesProvider: {
        zoneLookupCount += 1
        return []
      }
    )

    do {
      _ = try await verifier.hasAnyOwnerShare(forAccountRecordName: "owner-account")
      XCTFail("Expected an account change during account-wide lookup to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(zoneLookupCount, 1)
    XCTAssertTrue(accountRecordNames.isEmpty)
  }

  func testAccountWideOwnerAbsenceRejectsDifferentCurrentAccountBeforeLookup() async throws {
    var zoneLookupCount = 0
    let verifier = CloudKitHerdSharingRemoteOwnerShareVerifier(
      currentAccountRecordNameProvider: {
        "replacement-owner-account"
      },
      recordZonesProvider: {
        zoneLookupCount += 1
        return []
      }
    )

    do {
      _ = try await verifier.hasAnyOwnerShare(forAccountRecordName: "original-owner-account")
      XCTFail("Expected an empty replacement account to be rejected before its zones were queried.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(zoneLookupCount, 0)
  }

  func testURLOnlyOwnerProvenanceCannotAuthorizeStaleReset() async {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    let reference = HerdSharingRemoteOwnerShareReference(
      shareURL: URL(string: "https://www.icloud.com/share/legacy-owner-share")!,
      shareIdentifier: "legacy-owner-share"
    )
    referenceStore.record(reference, for: herdID)
    let verifier = OwnerProvenanceRecoveryRemoteVerifier(anyOwnerShareExists: false)

    do {
      try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
        for: herdID,
        referenceStore: referenceStore,
        remoteVerifier: verifier
      )
      XCTFail("Expected URL-only owner provenance to remain blocked without account binding.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.statusCallCount, 0)
    XCTAssertEqual(verifier.accountWideCallCount, 0)
    XCTAssertEqual(referenceStore.reference(for: herdID), reference)
  }

  func testURLOnlyOwnerVerifierRejectsAccountRelativeRemoteAbsence() async {
    var metadataLookupWasRequested = false
    let verifier = CloudKitHerdSharingRemoteOwnerShareVerifier(
      currentAccountRecordNameProvider: { "replacement-owner-account" },
      shareMetadataProvider: { _ in
        metadataLookupWasRequested = true
        throw CKError(.unknownItem)
      }
    )
    let reference = HerdSharingRemoteOwnerShareReference(
      shareURL: URL(string: "https://www.icloud.com/share/legacy-owner-share")!,
      shareIdentifier: "legacy-owner-share"
    )

    do {
      _ = try await verifier.status(for: reference)
      XCTFail("Expected URL-only owner absence verification to fail without account binding.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridgeConsistencyFailed, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("Account-relative CloudKit absence"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertTrue(metadataLookupWasRequested)
  }

  func testMirroredReferenceRecoversCorruptPrimaryCopiesFromRedundantExactCopy() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    let reference = makeReference(suffix: "recover")
    fixture.store.record(reference, for: fixture.herdID)

    let corruptValue = "corrupt-owner-primary"
    fixture.ubiquitous.set(corruptValue, forKey: fixture.primaryKey)
    fixture.defaults.set(corruptValue, forKey: fixture.primaryKey)
    _ = fixture.ubiquitous.synchronize()

    let recovered = try fixture.store.recoverableReference(for: fixture.herdID)

    XCTAssertEqual(recovered, reference)
    let encoded = try encodedReference(reference)
    XCTAssertEqual(fixture.ubiquitous.string(forKey: fixture.primaryKey), encoded)
    XCTAssertEqual(fixture.defaults.string(forKey: fixture.primaryKey), encoded)
    XCTAssertEqual(fixture.ubiquitous.string(forKey: fixture.recoveryKey), encoded)
    XCTAssertEqual(fixture.defaults.string(forKey: fixture.recoveryKey), encoded)
    let backups = backupValues(in: fixture.defaults, prefix: fixture.backupPrefix)
    XCTAssertEqual(backups.count, 2)
    XCTAssertTrue(backups.allSatisfy { $0 == corruptValue })
  }

  func testMirroredReferenceFailsClosedAndPreservesEveryCorruptCopy() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.store.record(makeReference(suffix: "all-corrupt"), for: fixture.herdID)
    let values = corruptEveryCopy(in: fixture)

    do {
      _ = try fixture.store.recoverableReference(for: fixture.herdID)
      XCTFail("Expected corrupt mirrored owner provenance to remain fail-closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridgeConsistencyFailed, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("owner-share provenance"))
      XCTAssertTrue(message.contains("backed up"))
    }

    assertActiveValues(values, in: fixture)
    XCTAssertEqual(Set(backupValues(in: fixture.defaults, prefix: fixture.backupPrefix)), Set(values))
  }

  func testRetirementBackupStopsMatchingWhenActiveCorruptBytesChange() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.store.record(makeReference(suffix: "snapshot"), for: fixture.herdID)
    _ = corruptEveryCopy(in: fixture)

    XCTAssertThrowsError(try fixture.store.recoverableReference(for: fixture.herdID))
    XCTAssertTrue(fixture.store.hasBackedUpUnusableReference(for: fixture.herdID))

    fixture.defaults.set("new-corrupt-defaults-primary", forKey: fixture.primaryKey)

    XCTAssertFalse(fixture.store.hasBackedUpUnusableReference(for: fixture.herdID))
  }

  func testCorruptProvenanceCannotBeRetiredUsingAnotherAccountsAbsence() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.store.record(makeReference(suffix: "retire"), for: fixture.herdID)
    let values = corruptEveryCopy(in: fixture)
    let verifier = OwnerProvenanceRecoveryRemoteVerifier(anyOwnerShareExists: false)

    do {
      try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
        for: fixture.herdID,
        referenceStore: fixture.store,
        remoteVerifier: verifier
      )
      XCTFail("Expected corrupt provenance with no surviving account identity to remain blocked.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Expected bridgeConsistencyFailed, got \(error)")
        return
      }
    }

    XCTAssertEqual(verifier.statusCallCount, 0)
    XCTAssertEqual(verifier.accountWideCallCount, 0)
    assertActiveValues(values, in: fixture)
    XCTAssertEqual(backupValues(in: fixture.defaults, prefix: fixture.backupPrefix).count, 4)
  }

  func testCorruptProvenanceRemainsBlockedWhenAnyOwnerShareStillExists() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.store.record(makeReference(suffix: "remote-present"), for: fixture.herdID)
    let values = corruptEveryCopy(in: fixture)
    let verifier = OwnerProvenanceRecoveryRemoteVerifier(anyOwnerShareExists: true)

    do {
      try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
        for: fixture.herdID,
        referenceStore: fixture.store,
        remoteVerifier: verifier
      )
      XCTFail("Expected corrupt provenance with no surviving account identity to remain blocked.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Expected bridgeConsistencyFailed, got \(error)")
        return
      }
    }

    XCTAssertEqual(verifier.statusCallCount, 0)
    XCTAssertEqual(verifier.accountWideCallCount, 0)
    assertActiveValues(values, in: fixture)
  }

  func testMissingResumeProvenanceDoesNotUseAccountWideFallback() async {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    let verifier = OwnerProvenanceRecoveryRemoteVerifier(anyOwnerShareExists: false)

    do {
      try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
        for: herdID,
        referenceStore: referenceStore,
        remoteVerifier: verifier
      )
      XCTFail("Expected a resume with genuinely missing provenance to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.statusCallCount, 0)
    XCTAssertEqual(verifier.accountWideCallCount, 0)
  }

  func testFirstShareWithCorruptEvidenceCannotUseCurrentAccountsAbsence() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.ubiquitous.set("corrupt-primary", forKey: fixture.primaryKey)
    fixture.defaults.set("corrupt-recovery", forKey: fixture.recoveryKey)
    _ = fixture.ubiquitous.synchronize()
    let verifier = OwnerProvenanceRecoveryRemoteVerifier(anyOwnerShareExists: false)

    do {
      try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
        for: fixture.herdID,
        referenceStore: fixture.store,
        remoteVerifier: verifier,
        allowMissingReference: true
      )
      XCTFail("Expected corrupt evidence to block creation without its original account identity.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Expected bridgeConsistencyFailed, got \(error)")
        return
      }
    }

    XCTAssertEqual(verifier.statusCallCount, 0)
    XCTAssertEqual(verifier.accountWideCallCount, 0)
    XCTAssertEqual(fixture.ubiquitous.string(forKey: fixture.primaryKey), "corrupt-primary")
    XCTAssertEqual(fixture.defaults.string(forKey: fixture.recoveryKey), "corrupt-recovery")
  }

  func testIncompleteProvenanceCanRetireOnlyWithinItsRecordedAccount() async throws {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: nil,
        shareIdentifier: "incomplete-owner-share",
        shareOwnerAccountRecordName: "original-owner-account"
      ),
      for: herdID
    )
    let verifier = OwnerProvenanceRecoveryRemoteVerifier(anyOwnerShareExists: false)

    try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
      for: herdID,
      referenceStore: referenceStore,
      remoteVerifier: verifier
    )

    XCTAssertEqual(verifier.statusCallCount, 0)
    XCTAssertEqual(verifier.accountWideCallCount, 1)
    XCTAssertEqual(verifier.requestedAccountRecordNames, ["original-owner-account"])
    XCTAssertNil(referenceStore.reference(for: herdID))
  }

  func testExistingOwnerBackfillPreservesSavedURLForSameExactShare() throws {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    let savedURL = URL(string: "https://www.icloud.com/share/owner-backfill")!
    let existing = makeReference(suffix: "same", shareURL: savedURL)
    referenceStore.record(existing, for: herdID)
    let observed = makeReference(suffix: "same")

    try HerdSharingExistingOwnerShareBackfill.recordObservedReference(
      observed,
      for: herdID,
      referenceStore: referenceStore
    )

    XCTAssertEqual(referenceStore.reference(for: herdID), existing)
  }

  func testExistingOwnerBackfillRejectsURLWithoutOwnerAccountBinding() {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    let observed = HerdSharingRemoteOwnerShareReference(
      shareURL: URL(string: "https://www.icloud.com/share/unbound-owner")!,
      shareIdentifier: "unbound-owner"
    )

    XCTAssertThrowsError(
      try HerdSharingExistingOwnerShareBackfill.recordObservedReference(
        observed,
        for: herdID,
        referenceStore: referenceStore
      )
    )
    XCTAssertNil(referenceStore.reference(for: herdID))
  }

  func testPresentationDoesNotCommitURLWithoutOwnerAccountBinding() {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    let presentation = HerdSharePresentationRequest(
      token: HerdShareToken(),
      title: "Unbound Owner Share",
      shareIdentifier: "unbound-owner",
      shareURL: URL(string: "https://www.icloud.com/share/unbound-owner")!
    )

    XCTAssertFalse(
      HerdSharingOwnerShareProvenance.recordPresentationReferenceIfVerifiable(
        presentation,
        herdPublicID: herdID,
        referenceStore: referenceStore
      )
    )
    XCTAssertNil(referenceStore.reference(for: herdID))
  }

  func testSavedShareCallbackDoesNotCommitURLWithoutOwnerAccountBinding() {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    let presentation = HerdSharePresentationRequest(
      token: HerdShareToken(),
      title: "Unbound Saved Owner Share",
      shareIdentifier: "unbound-saved-owner",
      shareURL: nil
    )
    let recorder = HerdSharingSavedOwnerShareReferenceRecorder(
      referenceStore: referenceStore,
      herdPublicID: herdID,
      presentation: presentation
    )

    recorder.record(
      shareURL: URL(string: "https://www.icloud.com/share/unbound-saved-owner")!,
      shareIdentifier: "unbound-saved-owner"
    )

    XCTAssertNil(referenceStore.reference(for: herdID))
  }

  func testExistingOwnerBackfillReplacesReferenceWhenCloudKitIdentityDiffers() throws {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceMemoryStore()
    let stale = HerdSharingRemoteOwnerShareReference(
      shareURL: URL(string: "https://www.icloud.com/share/stale-owner")!,
      shareIdentifier: "zone-wide-share",
      shareRecordZoneName: "stale-zone",
      shareRecordOwnerName: "__defaultOwner__",
      shareOwnerAccountRecordName: "stale-account"
    )
    referenceStore.record(stale, for: herdID)
    let observed = HerdSharingRemoteOwnerShareReference(
      shareURL: nil,
      shareIdentifier: "zone-wide-share",
      shareRecordZoneName: "current-zone",
      shareRecordOwnerName: "__defaultOwner__",
      shareOwnerAccountRecordName: "current-account"
    )

    try HerdSharingExistingOwnerShareBackfill.recordObservedReference(
      observed,
      for: herdID,
      referenceStore: referenceStore
    )

    XCTAssertEqual(referenceStore.reference(for: herdID), observed)
  }

  func testExistingOwnerBackfillRepairsFullyCorruptMirrorsAfterBackingThemUp() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    fixture.store.record(makeReference(suffix: "old"), for: fixture.herdID)
    let corruptValues = corruptEveryCopy(in: fixture)
    let observed = makeReference(suffix: "active")

    try HerdSharingExistingOwnerShareBackfill.recordObservedReference(
      observed,
      for: fixture.herdID,
      referenceStore: fixture.store
    )

    XCTAssertEqual(try fixture.store.recoverableReference(for: fixture.herdID), observed)
    XCTAssertEqual(
      Set(backupValues(in: fixture.defaults, prefix: fixture.backupPrefix)),
      Set(corruptValues)
    )
  }

  func testPresentationReferenceIsNotReportedPersistedWhenDurableWriteFails() {
    let herdID = UUID()
    let referenceStore = OwnerProvenanceFailingStore()
    let presentation = HerdSharePresentationRequest(
      token: HerdShareToken(),
      title: "Failing Owner Provenance",
      shareIdentifier: "failed-owner-share",
      shareURL: nil,
      shareRecordZoneName: "failed-zone",
      shareRecordOwnerName: "__defaultOwner__",
      shareOwnerAccountRecordName: "failed-account"
    )

    let persisted = HerdSharingOwnerShareProvenance.recordPresentationReferenceIfVerifiable(
      presentation,
      herdPublicID: herdID,
      referenceStore: referenceStore
    )

    XCTAssertFalse(persisted)
    XCTAssertNil(referenceStore.reference(for: herdID))
  }

  private func makeFixture() throws -> OwnerProvenanceFixture {
    let suiteName = "HerdSharingOwnerShareProvenanceRecovery.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw OwnerProvenanceRecoveryTestError.userDefaultsUnavailable
    }
    defaults.removePersistentDomain(forName: suiteName)
    let keyPrefix = "OwnerShareReference.\(UUID().uuidString.lowercased())"
    let herdID = UUID()
    let ubiquitous = NSUbiquitousKeyValueStore.default
    let store = MirroredHerdSharingOwnerShareReferenceStore(
      ubiquitous: ubiquitous,
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    return OwnerProvenanceFixture(
      suiteName: suiteName,
      defaults: defaults,
      ubiquitous: ubiquitous,
      store: store,
      keyPrefix: keyPrefix,
      herdID: herdID
    )
  }

  private func makeReference(
    suffix: String,
    shareURL: URL? = nil
  ) -> HerdSharingRemoteOwnerShareReference {
    HerdSharingRemoteOwnerShareReference(
      shareURL: shareURL,
      shareIdentifier: "owner-share-\(suffix)",
      shareRecordZoneName: "owner-zone-\(suffix)",
      shareRecordOwnerName: "__defaultOwner__",
      shareOwnerAccountRecordName: "owner-account-\(suffix)"
    )
  }

  private func encodedReference(_ reference: HerdSharingRemoteOwnerShareReference) throws -> String {
    let data = try JSONEncoder().encode(reference)
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }

  private func corruptEveryCopy(in fixture: OwnerProvenanceFixture) -> [String] {
    let values = [
      "ubiquitous-primary-corrupt",
      "defaults-primary-corrupt",
      "ubiquitous-recovery-corrupt",
      "defaults-recovery-corrupt",
    ]
    fixture.ubiquitous.set(values[0], forKey: fixture.primaryKey)
    fixture.defaults.set(values[1], forKey: fixture.primaryKey)
    fixture.ubiquitous.set(values[2], forKey: fixture.recoveryKey)
    fixture.defaults.set(values[3], forKey: fixture.recoveryKey)
    _ = fixture.ubiquitous.synchronize()
    return values
  }

  private func assertActiveValues(_ values: [String], in fixture: OwnerProvenanceFixture) {
    XCTAssertEqual(fixture.ubiquitous.string(forKey: fixture.primaryKey), values[0])
    XCTAssertEqual(fixture.defaults.string(forKey: fixture.primaryKey), values[1])
    XCTAssertEqual(fixture.ubiquitous.string(forKey: fixture.recoveryKey), values[2])
    XCTAssertEqual(fixture.defaults.string(forKey: fixture.recoveryKey), values[3])
  }

  private func backupValues(in defaults: UserDefaults, prefix: String) -> [String] {
    defaults.dictionaryRepresentation().compactMap { key, value in
      guard key.hasPrefix(prefix) else { return nil }
      return value as? String
    }
  }
}

@MainActor
private struct OwnerProvenanceFixture {
  let suiteName: String
  let defaults: UserDefaults
  let ubiquitous: NSUbiquitousKeyValueStore
  let store: MirroredHerdSharingOwnerShareReferenceStore
  let keyPrefix: String
  let herdID: UUID

  var primaryKey: String {
    "\(keyPrefix).\(herdID.uuidString.lowercased())"
  }

  var recoveryKey: String {
    "\(primaryKey).recovery"
  }

  var backupPrefix: String {
    "\(keyPrefix).recovery-backup.\(herdID.uuidString.lowercased())."
  }

  func cleanup() {
    store.clearReference(for: herdID)
    defaults.removePersistentDomain(forName: suiteName)
  }
}

@MainActor
private final class OwnerProvenanceRecoveryRemoteVerifier: HerdSharingRemoteOwnerShareVerifying {
  private let anyOwnerShareExists: Bool
  private(set) var statusCallCount = 0
  private(set) var accountWideCallCount = 0
  private(set) var requestedAccountRecordNames: [String] = []

  init(anyOwnerShareExists: Bool) {
    self.anyOwnerShareExists = anyOwnerShareExists
  }

  func status(
    for reference: HerdSharingRemoteOwnerShareReference
  ) async throws -> HerdSharingRemoteOwnerShareStatus {
    statusCallCount += 1
    return .absent
  }

  func hasAnyOwnerShare(forAccountRecordName expectedAccountRecordName: String) async throws -> Bool {
    accountWideCallCount += 1
    requestedAccountRecordNames.append(expectedAccountRecordName)
    return anyOwnerShareExists
  }
}

@MainActor
private final class OwnerProvenanceMemoryStore: HerdSharingOwnerShareReferenceRecording {
  private var references: [UUID: HerdSharingRemoteOwnerShareReference] = [:]

  func reference(for herdPublicID: UUID) -> HerdSharingRemoteOwnerShareReference? {
    references[herdPublicID]
  }

  func record(
    _ reference: HerdSharingRemoteOwnerShareReference,
    for herdPublicID: UUID
  ) {
    references[herdPublicID] = reference
  }

  func clearReference(for herdPublicID: UUID) {
    references.removeValue(forKey: herdPublicID)
  }
}

@MainActor
private final class OwnerProvenanceFailingStore: HerdSharingOwnerShareReferenceRecording {
  func reference(for herdPublicID: UUID) -> HerdSharingRemoteOwnerShareReference? { nil }
  func record(
    _ reference: HerdSharingRemoteOwnerShareReference,
    for herdPublicID: UUID
  ) {}
  func clearReference(for herdPublicID: UUID) {}
}

private enum OwnerProvenanceRecoveryTestError: Error {
  case userDefaultsUnavailable
}
