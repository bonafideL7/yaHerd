//
//  DeferredHerdSharingStateGuardTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class DeferredHerdSharingStateGuardTests: XCTestCase {
  func testRepositoryRejectsExistingOwnerShareBeforeCallingBaseStart() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .ownerPrivateStore(participantCount: 2, hasActiveSystemShare: true)
    )
    let repository = makeRepository(context: container.mainContext, base: base)

    do {
      _ = try await repository.startSharing(herd: herd.toSummary(), storageMode: .iCloud)
      XCTFail("Expected the repository guard to reject the existing owner share.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareAlreadyExists)
    }
    XCTAssertEqual(base.startSharingCallCount, 0)
  }

  func testRepositoryRejectsAcceptedParticipantBeforeCallingBaseStart() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .acceptedSharedStore(permission: .readWrite, participantCount: 2)
    )
    let repository = makeRepository(context: container.mainContext, base: base)

    do {
      _ = try await repository.startSharing(herd: herd.toSummary(), storageMode: .iCloud)
      XCTFail("Expected the repository guard to reject the participant share.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .acceptedParticipantShareCannotReshare)
    }
    XCTAssertEqual(base.startSharingCallCount, 0)
  }

  func testRepositoryRequiresOwnershipConfirmationBeforeFirstShare() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(access: .localOwnerBridgePending)
    let repository = makeRepository(context: container.mainContext, base: base)

    do {
      _ = try await repository.startSharing(herd: herd.toSummary(), storageMode: .iCloud)
      XCTFail("Expected explicit local ownership confirmation to be required.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownershipConfirmationRequired)
    }
    XCTAssertEqual(base.startSharingCallCount, 0)
  }

  func testRepositoryDelegatesStartAfterExplicitOwnershipConfirmationAndDefersAccountProvenance()
    async throws
  {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(access: .localOwnerBridgePending)
    let accountRegistry = RecordingDeferredGuardAccountOwnershipRegistry()
    let repository = makeRepository(
      context: container.mainContext,
      base: base,
      accountRegistry: accountRegistry
    )

    _ = try await repository.confirmLocalHerdOwnership(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )
    let result = try await repository.startSharing(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(result.title, "Base Start")
    XCTAssertFalse(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
  }

  func testRepositoryBlocksReplacementDeviceStartWhenOwnerShareProvenanceExists() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(access: .localOwnerBridgePending)
    let accountRegistry = RecordingDeferredGuardAccountOwnershipRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let repository = makeRepository(
      context: container.mainContext,
      base: base,
      accountRegistry: accountRegistry
    )

    do {
      _ = try await repository.startSharing(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected prior owner-share provenance to block duplicate share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
    XCTAssertEqual(base.startSharingCallCount, 0)
  }

  func testPendingOwnerImportBlocksShareManagementBeforeBaseStart() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
    let base = RecordingGuardedBaseRepository(
      access: .ownerPrivateStore(participantCount: 2, hasActiveSystemShare: true)
    )
    let repository = makeRepository(
      context: container.mainContext,
      base: base,
      journal: journal
    )

    do {
      _ = try await repository.manageExistingShare(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected pending owner import to block share management.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .sharingOperationPending)
    }
    XCTAssertEqual(base.startSharingCallCount, 0)
    XCTAssertEqual(base.manageExistingShareCallCount, 0)
  }

  func testRepositoryRejectsConflictingBridgeRecordsBeforeCallingBaseStart() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .conflictingStores(ownerHasActiveSystemShare: true, participantCount: 2)
    )
    let repository = makeRepository(context: container.mainContext, base: base)

    do {
      _ = try await repository.startSharing(herd: herd.toSummary(), storageMode: .iCloud)
      XCTFail("Expected conflicting bridge records to reject new share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .unresolvedSharingBridge)
    }
    XCTAssertEqual(base.startSharingCallCount, 0)
  }

  func testBridgeConflictResolutionCallsResolverAndSchedulesImportFirstRecovery() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
    let base = RecordingGuardedBaseRepository(
      access: .conflictingStores(ownerHasActiveSystemShare: true, participantCount: 2)
    )
    let resolver = RecordingBridgeConflictResolver(
      resultAccess: .ownerPrivateStore(participantCount: 2, hasActiveSystemShare: true)
    )
    let repository = makeRepository(
      context: container.mainContext,
      base: base,
      journal: journal,
      conflictResolver: resolver
    )

    let result = try await repository.resolveBridgeConflict(
      herd: herd.toSummary(),
      keeping: .keepOwnerShare,
      storageMode: .iCloud
    )

    XCTAssertEqual(resolver.callCount, 1)
    XCTAssertEqual(resolver.lastResolution, .keepOwnerShare)
    XCTAssertEqual(result.title, "Bridge conflict resolved")
    let unfinished = await journal.unfinishedOperations(for: herd.publicID)
    XCTAssertEqual(unfinished.count, 1)
    XCTAssertEqual(unfinished.first?.direction, .importFromBridge)
    XCTAssertEqual(
      unfinished.first?.bridgeLocation,
      HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
  }

  func testRepositoryOpensExistingOwnerShareWithoutCallingBaseStart() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .ownerPrivateStore(participantCount: 2, hasActiveSystemShare: true)
    )
    let repository = makeRepository(context: container.mainContext, base: base)

    let result = try await repository.manageExistingShare(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(base.manageExistingShareCallCount, 1)
    XCTAssertEqual(base.startSharingCallCount, 0)
    XCTAssertEqual(result.title, "Base Manage")
  }

  func testRepositoryResumesInterruptedShareAfterExplicitOwnershipConfirmation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let registry = RecordingDeferredGuardOwnershipRegistry()
    registry.recordOwner(
      herdPublicID: herd.publicID,
      deviceID: CollaborationIdentityProvider.current().deviceID
    )
    let base = RecordingGuardedBaseRepository(
      access: .ownerPrivateStore(participantCount: nil, hasActiveSystemShare: false)
    )
    let repository = makeRepository(
      context: container.mainContext,
      base: base,
      registry: registry
    )

    let result = try await repository.manageExistingShare(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(base.manageExistingShareCallCount, 0)
    XCTAssertEqual(result.title, "Base Start")
  }

  private func makeRepository(
    context: ModelContext,
    base: RecordingGuardedBaseRepository,
    journal: HerdSharingBridgeJournal? = nil,
    registry: RecordingDeferredGuardOwnershipRegistry = RecordingDeferredGuardOwnershipRegistry(),
    accountRegistry: RecordingDeferredGuardAccountOwnershipRegistry = RecordingDeferredGuardAccountOwnershipRegistry(),
    conflictResolver: (any HerdSharingBridgeConflictResolving)? = nil
  ) -> DeferredCoreDataHerdSharingRepository {
    let resolvedJournal = journal ?? HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL())
    return DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: HerdSharingCreationStateGuard(
        context: context,
        journal: resolvedJournal,
        ownershipRegistry: registry,
        accountOwnershipRegistry: accountRegistry
      ),
      conflictResolver: conflictResolver
    )
  }

  private func insertHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Repository Guard Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try PersistenceLog.save(
      context,
      operation: "DeferredHerdSharingStateGuardTests.insertHerd"
    )
    return herd
  }

  private func makeTemporaryJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}
