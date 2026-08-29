//
//  HerdSharingCreationStateGuardTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingCreationStateGuardTests: XCTestCase {
  func testUniqueFreshLocalHerdRequiresOwnershipConfirmationBeforeFirstShare() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ownershipConfirmationRequired)
    XCTAssertFalse(access.creationState.allowsNewShare)
  }

  func testConfirmLocalOwnershipMakesFreshLocalHerdReady() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.confirmLocalOwnership(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ready)
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  func testLocallyCreatedHerdRemainsFirstShareEligibleAfterNormalLocalEdits() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = try insertFreshLocalHerd(in: context)
    let repository = SwiftDataHerdRepository(context: context)
    let renamed = try repository.renameCurrentHerd(to: "Edited Before Sharing")
    let revision = try XCTUnwrap(try herdRevision(for: herd, in: context))
    XCTAssertGreaterThan(revision.revision, 1)
    XCTAssertEqual(revision.baseRevision, 0)
    XCTAssertEqual(
      revision.modifiedByDeviceID,
      CollaborationIdentityProvider.current().deviceID
    )

    let registry = RecordingHerdSharingOwnershipRegistry()
    let guardService = makeGuard(context: context, registry: registry)
    let access = try await guardService.evaluate(
      herd: renamed,
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ownershipConfirmationRequired)
    let confirmed = try await guardService.confirmLocalOwnership(
      herd: renamed,
      access: .localOwnerBridgePending
    )
    XCTAssertEqual(confirmed.creationState, .ready)
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  func testSharedLineageDoesNotBecomeFirstShareEligibleAfterCurrentDeviceEdit() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = try insertFreshLocalHerd(in: context)
    let revision = try XCTUnwrap(try herdRevision(for: herd, in: context))
    revision.revision = 2
    revision.baseRevision = 1
    revision.modifiedByDeviceID = CollaborationIdentityProvider.current().deviceID
    try context.save()
    let guardService = makeGuard(context: context)

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ownerBridgeVerificationRequired)
  }

  func testActiveOwnerShareRoutesToManagementWithoutCommittingUnverifiedAccountProvenance()
    async throws
  {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    let accountRegistry = RecordingHerdSharingAccountOwnershipRegistry()
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry,
      accountRegistry: accountRegistry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      )
    )

    XCTAssertEqual(access.creationState, .existingOwnerShare)
    XCTAssertFalse(access.creationState.allowsNewShare)
    XCTAssertFalse(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
    XCTAssertNil(registry.ownership(for: herd.publicID))
  }

  func testActiveOwnerShareWithPendingImportRoutesToRecoveryBeforeManagement() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: RecordingHerdSharingOwnershipRegistry(),
      accountOwnershipRegistry: RecordingHerdSharingAccountOwnershipRegistry()
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      )
    )

    XCTAssertEqual(access.creationState, .pendingBridgeOperation)
  }

  func testAcceptedParticipantShareRoutesToSynchronization() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .acceptedSharedStore(
        permission: .readWrite,
        participantCount: 2
      )
    )

    XCTAssertEqual(access.creationState, .acceptedParticipantShare)
    XCTAssertEqual(registry.ownership(for: herd.publicID), .participant)
  }

  func testOwnerBridgeWithoutSystemShareIsUnresolvedAfterOwnershipConfirmation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    registry.recordOwner(
      herdPublicID: herd.publicID,
      deviceID: CollaborationIdentityProvider.current().deviceID
    )
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )

    XCTAssertEqual(access.creationState, .unresolvedBridgeRecord)
  }

  func testUnfinishedBridgeOperationBlocksNewShare() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: "accepted shared store"
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: RecordingHerdSharingOwnershipRegistry(),
      accountOwnershipRegistry: RecordingHerdSharingAccountOwnershipRegistry()
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .pendingBridgeOperation)
  }

  func testUnfinishedBridgeOperationBlocksInterruptedShareResume() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: "owner private store"
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: RecordingHerdSharingOwnershipRegistry(),
      accountOwnershipRegistry: RecordingHerdSharingAccountOwnershipRegistry()
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )

    XCTAssertEqual(access.creationState, .pendingBridgeOperation)
  }

  func testParticipantOwnershipMarkerBlocksShareWhenBridgeHasNotLoadedYet() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    registry.recordParticipant(herdPublicID: herd.publicID)
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .notOwnedByCurrentDevice)
  }

  func testRestoredFreshLocalLineageRequiresExplicitOwnershipConfirmation() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = try insertFreshLocalHerd(in: context)
    let revision = try XCTUnwrap(try herdRevision(for: herd, in: context))
    revision.modifiedByDeviceID = "device-from-previous-installation"
    try context.save()
    let registry = RecordingHerdSharingOwnershipRegistry()
    let guardService = makeGuard(context: context, registry: registry)

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ownershipConfirmationRequired)
    let confirmed = try await guardService.confirmLocalOwnership(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )
    XCTAssertEqual(confirmed.creationState, .ready)
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  func testPreviousOwnerDeviceMarkerCannotBeConfirmedWhileBridgeIsMissing() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    registry.recordOwner(herdPublicID: herd.publicID, deviceID: "previous-installation")
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let before = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )
    XCTAssertEqual(before.creationState, .ownerBridgeVerificationRequired)

    do {
      _ = try await guardService.confirmLocalOwnership(
        herd: herd.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected missing-bridge ownership confirmation to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
  }

  func testAccountOwnerShareProvenanceBlocksReplacementDeviceShareCreation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let accountRegistry = RecordingHerdSharingAccountOwnershipRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let guardService = makeGuard(
      context: container.mainContext,
      accountRegistry: accountRegistry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )
    XCTAssertEqual(access.creationState, .ownerBridgeVerificationRequired)

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected established owner-share provenance to block a replacement share.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    do {
      _ = try await guardService.confirmLocalOwnership(
        herd: herd.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected confirmation to remain blocked until owner bridge state is resolved.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
  }

  func testExplicitStaleOwnerResetClearsAccountProvenanceAndAuthorizesCurrentDevice() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    registry.recordOwner(herdPublicID: herd.publicID, deviceID: "previous-installation")
    let accountRegistry = RecordingHerdSharingAccountOwnershipRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry,
      accountRegistry: accountRegistry
    )

    let access = try await guardService.resetStaleOwnerSharingState(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ready)
    XCTAssertFalse(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  func testStaleOwnerResetAbandonsInterruptedOwnerImportAfterBridgeLoss() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
    let registry = RecordingHerdSharingOwnershipRegistry()
    let accountRegistry = RecordingHerdSharingAccountOwnershipRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: registry,
      accountOwnershipRegistry: accountRegistry
    )

    let access = try await guardService.resetStaleOwnerSharingState(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ready)
    XCTAssertFalse(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
    let unfinished = await journal.unfinishedOperations(for: herd.publicID)
    XCTAssertTrue(unfinished.isEmpty)
  }

  func testStaleParticipantDetachClearsMarkerOnlyWhenAcceptedBridgeIsAbsent() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    registry.recordParticipant(herdPublicID: herd.publicID)
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.detachStaleParticipantState(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertNil(registry.ownership(for: herd.publicID))
    XCTAssertEqual(access.creationState, .ownershipConfirmationRequired)

    registry.recordParticipant(herdPublicID: herd.publicID)
    do {
      _ = try await guardService.detachStaleParticipantState(
        herd: herd.toSummary(),
        access: .acceptedSharedStore(permission: .readWrite, participantCount: 2)
      )
      XCTFail("Expected an existing accepted bridge to block participant detach.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Expected bridge consistency failure, got \(error)")
        return
      }
    }
    XCTAssertEqual(registry.ownership(for: herd.publicID), .participant)
  }

  func testRecordOwnerShareEstablishedRecordsLocalAndAccountAuthority() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    let accountRegistry = RecordingHerdSharingAccountOwnershipRegistry()
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry,
      accountRegistry: accountRegistry
    )

    guardService.recordOwnerShareEstablished(herdPublicID: herd.publicID)

    XCTAssertTrue(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  func testValidationRejectsExistingOwnerShareBeforeCloudKitCreation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .ownerPrivateStore(
          participantCount: 2,
          hasActiveSystemShare: true
        )
      )
      XCTFail("Expected an existing owner share to be rejected.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareAlreadyExists)
    }
  }

  func testValidationRejectsAcceptedParticipantShareBeforeCloudKitCreation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .acceptedSharedStore(
          permission: .readOnly,
          participantCount: 2
        )
      )
      XCTFail("Expected an accepted participant share to be rejected.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .acceptedParticipantShareCannotReshare)
    }
  }

  func testValidationRequiresExplicitOwnershipConfirmationForFreshLocalHerd() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertFreshLocalHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected explicit local ownership confirmation to be required.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownershipConfirmationRequired)
    }
  }

  private func insertFreshLocalHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Guard Test Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try PersistenceLog.save(
      context,
      operation: "HerdSharingCreationStateGuardTests.insertFreshLocalHerd"
    )
    return herd
  }

  private func herdRevision(
    for herd: Herd,
    in context: ModelContext
  ) throws -> CollaborationRevisionRecord? {
    let key = herd.collaborationKey.storageKey
    return try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
      .first { $0.aggregateKey == key }
  }

  private func makeGuard(
    context: ModelContext,
    registry: RecordingHerdSharingOwnershipRegistry = RecordingHerdSharingOwnershipRegistry(),
    accountRegistry: RecordingHerdSharingAccountOwnershipRegistry = RecordingHerdSharingAccountOwnershipRegistry()
  ) -> HerdSharingCreationStateGuard {
    HerdSharingCreationStateGuard(
      context: context,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: registry,
      accountOwnershipRegistry: accountRegistry
    )
  }

  private func makeTemporaryJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}
