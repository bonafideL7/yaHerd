import CloudKit
@preconcurrency import CoreData
import Foundation
import SwiftData
import XCTest

@testable import yaHerd

private struct AcceptedReferenceFailingRevisionHydrator:
  HerdSharingImportApplying,
  CollaborationRevisionHydrating
{
  func hydrateCollaborationRevisions(for herdPublicID: UUID) async throws {
    throw HerdSharingActionError.bridgeImportFailed(
      "accepted participant reference commit boundary regression"
    )
  }

  func applyImport(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector
  ) async throws -> HerdSharingSwiftDataImportApplication {
    throw HerdSharingActionError.bridgeImportFailed(
      "unexpected import application after revision hydration failure"
    )
  }
}

@MainActor
final class HerdSharingAcceptedInvitationScopeTests: XCTestCase {
  private static let participantAccountRecordName = "test-participant-account"

  func testUnscopedParticipantImportRecoversConflictingReferenceBeforeOwnershipMarker()
    async throws
  {
    let directory = makeDirectory(named: "unscoped-participant-reference")
    let suiteName = "HerdSharingAcceptedInvitationUnscopedReference.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let rootRecordID = CKRecord.ID(
      recordName: "unscoped-root",
      zoneID: CKRecordZone.ID(zoneName: "unscoped-zone", ownerName: "unscoped-owner")
    )
    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    var expectedHerdPublicID: UUID?
    var referenceWasDurableWhenOwnershipWasRecorded = false
    let remoteVerifier = StubAcceptedParticipantRemoteVerifier(
      status: .present(permission: .readWrite)
    )
    let store = try await makeStore(
      directory: directory,
      recorder: { herdPublicID in
        referenceWasDurableWhenOwnershipWasRecorded =
          herdPublicID == expectedHerdPublicID
          && referenceStore.reference(for: herdPublicID) == HerdSharingAcceptedParticipantReference(
            rootRecordID: rootRecordID,
            participantAccountRecordName: Self.participantAccountRecordName
          )
      },
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] },
      acceptedParticipantRemoteVerifier: remoteVerifier
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let acceptedHerd = try await seedHerd(
      name: "Unscoped Participant Herd",
      updatedAt: Date(timeIntervalSince1970: 90),
      into: store,
      sharedStore: sharedStore
    )
    expectedHerdPublicID = acceptedHerd.publicID
    let acceptedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: acceptedHerd.publicID, in: sharedStore).first
    )
    recordIDsByObjectID[acceptedRecord.objectID] = rootRecordID
    let primaryKey = "accepted-reference.\(acceptedHerd.publicID.uuidString.lowercased())"
    defaults.set(
      try JSONEncoder().encode(
        HerdSharingAcceptedParticipantReference(
          rootRecordName: "conflicting-import-primary",
          rootZoneName: "conflicting-import-primary-zone",
          rootZoneOwnerName: "conflicting-import-primary-owner",
          participantAccountRecordName: Self.participantAccountRecordName
        )
      ),
      forKey: primaryKey
    )
    defaults.set(
      try JSONEncoder().encode(
        HerdSharingAcceptedParticipantReference(
          rootRecordName: "conflicting-import-recovery",
          rootZoneName: "conflicting-import-recovery-zone",
          rootZoneOwnerName: "conflicting-import-recovery-owner",
          participantAccountRecordName: Self.participantAccountRecordName
        )
      ),
      forKey: "\(primaryKey).recovery"
    )

    do {
      _ = try await store.importSharedRecordsIntoSwiftData(
        importer: AcceptedReferenceFailingRevisionHydrator()
      )
      XCTFail("Expected revision hydration to fail after participant provenance commits.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportRequiresAccessVerification(let message) = error else {
        return XCTFail("Expected access verification failure, received \(error).")
      }
      XCTAssertTrue(message.contains("reference commit boundary regression"))
    }

    XCTAssertTrue(referenceWasDurableWhenOwnershipWasRecorded)
    XCTAssertEqual(
      remoteVerifier.references,
      [
        HerdSharingAcceptedParticipantReference(
          rootRecordID: rootRecordID,
          participantAccountRecordName: Self.participantAccountRecordName
        )
      ]
    )
    XCTAssertEqual(
      referenceStore.reference(for: acceptedHerd.publicID),
      HerdSharingAcceptedParticipantReference(
        rootRecordID: rootRecordID,
        participantAccountRecordName: Self.participantAccountRecordName
      )
    )
  }

  func testUnscopedParticipantImportWithoutExactRootDoesNotCommitOwnership() async throws {
    let directory = makeDirectory(named: "unscoped-participant-missing-root")
    let suiteName = "HerdSharingAcceptedInvitationMissingUnscopedRoot.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    var recordedOwnership: [UUID] = []
    let store = try await makeStore(
      directory: directory,
      recorder: { recordedOwnership.append($0) },
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: { _ in nil }
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let acceptedHerd = try await seedHerd(
      name: "Unidentified Participant Herd",
      updatedAt: Date(timeIntervalSince1970: 91),
      into: store,
      sharedStore: sharedStore
    )
    let importer = SwiftDataHerdSharingActor(
      modelContainer: try TestSupport.makeModelContainer()
    )

    do {
      _ = try await store.importSharedRecordsIntoSwiftData(importer: importer)
      XCTFail("Expected missing exact CloudKit root identity to fail closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportRequiresAccessVerification(let message) = error else {
        return XCTFail("Expected access verification failure, received \(error).")
      }
      XCTAssertTrue(message.contains("no exact CloudKit record identity"))
    }

    XCTAssertTrue(recordedOwnership.isEmpty)
    XCTAssertNil(referenceStore.reference(for: acceptedHerd.publicID))
  }

  func testAcceptedInvitationConsistencyFailureInvalidatesCachedWritablePolicy() async throws {
    let suiteName = "AcceptedInvitationPolicyInvalidation.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let storageKey = "pending-scopes"
    defaults.set(Data("corrupt-invitation-state".utf8), forKey: storageKey)
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      currentAccountRecordNameProvider: { "participant-account" }
    )
    let acceptedScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "corrupt-recovery-share",
      rootRecordName: "corrupt-recovery-root",
      rootZoneName: "corrupt-recovery-zone",
      rootZoneOwnerName: "owner",
      participantAccountRecordName: "participant-account"
    )
    let base = InvitationConsistencyFailureRepository(
      scopeStore: scopeStore,
      acceptedScope: acceptedScope
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(participantCount: 1)
        .applyingCreationState(.ready)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )
    let invitation = HerdShareInvitation(
      token: HerdShareToken(),
      containerIdentifier: "iCloud.test",
      shareIdentifier: "corrupt-recovery-share",
      rootIdentifier: "corrupt-recovery-root",
      ownerIdentifier: "owner",
      ownerDisplayName: "Owner",
      participantRole: .privateUser,
      permission: .readOnly,
      status: .pending,
      shareURL: nil
    )

    do {
      _ = try await repository.acceptShareInvitation(invitation, storageMode: .iCloud)
      XCTFail("Expected staged corrupt invitation recovery to fail closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        return XCTFail("Expected bridge consistency failure, got \(error)")
      }
    }

    XCTAssertEqual(base.acceptedInvitationIDs, [invitation.id])
    XCTAssertTrue(scopeStore.hasCorruptRecoveryPending)
    XCTAssertTrue(try scopeStore.pendingScopes().isEmpty)
    XCTAssertNil(policy.snapshot.access)
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
  }

  func testAcceptedRootResolutionSelectsExactHerdWhenSharedStoreContainsMultipleRoots() async throws {
    let directory = makeDirectory(named: "root-resolution")
    let store = try await makeStore(directory: directory)
    let sharedStore = try XCTUnwrap(store.sharedStore)

    let existingHerd = try await seedHerd(
      name: "Existing Accepted Herd",
      updatedAt: Date(timeIntervalSince1970: 20),
      into: store,
      sharedStore: sharedStore
    )
    let invitedHerd = try await seedHerd(
      name: "New Invitation Herd",
      updatedAt: Date(timeIntervalSince1970: 10),
      into: store,
      sharedStore: sharedStore
    )

    let existingRecordID = CKRecord.ID(
      recordName: "existing-root",
      zoneID: CKRecordZone.ID(zoneName: "existing-zone", ownerName: "existing-owner")
    )
    let invitedRecordID = CKRecord.ID(
      recordName: "invited-root",
      zoneID: CKRecordZone.ID(zoneName: "invited-zone", ownerName: "invited-owner")
    )
    let records = try store.fetchSharedHerdRecords(in: sharedStore)
    let recordIDsByObjectID = Dictionary(uniqueKeysWithValues: records.map { record in
      let recordID = record.publicID == invitedHerd.publicID.uuidString
        ? invitedRecordID
        : existingRecordID
      return (record.objectID, recordID)
    })
    let scope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "invited-share",
      rootRecordName: invitedRecordID.recordName,
      rootZoneName: invitedRecordID.zoneID.zoneName,
      rootZoneOwnerName: invitedRecordID.zoneID.ownerName,
      acceptedAt: Date(timeIntervalSince1970: 30),
      participantAccountRecordName: Self.participantAccountRecordName
    )

    let resolvedPublicID = try store.acceptedHerdPublicID(
      matching: scope,
      in: sharedStore,
      recordIDProvider: { recordIDsByObjectID[$0] }
    )

    XCTAssertNotEqual(existingHerd.publicID, invitedHerd.publicID)
    XCTAssertEqual(resolvedPublicID, invitedHerd.publicID)
  }

  func testScopedAcceptedImportRecordsProvenanceOnlyForRequestedHerd() async throws {
    let directory = makeDirectory(named: "scoped-import")
    var recordedHerdIDs: [UUID] = []
    let store = try await makeStore(
      directory: directory,
      recorder: { recordedHerdIDs.append($0) }
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)

    let existingHerd = try await seedHerd(
      name: "Existing Accepted Herd",
      updatedAt: Date(timeIntervalSince1970: 20),
      into: store,
      sharedStore: sharedStore
    )
    let invitedHerd = try await seedHerd(
      name: "New Invitation Herd",
      updatedAt: Date(timeIntervalSince1970: 10),
      into: store,
      sharedStore: sharedStore
    )
    let targetContainer = try TestSupport.makeModelContainer()
    let targetActor = SwiftDataHerdSharingActor(modelContainer: targetContainer)

    let result = try await store.importAcceptedBridgeRecordsIntoSwiftData(
      for: invitedHerd.publicID,
      importer: targetActor
    )

    XCTAssertEqual(result.herdName, invitedHerd.name)
    XCTAssertEqual(recordedHerdIDs, [invitedHerd.publicID])
    let importedHerds = try targetContainer.mainContext.fetch(FetchDescriptor<Herd>())
    XCTAssertEqual(importedHerds.count, 1)
    XCTAssertEqual(importedHerds.first?.publicID, invitedHerd.publicID)
    XCTAssertFalse(importedHerds.contains { $0.publicID == existingHerd.publicID })
  }

  func testAcceptedShareScopePersistsAcrossStoreRecreationUntilRemoved() throws {
    let suiteName = "HerdSharingAcceptedInvitationScope.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let storageKey = "pending-scopes"
    let scope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "share-two",
      rootRecordName: "root-two",
      rootZoneName: "zone-two",
      rootZoneOwnerName: "owner-two",
      acceptedAt: Date(timeIntervalSince1970: 2),
      participantAccountRecordName: Self.participantAccountRecordName
    )

    try HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    ).record(scope)

    let reloadedStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    XCTAssertEqual(try reloadedStore.pendingScopes(), [scope])

    reloadedStore.remove(scope)
    XCTAssertTrue(
      try HerdSharingAcceptedShareImportScopeStore(
        defaults: defaults,
        storageKey: storageKey,
        currentAccountRecordNameProvider: { Self.participantAccountRecordName }
      ).pendingScopes().isEmpty
    )
  }

  func testScopesWithSameShareRecordNameInDifferentZonesRemainIndependent() throws {
    let suiteName = "HerdSharingAcceptedInvitationScopeIdentity.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let firstScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "same-share-record-name",
      rootRecordName: "same-root-record-name",
      rootZoneName: "zone-a",
      rootZoneOwnerName: "owner-a",
      acceptedAt: Date(timeIntervalSince1970: 1),
      participantAccountRecordName: Self.participantAccountRecordName
    )
    let secondScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "same-share-record-name",
      rootRecordName: "same-root-record-name",
      rootZoneName: "zone-b",
      rootZoneOwnerName: "owner-b",
      acceptedAt: Date(timeIntervalSince1970: 2),
      participantAccountRecordName: Self.participantAccountRecordName
    )

    try store.record(firstScope)
    try store.record(secondScope)

    let persisted = try store.pendingScopes()
    XCTAssertEqual(persisted.count, 2)
    XCTAssertTrue(persisted.contains(firstScope))
    XCTAssertTrue(persisted.contains(secondScope))

    store.remove(firstScope)
    XCTAssertEqual(try store.pendingScopes(), [secondScope])
  }

  func testResolvedAcceptedScopePersistsExactRootAndParticipantAccountForVerification() throws {
    let suiteName = "HerdSharingAcceptedParticipantReference.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let herdPublicID = UUID()
    let scope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "accepted-share",
      rootRecordName: "accepted-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner",
      participantAccountRecordName: Self.participantAccountRecordName
    )
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )

    scopeStore.recordParticipantReference(scope, for: herdPublicID)

    let reloadedReferenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    XCTAssertEqual(
      reloadedReferenceStore.reference(for: herdPublicID),
      HerdSharingAcceptedParticipantReference(scope: scope)
    )
  }

  func testRemoteVerifiedAccessRecoverablyReplacesConflictingParticipantReferences() async throws {
    let directory = makeDirectory(named: "conflicting-participant-reference-recovery")
    let suiteName = "HerdSharingAcceptedParticipantConflictRecovery.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let keyPrefix = "accepted-reference"
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let remoteVerifier = StubAcceptedParticipantRemoteVerifier(
      status: .present(permission: .readOnly)
    )
    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] },
      acceptedParticipantRemoteVerifier: remoteVerifier
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let acceptedHerd = try await seedHerd(
      name: "Conflicting Provenance Participant Herd",
      updatedAt: Date(timeIntervalSince1970: 92),
      into: store,
      sharedStore: sharedStore
    )
    let acceptedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: acceptedHerd.publicID, in: sharedStore).first
    )
    let authoritativeRootRecordID = CKRecord.ID(
      recordName: "authoritative-root",
      zoneID: CKRecordZone.ID(
        zoneName: "authoritative-zone",
        ownerName: "authoritative-owner"
      )
    )
    recordIDsByObjectID[acceptedRecord.objectID] = authoritativeRootRecordID

    let conflictingPrimary = HerdSharingAcceptedParticipantReference(
      rootRecordName: "conflicting-primary-root",
      rootZoneName: "conflicting-primary-zone",
      rootZoneOwnerName: "conflicting-primary-owner",
      participantAccountRecordName: Self.participantAccountRecordName
    )
    let conflictingRecovery = HerdSharingAcceptedParticipantReference(
      rootRecordName: "conflicting-recovery-root",
      rootZoneName: "conflicting-recovery-zone",
      rootZoneOwnerName: "conflicting-recovery-owner",
      participantAccountRecordName: Self.participantAccountRecordName
    )
    let primaryData = try JSONEncoder().encode(conflictingPrimary)
    let recoveryData = try JSONEncoder().encode(conflictingRecovery)
    let primaryKey = "\(keyPrefix).\(acceptedHerd.publicID.uuidString.lowercased())"
    defaults.set(primaryData, forKey: primaryKey)
    defaults.set(recoveryData, forKey: "\(primaryKey).recovery")

    let access = try await store.fetchSharingAccess(for: acceptedHerd)

    let authoritativeReference = HerdSharingAcceptedParticipantReference(
      rootRecordID: authoritativeRootRecordID,
      participantAccountRecordName: Self.participantAccountRecordName
    )
    XCTAssertEqual(access.permission, .readOnly)
    XCTAssertEqual(remoteVerifier.references, [authoritativeReference])
    XCTAssertEqual(
      try referenceStore.recoverableReference(for: acceptedHerd.publicID),
      authoritativeReference
    )
    let backupPrefix =
      "\(keyPrefix).corrupt-backup.\(acceptedHerd.publicID.uuidString.lowercased()).authoritative-replacement-"
    let backupData = defaults.dictionaryRepresentation()
      .filter { $0.key.hasPrefix(backupPrefix) }
      .values
      .compactMap { $0 as? Data }
    XCTAssertEqual(Set(backupData), Set([primaryData, recoveryData]))
  }

  func testParticipantAbsenceVerificationRejectsDifferentCurrentAccountBeforeCloudKitLookup() async throws {
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner",
      participantAccountRecordName: "account-a"
    )
    let verifier = CloudKitHerdSharingRemoteAcceptedParticipantVerifier(
      currentAccountRecordNameProvider: { "account-b" }
    )

    do {
      _ = try await verifier.status(for: reference)
      XCTFail("Expected an iCloud account mismatch to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(
        error,
        .bridgeConsistencyFailed(
          "The accepted CloudKit Herd belongs to a different iCloud account than the account currently signed in. Participant state was not detached."
        )
      )
    }
  }

  func testParticipantAbsenceLookupRejectsAccountChangeBeforeReturningAbsent() async throws {
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner",
      participantAccountRecordName: "account-a"
    )
    var accountRecordNames = ["account-a", "account-b"]
    var recordLookupCount = 0
    let verifier = CloudKitHerdSharingRemoteAcceptedParticipantVerifier(
      currentAccountRecordNameProvider: {
        accountRecordNames.removeFirst()
      },
      sharedRecordProvider: { _ -> CKRecord in
        recordLookupCount += 1
        throw CKError(.unknownItem)
      }
    )

    do {
      _ = try await verifier.status(for: reference)
      XCTFail("Expected an account change during participant lookup to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(
        error,
        .bridgeConsistencyFailed(
          "The accepted CloudKit Herd belongs to a different iCloud account than the account currently signed in. Participant state was not detached."
        )
      )
    }

    XCTAssertEqual(recordLookupCount, 1)
    XCTAssertTrue(accountRecordNames.isEmpty)
  }

  func testParticipantPresenceReturnsAuthoritativeRemotePermission() async throws {
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner",
      participantAccountRecordName: "account-a"
    )
    let rootRecord = CKRecord(
      recordType: "SharedHerdRecord",
      recordID: reference.rootRecordID
    )
    var accountRecordNames = ["account-a", "account-a"]
    var permissionLookupCount = 0
    let verifier = CloudKitHerdSharingRemoteAcceptedParticipantVerifier(
      currentAccountRecordNameProvider: {
        accountRecordNames.removeFirst()
      },
      sharedRecordProvider: { recordID in
        XCTAssertEqual(recordID, reference.rootRecordID)
        return rootRecord
      },
      sharedPermissionProvider: { record in
        XCTAssertEqual(record.recordID, reference.rootRecordID)
        permissionLookupCount += 1
        return .readOnly
      }
    )

    let status = try await verifier.status(for: reference)

    XCTAssertEqual(status, .present(permission: .readOnly))
    XCTAssertEqual(permissionLookupCount, 1)
    XCTAssertTrue(accountRecordNames.isEmpty)
  }

  func testParticipantAbsenceVerificationRejectsReferenceWithoutAcceptingAccount() async throws {
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner"
    )
    var accountLookupWasRequested = false
    let verifier = CloudKitHerdSharingRemoteAcceptedParticipantVerifier(
      currentAccountRecordNameProvider: {
        accountLookupWasRequested = true
        return Self.participantAccountRecordName
      }
    )

    do {
      _ = try await verifier.status(for: reference)
      XCTFail("Expected missing participant account provenance to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(
        error,
        .bridgeConsistencyFailed(
          "The stored accepted-share provenance has no originating iCloud account identity. Participant state was not detached."
        )
      )
      XCTAssertFalse(accountLookupWasRequested)
    }
  }

  func testExistingAcceptedAccessBackfillsExactParticipantRootForVerifiedCurrentAccount() async throws {
    let directory = makeDirectory(named: "restored-participant-backfill")
    let suiteName = "HerdSharingAcceptedParticipantBackfill.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let keyPrefix = "accepted-reference"
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let remoteVerifier = StubAcceptedParticipantRemoteVerifier(
      status: .present(permission: .readWrite)
    )
    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] },
      acceptedParticipantRemoteVerifier: remoteVerifier
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let acceptedHerd = try await seedHerd(
      name: "Restored Participant Herd",
      updatedAt: Date(timeIntervalSince1970: 40),
      into: store,
      sharedStore: sharedStore
    )
    let acceptedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: acceptedHerd.publicID, in: sharedStore).first
    )
    let expectedRecordID = CKRecord.ID(
      recordName: "restored-root",
      zoneID: CKRecordZone.ID(zoneName: "restored-zone", ownerName: "restored-owner")
    )
    recordIDsByObjectID[acceptedRecord.objectID] = expectedRecordID

    XCTAssertNil(referenceStore.reference(for: acceptedHerd.publicID))
    let access = try await store.fetchSharingAccess(for: acceptedHerd)

    XCTAssertEqual(access.bridgeLocation, .acceptedSharedStore)
    XCTAssertEqual(access.permission, .readWrite)
    XCTAssertTrue(access.canExportLocalChangesToBridge)
    let expectedReference = HerdSharingAcceptedParticipantReference(
      rootRecordID: expectedRecordID,
      participantAccountRecordName: Self.participantAccountRecordName
    )
    XCTAssertEqual(remoteVerifier.references, [expectedReference])
    let reloadedReferenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    XCTAssertEqual(
      reloadedReferenceStore.reference(for: acceptedHerd.publicID),
      expectedReference
    )

    remoteVerifier.setStatus(.present(permission: .readOnly))
    let downgradedAccess = try await store.fetchSharingAccess(for: acceptedHerd)

    XCTAssertEqual(downgradedAccess.permission, .readOnly)
    XCTAssertFalse(downgradedAccess.canExportLocalChangesToBridge)
    XCTAssertEqual(remoteVerifier.references, [expectedReference, expectedReference])

    let exportContainer = try TestSupport.makeModelContainer()
    let exportContext = exportContainer.mainContext
    let exportHerd = Herd(
      publicID: acceptedHerd.publicID,
      name: acceptedHerd.name,
      createdAt: acceptedHerd.createdAt,
      updatedAt: acceptedHerd.updatedAt
    )
    exportContext.insert(exportHerd)
    try exportContext.save()
    let downgradedExport = try await SwiftDataHerdSharingActor(
      modelContainer: exportContainer
    ).makeExport(
      for: exportHerd.toSummary(),
      storeDescription: "downgraded participant export"
    )

    do {
      _ = try await store.syncBridgeRecordsFromSnapshot(downgradedExport)
      XCTFail("Expected inner bridge export to reject remotely downgraded permission.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .readOnlyShareCannotWrite)
    }
    XCTAssertEqual(remoteVerifier.references.count, 3)
  }

  func testExistingAcceptedAccessDoesNotBackfillWhenRemoteRootIsAbsentForCurrentAccount() async throws {
    let directory = makeDirectory(named: "restored-participant-backfill-absent")
    let suiteName = "HerdSharingAcceptedParticipantBackfillAbsent.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let remoteVerifier = StubAcceptedParticipantRemoteVerifier(status: .absent)
    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] },
      acceptedParticipantRemoteVerifier: remoteVerifier
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let acceptedHerd = try await seedHerd(
      name: "Stale Restored Participant Herd",
      updatedAt: Date(timeIntervalSince1970: 41),
      into: store,
      sharedStore: sharedStore
    )
    let acceptedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: acceptedHerd.publicID, in: sharedStore).first
    )
    recordIDsByObjectID[acceptedRecord.objectID] = CKRecord.ID(
      recordName: "stale-root",
      zoneID: CKRecordZone.ID(zoneName: "stale-zone", ownerName: "stale-owner")
    )

    do {
      _ = try await store.fetchSharingAccess(for: acceptedHerd)
      XCTFail("Expected stale accepted-store data to remain unverified.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(
        error,
        .bridgeConsistencyFailed(
          "The accepted Herd root is no longer available to the current iCloud account. The cached participant relationship was not trusted."
        )
      )
    }
    XCTAssertNil(referenceStore.reference(for: acceptedHerd.publicID))
  }

  func testExistingAcceptedAccessRevalidatesMatchingSavedReferenceBeforePublishingAccess() async throws {
    let directory = makeDirectory(named: "recorded-participant-revalidation")
    let suiteName = "HerdSharingAcceptedParticipantRevalidation.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let remoteVerifier = StubAcceptedParticipantRemoteVerifier(status: .absent)
    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] },
      acceptedParticipantRemoteVerifier: remoteVerifier
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let acceptedHerd = try await seedHerd(
      name: "Revoked Recorded Participant Herd",
      updatedAt: Date(timeIntervalSince1970: 42),
      into: store,
      sharedStore: sharedStore
    )
    let acceptedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: acceptedHerd.publicID, in: sharedStore).first
    )
    let rootRecordID = CKRecord.ID(
      recordName: "revoked-recorded-root",
      zoneID: CKRecordZone.ID(
        zoneName: "revoked-recorded-zone",
        ownerName: "revoked-recorded-owner"
      )
    )
    recordIDsByObjectID[acceptedRecord.objectID] = rootRecordID
    let savedReference = HerdSharingAcceptedParticipantReference(
      rootRecordID: rootRecordID,
      participantAccountRecordName: Self.participantAccountRecordName
    )
    referenceStore.record(savedReference, for: acceptedHerd.publicID)

    do {
      _ = try await store.fetchSharingAccess(for: acceptedHerd)
      XCTFail("Expected a remotely revoked saved participant relationship to remain blocked.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(
        error,
        .bridgeConsistencyFailed(
          "The accepted Herd root is no longer available to the current iCloud account. The cached participant relationship was not trusted."
        )
      )
    }

    XCTAssertEqual(remoteVerifier.references, [savedReference])
    XCTAssertEqual(referenceStore.reference(for: acceptedHerd.publicID), savedReference)
  }

  func testManualRetryAfterProcessRestartConsumesPersistedInvitationBeforeCurrentHerd() async throws {
    let directory = makeDirectory(named: "manual-persisted-retry")
    let suiteName = "HerdSharingAcceptedInvitationManualRetry.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let storageKey = "pending-scopes"
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let invitedRecordID = CKRecord.ID(
      recordName: "manual-invited-root",
      zoneID: CKRecordZone.ID(zoneName: "manual-zone", ownerName: "manual-owner")
    )
    let scope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "manual-share",
      rootRecordName: invitedRecordID.recordName,
      rootZoneName: invitedRecordID.zoneID.zoneName,
      rootZoneOwnerName: invitedRecordID.zoneID.ownerName,
      participantAccountRecordName: Self.participantAccountRecordName
    )
    try HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    ).record(scope)
    let reloadedScopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    XCTAssertNil(reloadedScopeStore.immediateImportScope)

    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: reloadedScopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] }
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let invitedHerd = try await seedHerd(
      name: "Persisted Invitation Herd",
      updatedAt: Date(timeIntervalSince1970: 50),
      into: store,
      sharedStore: sharedStore
    )
    let invitedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: invitedHerd.publicID, in: sharedStore).first
    )
    recordIDsByObjectID[invitedRecord.objectID] = invitedRecordID

    let targetContainer = try TestSupport.makeModelContainer()
    let targetContext = targetContainer.mainContext
    let currentHerd = Herd(
      publicID: UUID(),
      name: "Current Local Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    targetContext.insert(currentHerd)
    try targetContext.save()
    let currentSummary = currentHerd.toSummary()
    let repository = CoreDataHerdSharingRepository(context: targetContext, store: store)

    let result = try await repository.importSharedBridgeData(
      herd: currentSummary,
      storageMode: .iCloud
    )

    XCTAssertTrue(result.message.contains(invitedHerd.name))
    XCTAssertTrue(try reloadedScopeStore.pendingScopes().isEmpty)
    let importedHerds = try targetContext.fetch(FetchDescriptor<Herd>())
    XCTAssertEqual(importedHerds.count, 1)
    XCTAssertEqual(importedHerds.first?.publicID, invitedHerd.publicID)
    XCTAssertFalse(importedHerds.contains { $0.publicID == currentSummary.publicID })
    XCTAssertEqual(
      referenceStore.reference(for: invitedHerd.publicID),
      HerdSharingAcceptedParticipantReference(
        rootRecordID: invitedRecordID,
        participantAccountRecordName: Self.participantAccountRecordName
      )
    )
  }

  func testSyncRetryAfterProcessRestartImportsPendingInvitationWithoutExportingCurrentHerd() async throws {
    let directory = makeDirectory(named: "sync-persisted-retry")
    let suiteName = "HerdSharingAcceptedInvitationSyncRetry.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let storageKey = "pending-scopes"
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let invitedRecordID = CKRecord.ID(
      recordName: "sync-invited-root",
      zoneID: CKRecordZone.ID(zoneName: "sync-zone", ownerName: "sync-owner")
    )
    let scope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "sync-share",
      rootRecordName: invitedRecordID.recordName,
      rootZoneName: invitedRecordID.zoneID.zoneName,
      rootZoneOwnerName: invitedRecordID.zoneID.ownerName,
      participantAccountRecordName: Self.participantAccountRecordName
    )
    try HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    ).record(scope)
    let reloadedScopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    XCTAssertNil(reloadedScopeStore.immediateImportScope)

    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: reloadedScopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] }
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let privateStore = try XCTUnwrap(store.privateStore)
    let invitedHerd = try await seedHerd(
      name: "Persisted Sync Invitation Herd",
      updatedAt: Date(timeIntervalSince1970: 60),
      into: store,
      sharedStore: sharedStore
    )
    let invitedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: invitedHerd.publicID, in: sharedStore).first
    )
    recordIDsByObjectID[invitedRecord.objectID] = invitedRecordID

    let targetContainer = try TestSupport.makeModelContainer()
    let targetContext = targetContainer.mainContext
    let currentHerd = Herd(
      publicID: UUID(),
      name: "Current Sync Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    targetContext.insert(currentHerd)
    try targetContext.save()
    let currentSummary = currentHerd.toSummary()
    let repository = CoreDataHerdSharingRepository(context: targetContext, store: store)

    let result = try await repository.syncSharedBridgeData(
      herd: currentSummary,
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Accepted invitation imported")
    XCTAssertTrue(result.message.contains(invitedHerd.name))
    XCTAssertTrue(try reloadedScopeStore.pendingScopes().isEmpty)
    XCTAssertTrue(
      try store.fetchSharedHerdRecords(publicID: currentSummary.publicID, in: privateStore).isEmpty
    )
    let importedHerds = try targetContext.fetch(FetchDescriptor<Herd>())
    XCTAssertEqual(importedHerds.count, 1)
    XCTAssertEqual(importedHerds.first?.publicID, invitedHerd.publicID)
    XCTAssertFalse(importedHerds.contains { $0.publicID == currentSummary.publicID })
  }

  func testCorruptInvitationRecoveryBacksUpBytesAndRequiresExactInvitationScope() async throws {
    let directory = makeDirectory(named: "corrupt-recovery")
    let suiteName = "HerdSharingAcceptedInvitationCorruptRecovery.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let storageKey = "pending-scopes"
    let corruptData = Data("not-valid-json".utf8)
    defaults.set(corruptData, forKey: storageKey)
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: "accepted-reference"
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      participantReferenceStore: referenceStore,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let remoteVerifier = StubAcceptedParticipantRemoteVerifier(
      status: .present(permission: .readWrite)
    )
    var recordIDsByObjectID: [NSManagedObjectID: CKRecord.ID] = [:]
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: { recordIDsByObjectID[$0] },
      acceptedParticipantRemoteVerifier: remoteVerifier
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let acceptedHerd = try await seedHerd(
      name: "Recovered Accepted Herd",
      updatedAt: Date(timeIntervalSince1970: 70),
      into: store,
      sharedStore: sharedStore
    )
    let acceptedRecord = try XCTUnwrap(
      try store.fetchSharedHerdRecords(publicID: acceptedHerd.publicID, in: sharedStore).first
    )
    let acceptedRecordID = CKRecord.ID(
      recordName: "recovered-root",
      zoneID: CKRecordZone.ID(zoneName: "recovered-zone", ownerName: "recovered-owner")
    )
    recordIDsByObjectID[acceptedRecord.objectID] = acceptedRecordID

    let targetContainer = try TestSupport.makeModelContainer()
    let repository = CoreDataHerdSharingRepository(context: targetContainer.mainContext, store: store)
    do {
      _ = try await repository.importSharedBridgeData(herd: nil, storageMode: .iCloud)
      XCTFail("Expected corrupt recovery to refuse an unscoped shared root.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportRequiresAccessVerification(let message) = error else {
        XCTFail("Expected bridgeImportRequiresAccessVerification, received \(error).")
        return
      }
      XCTAssertTrue(message.contains("exact invitation identity was lost"))
    }

    XCTAssertFalse(scopeStore.hasCorruptPersistedState)
    XCTAssertTrue(scopeStore.hasCorruptRecoveryPending)
    XCTAssertNil(referenceStore.reference(for: acceptedHerd.publicID))
    XCTAssertTrue(remoteVerifier.references.isEmpty)
    XCTAssertTrue(try targetContainer.mainContext.fetch(FetchDescriptor<Herd>()).isEmpty)
    let backupKeys = defaults.dictionaryRepresentation().keys.filter {
      $0.hasPrefix("\(storageKey).corrupt-backup-")
    }
    XCTAssertEqual(backupKeys.count, 1)
    XCTAssertEqual(defaults.data(forKey: try XCTUnwrap(backupKeys.first)), corruptData)

    let restoredScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "reopened-share",
      rootRecordName: acceptedRecordID.recordName,
      rootZoneName: acceptedRecordID.zoneID.zoneName,
      rootZoneOwnerName: acceptedRecordID.zoneID.ownerName,
      participantAccountRecordName: Self.participantAccountRecordName,
      acceptanceState: .pending
    )
    do {
      try scopeStore.record(restoredScope)
      XCTFail("Expected the first reopened invitation to stage, not clear, corrupt recovery.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridgeConsistencyFailed, received \(error).")
        return
      }
      XCTAssertTrue(message.contains("staged as the proposed recovery target"))
    }
    XCTAssertTrue(scopeStore.hasCorruptRecoveryPending)
    XCTAssertNil(scopeStore.immediateImportScope)

    try scopeStore.record(restoredScope)

    XCTAssertFalse(scopeStore.hasCorruptRecoveryPending)
    XCTAssertEqual(scopeStore.immediateImportScope, restoredScope)
    XCTAssertEqual(try scopeStore.pendingScopes(), [restoredScope])

    let result = try await repository.importSharedBridgeData(herd: nil, storageMode: .iCloud)

    XCTAssertTrue(result.message.contains(acceptedHerd.name))
    XCTAssertTrue(try scopeStore.pendingScopes().isEmpty)
    XCTAssertEqual(
      referenceStore.reference(for: acceptedHerd.publicID),
      HerdSharingAcceptedParticipantReference(scope: restoredScope)
    )
    let importedHerds = try targetContainer.mainContext.fetch(FetchDescriptor<Herd>())
    XCTAssertEqual(importedHerds.count, 1)
    XCTAssertEqual(importedHerds.first?.publicID, acceptedHerd.publicID)
  }

  func testCorruptInvitationRecoveryDoesNotGuessAmongMultipleSharedRoots() async throws {
    let directory = makeDirectory(named: "corrupt-recovery-ambiguous")
    let suiteName = "HerdSharingAcceptedInvitationCorruptAmbiguous.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let storageKey = "pending-scopes"
    let corruptData = Data("not-valid-json".utf8)
    defaults.set(corruptData, forKey: storageKey)
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    _ = try await seedHerd(
      name: "First Accepted Herd",
      updatedAt: Date(timeIntervalSince1970: 80),
      into: store,
      sharedStore: sharedStore
    )
    _ = try await seedHerd(
      name: "Second Accepted Herd",
      updatedAt: Date(timeIntervalSince1970: 81),
      into: store,
      sharedStore: sharedStore
    )

    let targetContainer = try TestSupport.makeModelContainer()
    let repository = CoreDataHerdSharingRepository(context: targetContainer.mainContext, store: store)
    do {
      _ = try await repository.importSharedBridgeData(herd: nil, storageMode: .iCloud)
      XCTFail("Expected ambiguous corrupt recovery to remain fail-closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportRequiresAccessVerification(let message) = error else {
        XCTFail("Expected bridgeImportRequiresAccessVerification, received \(error).")
        return
      }
      XCTAssertTrue(message.contains("multiple accepted shared Herd roots"))
    }

    XCTAssertFalse(scopeStore.hasCorruptPersistedState)
    XCTAssertTrue(scopeStore.hasCorruptRecoveryPending)
    let hasPendingScope = try await scopeStore.hasPendingScopeForCurrentAccount()
    XCTAssertTrue(hasPendingScope)
    let backupKeys = defaults.dictionaryRepresentation().keys.filter {
      $0.hasPrefix("\(storageKey).corrupt-backup-")
    }
    XCTAssertEqual(backupKeys.count, 1)
    XCTAssertEqual(defaults.data(forKey: try XCTUnwrap(backupKeys.first)), corruptData)
  }

  func testConfirmedLegacyScopeAbsenceRetiresCurrentAccountBlockAndPreservesOtherAccountRecovery()
    async throws
  {
    let directory = makeDirectory(named: "legacy-scope-retirement")
    let suiteName = "HerdSharingAcceptedInvitationLegacyRetirement.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let storageKey = "pending-scopes"
    let scope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "legacy-share",
      rootRecordName: "legacy-root",
      rootZoneName: "legacy-zone",
      rootZoneOwnerName: "legacy-owner",
      acceptedAt: Date(timeIntervalSince1970: 1),
      acceptanceState: .legacyUnknown
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    try scopeStore.record(scope)

    var now = Date(timeIntervalSince1970: 100)
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore,
      acceptedParticipantRemoteVerifier: StubAcceptedParticipantRemoteVerifier(status: .absent),
      acceptedScopeRemoteAbsenceConfirmationInterval: 30,
      nowProvider: { now }
    )
    let targetContainer = try TestSupport.makeModelContainer()
    let importer = SwiftDataHerdSharingActor(modelContainer: targetContainer)

    do {
      _ = try await store.importSharedRecordsIntoSwiftData(importer: importer)
      XCTFail("The first remote absence must remain fail-closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportFailed(let message) = error else {
        return XCTFail("Expected bridgeImportFailed, received \(error).")
      }
      XCTAssertTrue(message.contains("kept the scope fail-closed"))
    }
    let isPendingAfterFirstAbsence = try await scopeStore.hasPendingScopeForCurrentAccount()
    XCTAssertTrue(isPendingAfterFirstAbsence)

    now = now.addingTimeInterval(31)
    do {
      _ = try await store.importSharedRecordsIntoSwiftData(importer: importer)
      XCTFail("The confirming remote absence must report retirement before retrying.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportFailed(let message) = error else {
        return XCTFail("Expected bridgeImportFailed, received \(error).")
      }
      XCTAssertTrue(message.contains("retired for this account"))
    }

    let isPendingAfterConfirmedAbsence = try await scopeStore.hasPendingScopeForCurrentAccount()
    let currentAccountScopes = try await scopeStore.pendingScopesForCurrentAccount()
    XCTAssertFalse(isPendingAfterConfirmedAbsence)
    XCTAssertTrue(currentAccountScopes.isEmpty)
    let retainedScope = try XCTUnwrap(scopeStore.pendingScopes().first)
    XCTAssertEqual(
      retainedScope.ignoredParticipantAccountRecordNames,
      [Self.participantAccountRecordName]
    )

    let otherAccountStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      currentAccountRecordNameProvider: { "other-participant-account" }
    )
    let otherAccountScopes = try await otherAccountStore.pendingScopesForCurrentAccount()
    XCTAssertEqual(otherAccountScopes.count, 1)
    XCTAssertEqual(
      otherAccountScopes.first?.participantAccountRecordName,
      "other-participant-account"
    )
    let isPendingForOtherAccount = try await otherAccountStore.hasPendingScopeForCurrentAccount()
    XCTAssertTrue(isPendingForOtherAccount)
  }

  func testRemotePresenceClearsEarlierAcceptedScopeAbsenceConfirmation() async throws {
    let directory = makeDirectory(named: "accepted-scope-presence-reset")
    let suiteName = "HerdSharingAcceptedInvitationPresenceReset.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let scope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "accepted-share",
      rootRecordName: "accepted-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner",
      acceptedAt: Date(timeIntervalSince1970: 1),
      participantAccountRecordName: Self.participantAccountRecordName,
      acceptanceState: .accepted
    )
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    try scopeStore.record(scope)
    let remoteVerifier = SequencedAcceptedParticipantRemoteVerifier(
      statuses: [.absent, .present(permission: .readWrite), .absent, .absent]
    )
    var now = Date(timeIntervalSince1970: 100)
    let store = try await makeStore(
      directory: directory,
      acceptedShareImportScopeStore: scopeStore,
      acceptedParticipantRemoteVerifier: remoteVerifier,
      acceptedScopeRemoteAbsenceConfirmationInterval: 30,
      nowProvider: { now }
    )
    let importer = SwiftDataHerdSharingActor(modelContainer: try TestSupport.makeModelContainer())

    await assertAcceptedScopeImportFails(store: store, importer: importer)
    XCTAssertEqual(try scopeStore.pendingScopes().first?.remoteAbsenceObservedAt, now)

    now = Date(timeIntervalSince1970: 110)
    await assertAcceptedScopeImportFails(store: store, importer: importer)
    XCTAssertNil(try scopeStore.pendingScopes().first?.remoteAbsenceObservedAt)

    now = Date(timeIntervalSince1970: 131)
    await assertAcceptedScopeImportFails(store: store, importer: importer)
    let restartedWindowScope = try XCTUnwrap(scopeStore.pendingScopes().first)
    XCTAssertEqual(restartedWindowScope.remoteAbsenceObservedAt, now)

    now = Date(timeIntervalSince1970: 162)
    await assertAcceptedScopeImportFails(store: store, importer: importer)
    XCTAssertTrue(try scopeStore.pendingScopes().isEmpty)
    XCTAssertEqual(remoteVerifier.references.count, 4)
  }

  private func assertAcceptedScopeImportFails(
    store: HerdSharingCoreDataStore,
    importer: any HerdSharingImportApplying
  ) async {
    do {
      _ = try await store.importSharedRecordsIntoSwiftData(importer: importer)
      XCTFail("The accepted root has not arrived locally, so scoped import must remain pending.")
    } catch {
      // Expected while the exact accepted root is absent from the local shared bridge.
    }
  }

  private func makeStore(
    directory: URL,
    recorder: @escaping @MainActor (UUID) -> Void = { _ in },
    acceptedShareImportScopeStore: HerdSharingAcceptedShareImportScopeStore? = nil,
    acceptedShareRecordIDProvider: ((NSManagedObjectID) -> CKRecord.ID?)? = nil,
    acceptedParticipantRemoteVerifier: (any HerdSharingRemoteAcceptedParticipantVerifying)? = nil,
    acceptedScopeRemoteAbsenceConfirmationInterval: TimeInterval = 30,
    nowProvider: (@MainActor () -> Date)? = nil
  ) async throws -> HerdSharingCoreDataStore {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suiteName = "HerdSharingAcceptedInvitationScope.store.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let scopeStore = acceptedShareImportScopeStore ?? HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      currentAccountRecordNameProvider: { Self.participantAccountRecordName }
    )
    let remoteVerifier = acceptedParticipantRemoteVerifier
      ?? StubAcceptedParticipantRemoteVerifier(status: .present(permission: .readWrite))
    let store = HerdSharingCoreDataStore(
      storeDirectoryURL: directory,
      journalFileURL: directory.appendingPathComponent("journal.json"),
      acceptedParticipantProvenanceRecorder: recorder,
      acceptedShareImportScopeStore: scopeStore,
      acceptedShareRecordIDProvider: acceptedShareRecordIDProvider,
      acceptedParticipantRemoteVerifier: remoteVerifier,
      acceptedScopeRemoteAbsenceConfirmationInterval:
        acceptedScopeRemoteAbsenceConfirmationInterval,
      nowProvider: nowProvider
    )
    store.persistentContainer.persistentStoreDescriptions = [
      plainStoreDescription(
        at: directory.appendingPathComponent(HerdSharingCoreDataStore.privateStoreFileName)
      ),
      plainStoreDescription(
        at: directory.appendingPathComponent(HerdSharingCoreDataStore.sharedStoreFileName)
      ),
    ]
    try await store.loadIfNeeded()
    return store
  }

  private func seedHerd(
    name: String,
    updatedAt: Date,
    into store: HerdSharingCoreDataStore,
    sharedStore: NSPersistentStore
  ) async throws -> HerdSummary {
    let sourceContainer = try TestSupport.makeModelContainer()
    let sourceContext = sourceContainer.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: name,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: updatedAt
    )
    sourceContext.insert(herd)
    try sourceContext.save()
    let herdSummary = herd.toSummary()
    let sourceActor = SwiftDataHerdSharingActor(modelContainer: sourceContainer)
    let export = try await sourceActor.makeExport(
      for: herdSummary,
      storeDescription: "accepted invitation scope seed"
    )
    _ = try await store.writeBridgeSnapshot(export.snapshot, to: sharedStore)
    return herdSummary
  }

  private func plainStoreDescription(at url: URL) -> NSPersistentStoreDescription {
    let description = NSPersistentStoreDescription(url: url)
    description.type = NSSQLiteStoreType
    description.shouldMigrateStoreAutomatically = true
    description.shouldInferMappingModelAutomatically = true
    return description
  }

  private func makeDirectory(named name: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("HerdSharingAcceptedInvitationScopeTests", isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}

@MainActor
private final class StubAcceptedParticipantRemoteVerifier:
  HerdSharingRemoteAcceptedParticipantVerifying
{
  private var statusValue: HerdSharingRemoteAcceptedParticipantStatus
  private(set) var references: [HerdSharingAcceptedParticipantReference] = []

  init(status: HerdSharingRemoteAcceptedParticipantStatus) {
    statusValue = status
  }

  func setStatus(_ status: HerdSharingRemoteAcceptedParticipantStatus) {
    statusValue = status
  }

  func status(
    for reference: HerdSharingAcceptedParticipantReference
  ) async throws -> HerdSharingRemoteAcceptedParticipantStatus {
    references.append(reference)
    return statusValue
  }
}

@MainActor
private final class SequencedAcceptedParticipantRemoteVerifier:
  HerdSharingRemoteAcceptedParticipantVerifying
{
  private var statuses: [HerdSharingRemoteAcceptedParticipantStatus]
  private(set) var references: [HerdSharingAcceptedParticipantReference] = []

  init(statuses: [HerdSharingRemoteAcceptedParticipantStatus]) {
    self.statuses = statuses
  }

  func status(
    for reference: HerdSharingAcceptedParticipantReference
  ) async throws -> HerdSharingRemoteAcceptedParticipantStatus {
    references.append(reference)
    guard !statuses.isEmpty else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The test remote-status sequence was exhausted."
      )
    }
    return statuses.removeFirst()
  }
}