@MainActor
private final class RecordingGuardedBaseRepository: HerdSharingRepository {
  let access: HerdSharingAccess
  private(set) var startSharingCallCount = 0
  private(set) var manageExistingShareCallCount = 0

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
    startSharingCallCount += 1
    return HerdSharingActionResult(title: "Base Start", message: "Base repository was called.")
  }

  func manageExistingShare(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    manageExistingShareCallCount += 1
    return HerdSharingActionResult(
      title: "Base Manage",
      message: "Existing owner share management was called."
    )
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

@MainActor
private final class RecordingBridgeConflictResolver: HerdSharingBridgeConflictResolving {
  let resultAccess: HerdSharingAccess
  private(set) var callCount = 0
  private(set) var lastResolution: HerdSharingBridgeConflictResolution?

  init(resultAccess: HerdSharingAccess) {
    self.resultAccess = resultAccess
  }

  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution
  ) async throws -> HerdSharingAccess {
    callCount += 1
    lastResolution = resolution
    return resultAccess
  }
}

private final class RecordingDeferredGuardOwnershipRegistry: HerdSharingOwnershipRecording {
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

private final class RecordingDeferredGuardAccountOwnershipRegistry: HerdSharingAccountOwnershipRecording {
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
extension DeferredHerdSharingStateGuardTests {
  func testFailedBridgeSyncInvalidatesWritableAccessUntilReverified() async {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Failed Sync Write Guard Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let writableAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 2,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let sharingRepository = FailedSyncWritePolicySharingRepository(access: writableAccess)
    let writePolicy = HerdCollaborationWritePolicy()
    var refreshRequestCount = 0
    writePolicy.setAccessRefreshRequestHandler { _ in
      refreshRequestCount += 1
    }
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: FailedSyncWritePolicyHerdRepository(herd: herd),
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertFalse(didSync)
    XCTAssertEqual(sharingRepository.accessCallCount, 1)
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertNil(writePolicy.snapshot.access)
    XCTAssertFalse(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertNotNil(coordinator.lastErrorMessage)

    XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .animal)
      )
    }
    XCTAssertEqual(refreshRequestCount, 1)
  }
}