private final class RecordingHerdSharingOwnershipRegistry: HerdSharingOwnershipRecording {
  private var ownershipByHerdID: [UUID: HerdSharingOwnership] = [:]

  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    ownershipByHerdID[herdPublicID]
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {
    ownershipByHerdID[herdPublicID] = .owner(deviceID: deviceID)
  }

  func recordParticipant(herdPublicID: UUID) {
    ownershipByHerdID[herdPublicID] = .participant
  }

  func clearOwnership(for herdPublicID: UUID) {
    ownershipByHerdID.removeValue(forKey: herdPublicID)
  }
}

private final class RecordingHerdSharingAccountOwnershipRegistry: HerdSharingAccountOwnershipRecording {
  private var establishedHerdIDs: Set<UUID> = []

  func hasEstablishedOwnerShare(for herdPublicID: UUID) -> Bool {
    establishedHerdIDs.contains(herdPublicID)
  }

  func recordEstablishedOwnerShare(for herdPublicID: UUID) {
    establishedHerdIDs.insert(herdPublicID)
  }

  func clearEstablishedOwnerShare(for herdPublicID: UUID) {
    establishedHerdIDs.remove(herdPublicID)
  }
}
@MainActor
extension HerdSharingCreationStateGuardTests {
  func testSupersededJournalOperationsUseRollbackCompatibleCompletedState() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HerdSharingBridgeJournalCompatibilityTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("HerdSharingSyncJournal.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let herdID = UUID()
    let journal = HerdSharingBridgeJournal(fileURL: fileURL)
    _ = try await journal.begin(
      herdPublicID: herdID,
      direction: .importFromBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )

    try await journal.abandonUnfinishedOperations(
      for: herdID,
      reason: "Superseded by explicit recovery."
    )

    let unfinishedOperations = await journal.unfinishedOperations(for: herdID)
    XCTAssertTrue(unfinishedOperations.isEmpty)
    let serialized = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertTrue(serialized.contains("\"state\" : \"completed\""))
    XCTAssertFalse(serialized.contains("abandoned"))
  }
}