@MainActor
extension HerdSharingAcceptedInvitationScopeTests {
  func testCurrentAccountImportSelectionFailsClosedWhenAnotherAccountAlsoHasPendingScope() async throws {
    let suiteName = "MixedAccountScope.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      currentAccountRecordNameProvider: { "account-B" }
    )
    let accountAScope = makeMixedAccountScope(
      suffix: "a",
      participantAccountRecordName: "account-A",
      acceptedAt: Date(timeIntervalSince1970: 1)
    )
    let accountBScope = makeMixedAccountScope(
      suffix: "b",
      participantAccountRecordName: "account-B",
      acceptedAt: Date(timeIntervalSince1970: 2)
    )
    try store.record(accountAScope)
    try store.record(accountBScope)

    let hasPendingScope = try await store.hasPendingScopeForCurrentAccount()
    XCTAssertTrue(hasPendingScope)

    do {
      _ = try await store.pendingScopesForCurrentAccount()
      XCTFail("Expected mixed-account recovery state to block import selection.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridgeConsistencyFailed, received \(error).")
        return
      }
      XCTAssertTrue(message.contains("different iCloud account"))
    }

    XCTAssertEqual(try store.pendingScopes(), [accountAScope, accountBScope])
  }

  func testCurrentAccountImportSelectionReturnsAllScopesWhenTheyBelongToSameAccount() async throws {
    let suiteName = "SameAccountScopes.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      currentAccountRecordNameProvider: { "account-A" }
    )
    let firstScope = makeMixedAccountScope(
      suffix: "first",
      participantAccountRecordName: "account-A",
      acceptedAt: Date(timeIntervalSince1970: 1)
    )
    let secondScope = makeMixedAccountScope(
      suffix: "second",
      participantAccountRecordName: "account-A",
      acceptedAt: Date(timeIntervalSince1970: 2)
    )
    try store.record(secondScope)
    try store.record(firstScope)

    let selected = try await store.pendingScopesForCurrentAccount()

    XCTAssertEqual(selected, [firstScope, secondScope])
    XCTAssertEqual(try store.pendingScopes(), [firstScope, secondScope])
  }

  private func makeMixedAccountScope(
    suffix: String,
    participantAccountRecordName: String,
    acceptedAt: Date
  ) -> HerdSharingAcceptedShareImportScope {
    HerdSharingAcceptedShareImportScope(
      shareIdentifier: "share-\(suffix)",
      rootRecordName: "root-\(suffix)",
      rootZoneName: "zone-\(suffix)",
      rootZoneOwnerName: "owner-\(suffix)",
      acceptedAt: acceptedAt,
      participantAccountRecordName: participantAccountRecordName,
      acceptanceState: .accepted
    )
  }
}