private enum FailedSyncWritePolicyTestError: Error {
  case syncFailedAfterBridgeOperationStarted
}

@MainActor
private final class FailedSyncWritePolicyHerdRepository: HerdRepository {
  private let herd: HerdSummary

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    herd
  }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    HerdSummary(
      publicID: herd.publicID,
      name: name,
      createdAt: herd.createdAt,
      updatedAt: herd.updatedAt,
      schemaVersion: herd.schemaVersion
    )
  }
}

@MainActor
private final class FailedSyncWritePolicySharingRepository: HerdSharingRepository {
  private let access: HerdSharingAccess
  private(set) var accessCallCount = 0
  private(set) var syncCallCount = 0

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
    accessCallCount += 1
    return access
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
    syncCallCount += 1
    throw FailedSyncWritePolicyTestError.syncFailedAfterBridgeOperationStarted
  }
}


@MainActor
extension DeferredHerdSharingStateGuardTests {
  func testPendingAcceptedInvitationBypassesCurrentHerdSyncPreflightAndRetriesUnscopedImport() async throws {
    let suiteName = "DeferredHerdSharingStateGuardTests.PendingInvitation.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes"
    )
    try scopeStore.record(
      HerdSharingAcceptedShareImportScope(
        shareIdentifier: "pending-share",
        rootRecordName: "pending-root",
        rootZoneName: "pending-zone",
        rootZoneOwnerName: "pending-owner"
      )
    )

    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Current Herd Must Not Bind Retry",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try context.save()

    let base = PendingInvitationRetryRecordingRepository()
    let journal = HerdSharingBridgeJournal(
      fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("HerdSharingSyncJournal.json")
    )
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: HerdSharingCreationStateGuard(
        context: context,
        journal: journal,
        ownershipRegistry: PendingInvitationRetryOwnershipRegistry(),
        accountOwnershipRegistry: PendingInvitationRetryAccountOwnershipRegistry()
      ),
      acceptedShareImportScopeStore: scopeStore
    )

    let result = try await repository.syncSharedBridgeData(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Pending Import")
    XCTAssertEqual(base.importCallCount, 1)
    XCTAssertNil(base.lastImportedHerd)
    XCTAssertEqual(base.syncCallCount, 0)
    XCTAssertEqual(base.fetchAccessCallCount, 0)
  }
}

@MainActor
private final class PendingInvitationRetryRecordingRepository: HerdSharingRepository {
  private(set) var fetchAccessCallCount = 0
  private(set) var importCallCount = 0
  private(set) var syncCallCount = 0
  private(set) var lastImportedHerd: HerdSummary?

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
    fetchAccessCallCount += 1
    return .localOwnerBridgePending
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
    importCallCount += 1
    lastImportedHerd = herd
    return HerdSharingActionResult(title: "Pending Import", message: "Pending invitation retry")
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
    syncCallCount += 1
    return HerdSharingActionResult(title: "Unexpected Sync", message: "Unexpected")
  }
}

