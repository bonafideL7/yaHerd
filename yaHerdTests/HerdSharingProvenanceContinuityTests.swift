import CloudKit
import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingProvenanceContinuityTests: XCTestCase {
  func testCurrentAccountOwnerShareBlocksNewShareCommitBoundary() async {
    let verifier = ProvenanceContinuityOwnerVerifier(
      status: .absent,
      hasAnyCurrentAccountOwnerShare: true
    )

    do {
      try await HerdSharingOwnerShareProvenance.verifyCurrentAccountHasNoOwnerShare(
        remoteVerifier: verifier
      )
      XCTFail("Expected current-account owner history to block new share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.currentAccountOwnerShareLookupCount, 1)
    XCTAssertEqual(verifier.statusCallCount, 0)
  }

  func testNewShareCommitBoundaryAllowsAccountOnlyAfterRemoteOwnerAbsence() async throws {
    let verifier = ProvenanceContinuityOwnerVerifier(
      status: .absent,
      hasAnyCurrentAccountOwnerShare: false
    )

    try await HerdSharingOwnerShareProvenance.verifyCurrentAccountHasNoOwnerShare(
      remoteVerifier: verifier
    )

    XCTAssertEqual(verifier.currentAccountOwnerShareLookupCount, 1)
    XCTAssertEqual(verifier.statusCallCount, 0)
  }

  func testObservedOwnerShareIsNotPersistedUntilAccountAwareVerificationSucceeds() async throws {
    let herd = makeHerd()
    let observedReference = HerdSharingRemoteOwnerShareReference(
      shareURL: nil,
      shareIdentifier: "observed-owner-share",
      shareRecordZoneName: "observed-owner-zone",
      shareRecordOwnerName: CKCurrentUserDefaultName,
      shareOwnerAccountRecordName: "owner-account-a"
    )
    let referenceStore = ProvenanceContinuityOwnerReferenceStore()
    let rejectingVerifier = ProvenanceContinuityOwnerVerifier(
      status: .present,
      statusError: .ownerBridgeVerificationRequired
    )
    let rejectedRepository = GatedHerdSharingRepository(
      base: ProvenanceContinuitySharingRepository(
        access: .ownerPrivateStore(participantCount: 2, hasActiveSystemShare: true)
      ),
      mutationGate: HerdDataMutationGate(),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: rejectingVerifier,
      observedOwnerShareReferenceProvider: { _ in observedReference }
    )

    do {
      _ = try await rejectedRepository.fetchSharingAccess(for: herd, storageMode: .iCloud)
      XCTFail("Expected the unverified observed owner share to be rejected.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
    XCTAssertNil(referenceStore.reference(for: herd.publicID))

    let acceptingVerifier = ProvenanceContinuityOwnerVerifier(status: .present)
    let acceptedRepository = GatedHerdSharingRepository(
      base: ProvenanceContinuitySharingRepository(
        access: .ownerPrivateStore(participantCount: 2, hasActiveSystemShare: true)
      ),
      mutationGate: HerdDataMutationGate(),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: acceptingVerifier,
      observedOwnerShareReferenceProvider: { _ in observedReference }
    )

    let access = try await acceptedRepository.fetchSharingAccess(for: herd, storageMode: .iCloud)

    XCTAssertEqual(access.bridgeLocation, .ownerPrivateStore)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), observedReference)
    XCTAssertEqual(acceptingVerifier.statusCallCount, 1)
  }

  func testLegacyLocalParticipantEvidenceDoesNotContaminateCurrentICloudAccountBeforeVerification()
    throws
  {
    let herdID = UUID()
    let ownershipPrefix = "ParticipantLocalOnly.ownership.\(UUID().uuidString)"
    let referencePrefix = "ParticipantLocalOnly.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantLocalOnly.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: ownershipPrefix,
        referencePrefix: referencePrefix
      )
    }

    UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: ownershipPrefix
    ).recordParticipant(herdPublicID: herdID)
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "legacy-root",
      rootZoneName: "legacy-zone",
      rootZoneOwnerName: "legacy-owner",
      participantAccountRecordName: "legacy-account"
    )
    let data = try JSONEncoder().encode(reference)
    let referenceKey = "\(referencePrefix).\(herdID.uuidString.lowercased())"
    defaults.set(data, forKey: referenceKey)
    defaults.set(data, forKey: "\(referenceKey).recovery")

    let ownership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaults,
      ubiquitous: ubiquitous,
      ownershipKeyPrefix: ownershipPrefix,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let referenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )

    XCTAssertEqual(ownership.ownership(for: herdID), .participant)
    XCTAssertEqual(try referenceStore.recoverableReference(for: herdID), reference)
    XCTAssertNil(ubiquitous.string(forKey: "\(ownershipPrefix).\(herdID.uuidString.lowercased())"))
    XCTAssertNil(ubiquitous.data(forKey: referenceKey))
    XCTAssertNil(ubiquitous.data(forKey: "\(referenceKey).recovery"))

    // These calls model the account-aware post-verification migration boundary.
    try referenceStore.recordRecoverably(reference, for: herdID)
    ownership.recordParticipant(herdPublicID: herdID)
    XCTAssertNotNil(ubiquitous.string(forKey: "\(ownershipPrefix).\(herdID.uuidString.lowercased())"))
    XCTAssertEqual(ubiquitous.data(forKey: referenceKey), data)
  }

  func testParticipantLineageAndExactReferenceRestoreOnReplacementDevice() throws {
    let herdID = UUID()
    let ownershipPrefix = "ParticipantContinuity.ownership.\(UUID().uuidString)"
    let referencePrefix = "ParticipantContinuity.reference.\(UUID().uuidString)"
    let suiteAName = "ParticipantContinuity.deviceA.\(UUID().uuidString)"
    let suiteBName = "ParticipantContinuity.deviceB.\(UUID().uuidString)"
    let defaultsA = try XCTUnwrap(UserDefaults(suiteName: suiteAName))
    let defaultsB = try XCTUnwrap(UserDefaults(suiteName: suiteBName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaultsA.removePersistentDomain(forName: suiteAName)
    defaultsB.removePersistentDomain(forName: suiteBName)
    defer {
      defaultsA.removePersistentDomain(forName: suiteAName)
      defaultsB.removePersistentDomain(forName: suiteBName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: ownershipPrefix,
        referencePrefix: referencePrefix
      )
    }

    let deviceAOwnership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaultsA,
      ubiquitous: ubiquitous,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let deviceAReferenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaultsA,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-herd-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "owner-record",
      participantAccountRecordName: "participant-account"
    )

    try deviceAReferenceStore.recordRecoverably(reference, for: herdID)
    deviceAOwnership.recordParticipant(herdPublicID: herdID)
    XCTAssertEqual(deviceAReferenceStore.reference(for: herdID), reference)

    // The replacement installation has no local defaults; only account-level provenance remains.
    defaultsA.removePersistentDomain(forName: suiteAName)

    let deviceBOwnership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaultsB,
      ubiquitous: ubiquitous,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let deviceBReferenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaultsB,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )

    XCTAssertEqual(deviceBOwnership.ownership(for: herdID), .participant)
    XCTAssertEqual(try deviceBReferenceStore.recoverableReference(for: herdID), reference)
  }

  func testFailedMirrorMarkerDoesNotAcceptLocalReferenceAsCrossDeviceProvenance() throws {
    let herdID = UUID()
    let referencePrefix = "ParticipantMirrorFailure.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantMirrorFailure.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: "ParticipantMirrorFailure.ownership.unused",
        referencePrefix: referencePrefix
      )
    }

    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "mirror-failure-root",
      rootZoneName: "mirror-failure-zone",
      rootZoneOwnerName: "mirror-failure-owner",
      participantAccountRecordName: "participant-account"
    )
    let data = try JSONEncoder().encode(reference)
    let referenceKey = "\(referencePrefix).\(herdID.uuidString.lowercased())"
    defaults.set(data, forKey: referenceKey)
    defaults.set(data, forKey: "\(referenceKey).recovery")
    defaults.set(true, forKey: "\(referenceKey).mirror-write-failed")

    let referenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )

    XCTAssertThrowsError(try referenceStore.recoverableReference(for: herdID)) { error in
      guard let actionError = error as? HerdSharingActionError,
            case .bridgeConsistencyFailed = actionError
      else {
        return XCTFail("Expected mirror persistence failure to remain fail-closed, got \(error)")
      }
    }
    XCTAssertTrue(referenceStore.hasConflictingReference(for: herdID))
    XCTAssertNil(ubiquitous.data(forKey: referenceKey))
  }

  func testDetachedOwnershipPersistsRetirementBeforeReferenceCleanup() throws {
    let herdID = UUID()
    let ownershipPrefix = "ParticipantDetachCrash.ownership.\(UUID().uuidString)"
    let referencePrefix = "ParticipantDetachCrash.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantDetachCrash.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: ownershipPrefix,
        referencePrefix: referencePrefix
      )
    }

    let ownership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaults,
      ubiquitous: ubiquitous,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let referenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "detach-crash-root",
      rootZoneName: "detach-crash-zone",
      rootZoneOwnerName: "detach-crash-owner",
      participantAccountRecordName: "participant-account"
    )

    try referenceStore.recordRecoverably(reference, for: herdID)
    ownership.recordParticipant(herdPublicID: herdID)

    // Model process termination immediately after the creation guard commits detached ownership,
    // before GatedHerdSharingRepository reaches its later exact-reference clearReference cleanup.
    ownership.recordDetachedParticipant(herdPublicID: herdID)

    let referenceKey = "\(referencePrefix).\(herdID.uuidString.lowercased())"
    XCTAssertTrue(ubiquitous.bool(forKey: "\(referenceKey).retired"))
    XCTAssertNotNil(ubiquitous.string(forKey: "\(referencePrefix).detachment-generation"))
    XCTAssertEqual(ownership.ownership(for: herdID), .detachedParticipant)
    XCTAssertNil(try referenceStore.recoverableReference(for: herdID))
  }

  func testDetachedParticipantCannotBeResurrectedByStaleSecondDevice() throws {
    let herdID = UUID()
    let ownershipPrefix = "ParticipantDetachContinuity.ownership.\(UUID().uuidString)"
    let referencePrefix = "ParticipantDetachContinuity.reference.\(UUID().uuidString)"
    let suiteAName = "ParticipantDetachContinuity.deviceA.\(UUID().uuidString)"
    let suiteBName = "ParticipantDetachContinuity.deviceB.\(UUID().uuidString)"
    let defaultsA = try XCTUnwrap(UserDefaults(suiteName: suiteAName))
    let defaultsB = try XCTUnwrap(UserDefaults(suiteName: suiteBName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaultsA.removePersistentDomain(forName: suiteAName)
    defaultsB.removePersistentDomain(forName: suiteBName)
    defer {
      defaultsA.removePersistentDomain(forName: suiteAName)
      defaultsB.removePersistentDomain(forName: suiteBName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: ownershipPrefix,
        referencePrefix: referencePrefix
      )
    }

    let staleDeviceOwnership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaultsA,
      ubiquitous: ubiquitous,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let detachingDeviceOwnership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaultsB,
      ubiquitous: ubiquitous,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let staleReferenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaultsA,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    let detachingReferenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaultsB,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "retired-root",
      rootZoneName: "retired-zone",
      rootZoneOwnerName: "retired-owner",
      participantAccountRecordName: "participant-account"
    )

    try staleReferenceStore.recordRecoverably(reference, for: herdID)
    staleDeviceOwnership.recordParticipant(herdPublicID: herdID)
    XCTAssertEqual(detachingDeviceOwnership.ownership(for: herdID), .participant)
    XCTAssertEqual(try detachingReferenceStore.recoverableReference(for: herdID), reference)

    detachingDeviceOwnership.recordDetachedParticipant(herdPublicID: herdID)
    detachingReferenceStore.clearReference(for: herdID)

    // Model a verification that started on device A before detachment and completes afterward. Both
    // the stale exact-reference write and stale lineage write must observe the retirement boundary.
    staleReferenceStore.record(reference, for: herdID)
    staleDeviceOwnership.recordParticipant(herdPublicID: herdID)

    // Also model out-of-order KVS delivery where a stale participant lineage write lands after the
    // detach lineage. The reference retirement tombstone remains the stronger authority on reads.
    let herdKey = herdID.uuidString.lowercased()
    ubiquitous.set("participant", forKey: "\(ownershipPrefix).\(herdKey)")
    _ = ubiquitous.synchronize()

    XCTAssertEqual(staleDeviceOwnership.ownership(for: herdID), .detachedParticipant)
    XCTAssertNil(try staleReferenceStore.recoverableReference(for: herdID))
    XCTAssertNil(staleReferenceStore.reference(for: herdID))
    let referenceKey = "\(referencePrefix).\(herdKey)"
    XCTAssertTrue(ubiquitous.bool(forKey: "\(referenceKey).retired"))
    XCTAssertNil(ubiquitous.data(forKey: referenceKey))
  }

  func testInvitationAcceptedBeforeNewerDetachCannotSupersedeTombstone() throws {
    let herdID = UUID()
    let ownershipPrefix = "ParticipantStaleAcceptance.ownership.\(UUID().uuidString)"
    let referencePrefix = "ParticipantStaleAcceptance.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantStaleAcceptance.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: ownershipPrefix,
        referencePrefix: referencePrefix
      )
    }

    let ownership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaults,
      ubiquitous: ubiquitous,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let referenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "stale-acceptance-root",
      rootZoneName: "stale-acceptance-zone",
      rootZoneOwnerName: "stale-acceptance-owner",
      participantAccountRecordName: "participant-account"
    )

    try referenceStore.recordRecoverably(reference, for: herdID)
    ownership.recordParticipant(herdPublicID: herdID)

    // Capture the invitation boundary before another device detaches this participant relationship.
    try referenceStore.recordExplicitAcceptanceBoundary(for: reference)
    ownership.recordDetachedParticipant(herdPublicID: herdID)
    referenceStore.clearReference(for: herdID)

    XCTAssertThrowsError(
      try referenceStore.recordExplicitlyAcceptedRecoverably(reference, for: herdID)
    ) { error in
      guard let actionError = error as? HerdSharingActionError,
            case .bridgeConsistencyFailed(let message) = actionError
      else {
        return XCTFail("Expected stale acceptance generation to fail closed, got \(error)")
      }
      XCTAssertTrue(message.contains("predates the current participant-detachment tombstone"))
    }
    XCTAssertEqual(ownership.ownership(for: herdID), .detachedParticipant)
    XCTAssertNil(try referenceStore.recoverableReference(for: herdID))
  }

  func testExplicitlyAcceptedReferenceCanSupersedeParticipantDetachTombstone() throws {
    let herdID = UUID()
    let ownershipPrefix = "ParticipantReaccept.ownership.\(UUID().uuidString)"
    let referencePrefix = "ParticipantReaccept.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantReaccept.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: ownershipPrefix,
        referencePrefix: referencePrefix
      )
    }

    let ownership = MirroredHerdSharingOwnershipRegistry(
      defaults: defaults,
      ubiquitous: ubiquitous,
      participantKeyPrefix: ownershipPrefix,
      participantReferenceKeyPrefix: referencePrefix
    )
    let referenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "reaccepted-root",
      rootZoneName: "reaccepted-zone",
      rootZoneOwnerName: "reaccepted-owner",
      participantAccountRecordName: "participant-account"
    )

    try referenceStore.recordRecoverably(reference, for: herdID)
    ownership.recordParticipant(herdPublicID: herdID)
    ownership.recordDetachedParticipant(herdPublicID: herdID)
    referenceStore.clearReference(for: herdID)

    // Production records this boundary before CloudKit invitation acceptance begins. Only a fresh
    // post-detach acceptance generation may supersede the current retirement tombstone.
    XCTAssertThrowsError(try referenceStore.recordRecoverably(reference, for: herdID))
    try referenceStore.recordExplicitAcceptanceBoundary(for: reference)
    try referenceStore.recordExplicitlyAcceptedRecoverably(reference, for: herdID)
    ownership.recordParticipant(herdPublicID: herdID)

    XCTAssertEqual(try referenceStore.recoverableReference(for: herdID), reference)
    XCTAssertEqual(ownership.ownership(for: herdID), .participant)
    let referenceKey = "\(referencePrefix).\(herdID.uuidString.lowercased())"
    XCTAssertFalse(ubiquitous.bool(forKey: "\(referenceKey).retired"))
  }

  func testPostDetachAcceptanceGenerationSurvivesReferenceStoreRecreation() throws {
    let herdID = UUID()
    let ownershipPrefix = "ParticipantReacceptRestart.ownership.\(UUID().uuidString)"
    let referencePrefix = "ParticipantReacceptRestart.reference.\(UUID().uuidString)"
    let suiteName = "ParticipantReacceptRestart.defaults.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let ubiquitous = NSUbiquitousKeyValueStore.default
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      clearUbiquitousParticipantState(
        ubiquitous,
        herdID: herdID,
        ownershipPrefix: ownershipPrefix,
        referencePrefix: referencePrefix
      )
    }

    let firstStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "restart-reaccept-root",
      rootZoneName: "restart-reaccept-zone",
      rootZoneOwnerName: "restart-reaccept-owner",
      participantAccountRecordName: "participant-account"
    )

    try firstStore.recordRecoverably(reference, for: herdID)
    firstStore.clearReference(for: herdID)
    try firstStore.recordExplicitAcceptanceBoundary(for: reference)

    // Recreate the reference store after the invitation was accepted but before its shared root was
    // imported. The local acceptance generation must still authorize only this post-detach invite.
    let restartedStore = MirroredHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      ubiquitous: ubiquitous,
      keyPrefix: referencePrefix
    )
    try restartedStore.recordExplicitlyAcceptedRecoverably(reference, for: herdID)

    XCTAssertEqual(try restartedStore.recoverableReference(for: herdID), reference)
  }

  private func makeHerd() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Provenance Continuity Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }

  private func clearUbiquitousParticipantState(
    _ store: NSUbiquitousKeyValueStore,
    herdID: UUID,
    ownershipPrefix: String,
    referencePrefix: String
  ) {
    let herdKey = herdID.uuidString.lowercased()
    let referenceKey = "\(referencePrefix).\(herdKey)"
    store.removeObject(forKey: "\(ownershipPrefix).\(herdKey)")
    store.removeObject(forKey: referenceKey)
    store.removeObject(forKey: "\(referenceKey).recovery")
    store.removeObject(forKey: "\(referenceKey).retired")
    store.removeObject(forKey: "\(referencePrefix).detachment-generation")
    _ = store.synchronize()
  }
}