@MainActor
private final class InvitationConsistencyFailureRepository: HerdSharingRepository {
  private let scopeStore: HerdSharingAcceptedShareImportScopeStore
  private let acceptedScope: HerdSharingAcceptedShareImportScope
  private(set) var acceptedInvitationIDs: [UUID] = []

  init(
    scopeStore: HerdSharingAcceptedShareImportScopeStore,
    acceptedScope: HerdSharingAcceptedShareImportScope
  ) {
    self.scopeStore = scopeStore
    self.acceptedScope = acceptedScope
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
    .localOwnerBridgePending
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.sharingStateUnavailable
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    acceptedInvitationIDs.append(invitation.id)
    try scopeStore.record(acceptedScope)
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.sharingStateUnavailable
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.sharingStateUnavailable
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.sharingStateUnavailable
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.sharingStateUnavailable
  }
}


extension HerdSharingAcceptedInvitationScopeTests {
  func testImmediateImportScopeTracksNewestLiveAcceptanceWithoutDiscardingOlderRecovery() throws {
    let suiteName = "HerdSharingAcceptedInvitationScopeTests.Sequencing.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes"
    )
    let olderScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "older-share",
      rootRecordName: "older-root",
      rootZoneName: "older-zone",
      rootZoneOwnerName: "older-owner",
      acceptedAt: Date(timeIntervalSince1970: 1)
    )
    let currentScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "current-share",
      rootRecordName: "current-root",
      rootZoneName: "current-zone",
      rootZoneOwnerName: "current-owner",
      acceptedAt: Date(timeIntervalSince1970: 2)
    )

    try scopeStore.record(olderScope)
    try scopeStore.record(currentScope)

    XCTAssertEqual(scopeStore.immediateImportScope, currentScope)
    XCTAssertEqual(try scopeStore.pendingScopes(), [olderScope, currentScope])

    scopeStore.remove(currentScope)

    XCTAssertNil(scopeStore.immediateImportScope)
    XCTAssertEqual(try scopeStore.pendingScopes(), [olderScope])
  }

  func testImmediateImportScopeIdentityRequiresExactCloudKitRoot() {
    let olderScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "same-share-record-name",
      rootRecordName: "same-root-record-name",
      rootZoneName: "older-zone",
      rootZoneOwnerName: "older-owner"
    )
    let currentScope = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "same-share-record-name",
      rootRecordName: "same-root-record-name",
      rootZoneName: "current-zone",
      rootZoneOwnerName: "current-owner"
    )

    XCTAssertFalse(HerdSharingCoreDataStore.sameAcceptedShareScope(olderScope, currentScope))
    XCTAssertTrue(HerdSharingCoreDataStore.sameAcceptedShareScope(currentScope, currentScope))
  }
}