private final class PendingInvitationRetryOwnershipRegistry: HerdSharingOwnershipRecording {
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

private final class PendingInvitationRetryAccountOwnershipRegistry:
  HerdSharingAccountOwnershipRecording
{
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
extension DeferredHerdSharingStateGuardTests {
  func testUnconfirmedLocalHerdCannotSynchronizeIntoNewBridgeBeforeOwnershipConfirmation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeSynchronizationGuardHerd(in: container.mainContext)
    let base = SynchronizationGuardBaseRepository(access: .localOwnerBridgePending)
    let repository = makeSynchronizationGuardRepository(
      context: container.mainContext,
      base: base
    )

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected ownership confirmation before creating an owner bridge through sync.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownershipConfirmationRequired)
    }

    XCTAssertEqual(base.syncCallCount, 0)
    XCTAssertEqual(base.importCallCount, 0)
  }

  func testPendingImportOnOrphanOwnerBridgeUsesImportOnlyUntilOwnershipConfirmed() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeSynchronizationGuardHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: synchronizationGuardJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
    let base = SynchronizationGuardBaseRepository(
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )
    let repository = makeSynchronizationGuardRepository(
      context: container.mainContext,
      base: base,
      journal: journal
    )

    let result = try await repository.syncSharedBridgeData(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Base Import")
    XCTAssertEqual(base.importCallCount, 1)
    XCTAssertEqual(base.syncCallCount, 0)
  }

  func testPendingImportWithMissingBridgeFailsBeforeAnyExport() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeSynchronizationGuardHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: synchronizationGuardJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
    let base = SynchronizationGuardBaseRepository(access: .localOwnerBridgePending)
    let repository = makeSynchronizationGuardRepository(
      context: container.mainContext,
      base: base,
      journal: journal
    )

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected a missing pending-import source to fail closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridge consistency failure, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("pending shared-data import"))
    }

    XCTAssertEqual(base.importCallCount, 0)
    XCTAssertEqual(base.syncCallCount, 0)
  }

  func testEstablishedOwnerProvenanceWithMissingBridgeFailsBeforeAnyExport() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeSynchronizationGuardHerd(in: container.mainContext)
    let base = SynchronizationGuardBaseRepository(access: .localOwnerBridgePending)
    let accountRegistry = SynchronizationGuardAccountOwnershipRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let repository = makeSynchronizationGuardRepository(
      context: container.mainContext,
      base: base,
      accountRegistry: accountRegistry
    )

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected missing owner bridge with established provenance to block synchronization.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(base.importCallCount, 0)
    XCTAssertEqual(base.syncCallCount, 0)
  }

  func testExportOnlyRecoveryRequiresOwnershipConfirmationThenRunsFullSync() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeSynchronizationGuardHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: synchronizationGuardJournalURL())
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
    let base = SynchronizationGuardBaseRepository(
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )
    let registry = SynchronizationGuardOwnershipRegistry()
    let repository = makeSynchronizationGuardRepository(
      context: container.mainContext,
      base: base,
      journal: journal,
      registry: registry
    )

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected export-only recovery to require local owner confirmation first.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownershipConfirmationRequired)
    }
    XCTAssertEqual(base.syncCallCount, 0)

    _ = try await repository.confirmLocalHerdOwnership(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )
    let result = try await repository.syncSharedBridgeData(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Base Sync")
    XCTAssertEqual(base.syncCallCount, 1)
    XCTAssertEqual(base.importCallCount, 0)
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  func testReadOnlyAcceptedShareSupersedesPendingExportAndSchedulesImportRecovery() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeSynchronizationGuardHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: synchronizationGuardJournalURL())
    let export = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
    try await journal.fail(
      operationID: export.id,
      errorDescription: "Simulated export failure before permission downgrade."
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: SynchronizationGuardOwnershipRegistry(),
      accountOwnershipRegistry: SynchronizationGuardAccountOwnershipRegistry()
    )

    let disposition = try await guardService.synchronizationDisposition(
      herd: herd.toSummary(),
      access: .acceptedSharedStore(permission: .readOnly, participantCount: 2)
    )

    XCTAssertEqual(disposition, .importOnly)
    let unfinished = await journal.unfinishedOperations(for: herd.publicID)
    XCTAssertEqual(unfinished.count, 1)
    XCTAssertEqual(unfinished.first?.direction, .importFromBridge)
    XCTAssertEqual(
      unfinished.first?.bridgeLocation,
      HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
    XCTAssertFalse(unfinished.contains { $0.direction == .exportToBridge })
  }

  func testUnknownAcceptedPermissionDoesNotAbandonPendingExport() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try makeSynchronizationGuardHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: synchronizationGuardJournalURL())
    let export = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .exportToBridge,
      bridgeLocation: HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
    try await journal.fail(
      operationID: export.id,
      errorDescription: "Simulated export failure while permission is unresolved."
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: SynchronizationGuardOwnershipRegistry(),
      accountOwnershipRegistry: SynchronizationGuardAccountOwnershipRegistry()
    )

    do {
      _ = try await guardService.synchronizationDisposition(
        herd: herd.toSummary(),
        access: .acceptedSharedStore(permission: .unknown, participantCount: 2)
      )
      XCTFail("Expected unresolved permission to keep pending export recovery fail-closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .sharingOperationPending)
    }

    let unfinished = await journal.unfinishedOperations(for: herd.publicID)
    XCTAssertEqual(unfinished.count, 1)
    XCTAssertEqual(unfinished.first?.direction, .exportToBridge)
  }

  private func makeSynchronizationGuardRepository(
    context: ModelContext,
    base: SynchronizationGuardBaseRepository,
    journal: HerdSharingBridgeJournal? = nil,
    registry: SynchronizationGuardOwnershipRegistry = SynchronizationGuardOwnershipRegistry(),
    accountRegistry: SynchronizationGuardAccountOwnershipRegistry = SynchronizationGuardAccountOwnershipRegistry()
  ) -> DeferredCoreDataHerdSharingRepository {
    let resolvedJournal = journal ?? HerdSharingBridgeJournal(
      fileURL: synchronizationGuardJournalURL()
    )
    return DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: HerdSharingCreationStateGuard(
        context: context,
        journal: resolvedJournal,
        ownershipRegistry: registry,
        accountOwnershipRegistry: accountRegistry
      )
    )
  }

  private func makeSynchronizationGuardHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Synchronization Guard Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try PersistenceLog.save(
      context,
      operation: "DeferredHerdSharingStateGuardTests.makeSynchronizationGuardHerd"
    )
    return herd
  }

  private func synchronizationGuardJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}