@MainActor
private final class ProvenanceContinuityOwnerReferenceStore:
  HerdSharingOwnerShareReferenceRecording
{
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
private final class ProvenanceContinuityOwnerVerifier: HerdSharingRemoteOwnerShareVerifying {
  private let remoteStatus: HerdSharingRemoteOwnerShareStatus
  private let statusError: HerdSharingActionError?
  private let hasAnyCurrentAccountOwnerShare: Bool
  private(set) var statusCallCount = 0
  private(set) var currentAccountOwnerShareLookupCount = 0

  init(
    status: HerdSharingRemoteOwnerShareStatus,
    statusError: HerdSharingActionError? = nil,
    hasAnyCurrentAccountOwnerShare: Bool = false
  ) {
    remoteStatus = status
    self.statusError = statusError
    self.hasAnyCurrentAccountOwnerShare = hasAnyCurrentAccountOwnerShare
  }

  func status(
    for reference: HerdSharingRemoteOwnerShareReference
  ) async throws -> HerdSharingRemoteOwnerShareStatus {
    statusCallCount += 1
    if let statusError { throw statusError }
    return remoteStatus
  }

  func hasAnyOwnerShareForCurrentAccount() async throws -> Bool {
    currentAccountOwnerShareLookupCount += 1
    return hasAnyCurrentAccountOwnerShare
  }
}

@MainActor
private final class ProvenanceContinuitySharingRepository: HerdSharingRepository {
  private let access: HerdSharingAccess

  init(access: HerdSharingAccess) {
    self.access = access
  }

  func fetchSharingReadiness(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) -> HerdSharingReadiness {
    .sharingAdapterAvailable
  }

  func fetchSharingAccess(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess {
    access
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }
}