// MARK: - Guard integrity regressions

@MainActor
extension HerdSharingCreationStateGuardTests {
  func testMissingBridgeDoesNotReplayAcceptedStoreExportAsOwnerExport() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeIntegrityGuardHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: integrityGuardJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
    let registry = IntegrityGuardOwnershipRegistry()
    registry.recordOwner(
      herdPublicID: herd.publicID,
      deviceID: CollaborationIdentityProvider.current().deviceID
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: registry
    )

    do {
      _ = try await guardService.synchronizationDisposition(
        herd: herd.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected stale accepted-store export recovery to fail closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridge consistency failure, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("Pending export recovery"))
    }
  }

  func testDeletedHerdRevisionBlocksOwnershipRecovery() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = try makeIntegrityGuardHerd(in: context)
    let revision = CollaborationRevisionRecord(
      key: herd.collaborationKey,
      herdPublicID: herd.publicID,
      metadata: CollaborationRevisionMetadata(
        modifiedAt: herd.updatedAt,
        revision: 2,
        modifiedByParticipantID: "participant-history",
        modifiedByDeviceID: "device-history",
        baseRevision: 1,
        baseFieldValues: [:],
        currentFieldValues: [:],
        isDeleted: true
      )
    )
    context.insert(revision)
    try context.save()

    let persistedRevisionRecords = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
    XCTAssertEqual(persistedRevisionRecords.count, 1)
    let persistedRevision = try XCTUnwrap(persistedRevisionRecords.first)
    XCTAssertEqual(persistedRevision.sourceEntityName, herd.collaborationKey.sourceEntityName)
    XCTAssertEqual(persistedRevision.aggregatePublicID, herd.publicID)
    XCTAssertEqual(persistedRevision.herdPublicID, herd.publicID)
    XCTAssertTrue(
      persistedRevision.deletionTombstone,
      "The test must exercise one persisted deleted revision row."
    )
    XCTAssertTrue(persistedRevision.metadata.isDeleted)

    let guardService = HerdSharingCreationStateGuard(
      context: context,
      journal: HerdSharingBridgeJournal(fileURL: integrityGuardJournalURL()),
      ownershipRegistry: IntegrityGuardOwnershipRegistry()
    )

    do {
      _ = try await guardService.evaluate(
        herd: herd.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected deleted collaboration revision metadata to block ownership recovery.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridge consistency failure, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("marks it deleted"))
    }
  }

  func testV1FixturePersistsCollaborationRevisionDeletionTombstone() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HerdSharingRevisionFixtureTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storeURL = directory.appendingPathComponent("yaHerdStore.store")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try YaHerdSchemaV1FixtureStore.create(at: storeURL)
    let container = try ModelContainerFactory.makeContainer(
      syncMode: .localOnly,
      storeURL: storeURL
    )
    try YaHerdSchemaV1FixtureStore.validate(in: container.mainContext)

    let revisions = try container.mainContext.fetch(FetchDescriptor<CollaborationRevisionRecord>())
    let persisted = try XCTUnwrap(
      revisions.first { $0.publicID == YaHerdSchemaV1FixtureStore.revisionRecordID }
    )
    XCTAssertTrue(persisted.deletionTombstone)
    XCTAssertTrue(persisted.metadata.isDeleted)
  }

  private func makeIntegrityGuardHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Integrity Guard Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try context.save()
    return herd
  }

  private func integrityGuardJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}

private final class IntegrityGuardOwnershipRegistry: HerdSharingOwnershipRecording {
  private var ownershipByHerdID: [UUID: HerdSharingOwnership] = [:]

  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    ownershipByHerdID[herdPublicID]
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {
    ownershipByHerdID[herdPublicID] = .owner(deviceID: deviceID)
  }

  func recordParticipant(herdPublicID: UUID) {
    ownershipByHerdID[herdPublicID] = .participant
  }
}

// MARK: - Write-policy recovery state regressions