@MainActor
private final class SynchronizationGuardBaseRepository: HerdSharingRepository {
  let access: HerdSharingAccess
  private(set) var syncCallCount = 0
  private(set) var importCallCount = 0

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
    importCallCount += 1
    return HerdSharingActionResult(title: "Base Import", message: "Imported only")
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
    syncCallCount += 1
    return HerdSharingActionResult(title: "Base Sync", message: "Full sync")
  }
}

private final class SynchronizationGuardOwnershipRegistry: HerdSharingOwnershipRecording {
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

private final class SynchronizationGuardAccountOwnershipRegistry: HerdSharingAccountOwnershipRecording {
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

// MARK: - Coordinator recovery access refresh

@MainActor
extension DeferredHerdSharingStateGuardTests {
  func testSuccessfulRecoverySyncRefreshesWritePolicyAfterPendingStateClears() async {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Recovery Refresh Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let pendingAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 2,
      hasActiveSystemShare: true
    ).applyingCreationState(.pendingBridgeOperation)
    let recoveredAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 2,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let sharingRepository = RecoveryRefreshSharingRepository(
      initialAccess: pendingAccess,
      refreshedAccess: recoveredAccess
    )
    let writePolicy = HerdCollaborationWritePolicy()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: RecoveryRefreshHerdRepository(herd: herd),
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertTrue(didSync)
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(sharingRepository.accessCallCount, 2)
    XCTAssertEqual(writePolicy.snapshot.access?.creationState, .existingOwnerShare)
    XCTAssertTrue(writePolicy.snapshot.allowsLocalMutations)
  }

  func testPostSyncAccessRefreshFailureClearsStaleWritePolicyAccess() async {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Recovery Refresh Failure Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let pendingAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 2,
      hasActiveSystemShare: true
    ).applyingCreationState(.pendingBridgeOperation)
    let sharingRepository = RecoveryRefreshSharingRepository(
      initialAccess: pendingAccess,
      refreshedAccess: .localOwnerBridgePending,
      failRefreshedAccess: true
    )
    let writePolicy = HerdCollaborationWritePolicy()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: RecoveryRefreshHerdRepository(herd: herd),
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertFalse(didSync)
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(sharingRepository.accessCallCount, 2)
    XCTAssertNil(writePolicy.snapshot.access)
    XCTAssertNotNil(coordinator.lastErrorMessage)
  }
}

private enum RecoveryRefreshTestError: Error {
  case accessRefreshFailed
}

@MainActor
private final class RecoveryRefreshHerdRepository: HerdRepository {
  private let herd: HerdSummary

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    herd
  }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    HerdSummary(
      publicID: herd.publicID,
      name: name,
      createdAt: herd.createdAt,
      updatedAt: herd.updatedAt,
      schemaVersion: herd.schemaVersion
    )
  }
}

@MainActor
private final class RecoveryRefreshSharingRepository: HerdSharingRepository {
  private let initialAccess: HerdSharingAccess
  private let refreshedAccess: HerdSharingAccess
  private let failRefreshedAccess: Bool
  private(set) var accessCallCount = 0
  private(set) var syncCallCount = 0

  init(
    initialAccess: HerdSharingAccess,
    refreshedAccess: HerdSharingAccess,
    failRefreshedAccess: Bool = false
  ) {
    self.initialAccess = initialAccess
    self.refreshedAccess = refreshedAccess
    self.failRefreshedAccess = failRefreshedAccess
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
    accessCallCount += 1
    if accessCallCount == 1 {
      return initialAccess
    }
    if failRefreshedAccess {
      throw RecoveryRefreshTestError.accessRefreshFailed
    }
    return refreshedAccess
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
    syncCallCount += 1
    return HerdSharingActionResult(title: "Recovered", message: "Recovery sync completed.")
  }
}

// MARK: - Crash-safe bridge conflict recovery

@MainActor
extension DeferredHerdSharingStateGuardTests {
  func testBridgeConflictRecoveryMarkerIsDurableBeforeDestructiveResolverRuns() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Crash Safe Conflict Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try context.save()

    let journal = HerdSharingBridgeJournal(
      fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("HerdSharingSyncJournal.json")
    )
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: CrashSafetySharingRepository(),
      creationGuard: HerdSharingCreationStateGuard(
        context: context,
        journal: journal,
        ownershipRegistry: CrashSafetyOwnershipRegistry()
      ),
      conflictResolver: ThrowingBridgeConflictResolver()
    )

    do {
      _ = try await repository.resolveBridgeConflict(
        herd: herd.toSummary(),
        keeping: .keepOwnerShare,
        storageMode: .iCloud
      )
      XCTFail("Expected the simulated destructive bridge resolver to fail.")
    } catch let error as CrashSafetyResolverError {
      XCTAssertEqual(error, .simulatedFailure)
    }

    let unfinished = await journal.unfinishedOperations(for: herd.publicID)
    XCTAssertEqual(unfinished.count, 1)
    XCTAssertEqual(unfinished.first?.direction, .importFromBridge)
    XCTAssertEqual(
      unfinished.first?.bridgeLocation,
      HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
    )
    XCTAssertEqual(unfinished.first?.state, .failed)
  }
}

private enum CrashSafetyResolverError: Error, Equatable {
  case simulatedFailure
}

@MainActor
private final class ThrowingBridgeConflictResolver: HerdSharingBridgeConflictResolving {
  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution
  ) async throws -> HerdSharingAccess {
    throw CrashSafetyResolverError.simulatedFailure
  }
}

@MainActor
private final class CrashSafetySharingRepository: HerdSharingRepository {
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
    .conflictingStores(
      ownerHasActiveSystemShare: true,
      participantCount: 2
    )
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

private final class CrashSafetyOwnershipRegistry: HerdSharingOwnershipRecording {
  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? { nil }
  func recordOwner(herdPublicID: UUID, deviceID: String) {}
  func recordParticipant(herdPublicID: UUID) {}
}

// MARK: - Bridge conflict resolver integration
