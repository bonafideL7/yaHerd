//
//  HerdSharingConflictingStoreTests.swift
//  yaHerdTests
//

import CloudKit
import CoreData
import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingConflictingStoreTests: XCTestCase {
  func testConflictingStoresBlockShareCreationAndLocalMutations() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let access = HerdSharingAccess.conflictingStores(
      ownerHasActiveSystemShare: true,
      participantCount: 2
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: ConflictingStoreOwnershipRegistry()
    )

    let evaluatedAccess = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: access
    )

    XCTAssertEqual(evaluatedAccess.creationState, .conflictingBridgeRecords)
    XCTAssertFalse(evaluatedAccess.creationState.allowsNewShare)
    XCTAssertFalse(evaluatedAccess.allowsLocalMutations)
    XCTAssertTrue(evaluatedAccess.hasConflictingBridgeRecords)
    XCTAssertEqual(evaluatedAccess.locationDescription, "owner and accepted shared stores")
  }

  func testConflictingStoresAreRejectedBeforeNewShareCreation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: ConflictingStoreOwnershipRegistry()
    )

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .conflictingStores(
          ownerHasActiveSystemShare: false,
          participantCount: 2
        )
      )
      XCTFail("Expected conflicting bridge records to block share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .unresolvedSharingBridge)
    }
  }

  func testWritePolicyReportsConflictingStoresAsBlocked() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: .conflictingStores(
        ownerHasActiveSystemShare: true,
        participantCount: 2
      ).applyingCreationState(.conflictingBridgeRecords)
    )

    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .bridgeConflictRequiresResolution(reason: .animal)
      )
    }
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertTrue(policy.snapshot.statusDescription.contains("both owner and accepted shared"))
  }

  func testPendingBridgeRecoveryBlocksLocalWritesUntilImportCompletes() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      ).applyingCreationState(.pendingBridgeOperation)
    )

    XCTAssertThrowsError(try policy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingRecoveryPending(reason: .pasture)
      )
    }
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertTrue(policy.snapshot.statusDescription.contains("pending shared-data"))
  }

  func testCollaborationViewModelExposesConflictResolutionAsActionable() async throws {
    let herd = makeSummary()
    let viewModel = HerdCollaborationViewModel()
    let sharingRepository = PresentationSharingRepository(
      access: HerdSharingAccess.conflictingStores(
        ownerHasActiveSystemShare: true,
        participantCount: 2
      ).applyingCreationState(.conflictingBridgeRecords)
    )
    viewModel.load(
      herdRepository: PresentationHerdRepository(herd: herd),
      sharingRepository: sharingRepository,
      storageMode: .iCloud
    )
    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .iCloud
    )

    XCTAssertTrue(viewModel.canPerformPrimarySharingAction)
    XCTAssertEqual(viewModel.primarySharingActionTitle, "Resolve Bridge Conflict")
    XCTAssertEqual(viewModel.primarySharingActionSystemImage, "exclamationmark.triangle")
  }

  func testCollaborationViewModelExposesOwnershipConfirmationAsActionable() async throws {
    let herd = makeSummary()
    let viewModel = HerdCollaborationViewModel()
    let sharingRepository = PresentationSharingRepository(
      access: HerdSharingAccess.localOwnerBridgePending
        .applyingCreationState(.ownershipConfirmationRequired)
    )
    viewModel.load(
      herdRepository: PresentationHerdRepository(herd: herd),
      sharingRepository: sharingRepository,
      storageMode: .iCloud
    )
    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .iCloud
    )

    XCTAssertTrue(viewModel.canPerformPrimarySharingAction)
    XCTAssertEqual(viewModel.primarySharingActionTitle, "Confirm Local Ownership")
    XCTAssertEqual(viewModel.primarySharingActionSystemImage, "checkmark.shield")
  }

  func testCollaborationViewModelInvalidatesWritablePolicyWhenAccessRevalidationFails()
    async throws
  {
    let herd = makeSummary()
    let viewModel = HerdCollaborationViewModel()
    let sharingRepository = PresentationSharingRepository(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: true
      ).applyingCreationState(.existingOwnerShare)
    )
    let writePolicy = HerdCollaborationWritePolicy()
    viewModel.load(
      herdRepository: PresentationHerdRepository(herd: herd),
      sharingRepository: sharingRepository,
      storageMode: .iCloud
    )
    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy
    )
    XCTAssertTrue(writePolicy.snapshot.allowsLocalMutations)

    sharingRepository.setError(HerdSharingActionError.ownerBridgeVerificationRequired)
    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy
    )

    XCTAssertNil(viewModel.sharingAccess)
    XCTAssertNotNil(viewModel.sharingAccessMessage)
    XCTAssertTrue(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .herd)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .herd)
      )
    }
  }

  func testCollaborationViewModelPreservesNewerSameHerdAccessWhenRefreshBecomesStale()
    async throws
  {
    let herd = makeSummary()
    let viewModel = HerdCollaborationViewModel()
    let sharingRepository = PresentationSharingRepository(
      access: HerdSharingAccess.localOwnerBridgePending
        .applyingCreationState(.ready)
    )
    sharingRepository.suspendAccessLookup()
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: HerdSharingAccess.localOwnerBridgePending.applyingCreationState(.ready)
    )
    viewModel.load(
      herdRepository: PresentationHerdRepository(herd: herd),
      sharingRepository: sharingRepository,
      storageMode: .iCloud
    )

    let refreshTask = Task { @MainActor in
      await viewModel.refreshSharingAccess(
        using: sharingRepository,
        storageMode: .iCloud,
        writePolicy: writePolicy
      )
    }
    while !sharingRepository.accessLookupStarted {
      await Task.yield()
    }

    // Models a concurrent coordinator refresh publishing owner-stop recovery state.
    let ownerStopAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.ownerStopCleanupPending)
    writePolicy.update(access: ownerStopAccess)
    sharingRepository.resumeAccessLookup()
    await refreshTask.value

    XCTAssertEqual(viewModel.sharingAccess, ownerStopAccess)
    XCTAssertTrue(viewModel.sharingAccessMessage?.contains("sharing state changed") == true)
    XCTAssertEqual(viewModel.primarySharingActionTitle, "Retry Stop Sharing Cleanup")
    XCTAssertTrue(viewModel.canPerformPrimarySharingAction)
    XCTAssertEqual(writePolicy.snapshot.access, ownerStopAccess)
    XCTAssertFalse(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
  }

  private func insertHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Conflicting Store Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try context.save()
    return herd
  }

  private func makeSummary() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Presentation Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }

  private func makeTemporaryJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}

private final class ConflictingStoreOwnershipRegistry: HerdSharingOwnershipRecording {
  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    nil
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {}

  func recordParticipant(herdPublicID: UUID) {}
}

@MainActor
private final class PresentationHerdRepository: HerdRepository {
  private var herd: HerdSummary

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    herd
  }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    herd = HerdSummary(
      publicID: herd.publicID,
      name: name,
      createdAt: herd.createdAt,
      updatedAt: herd.updatedAt,
      schemaVersion: herd.schemaVersion
    )
    return herd
  }
}

@MainActor
private final class PresentationSharingRepository: HerdSharingRepository {
  private let access: HerdSharingAccess
  private var error: Error?
  private var shouldSuspendAccessLookup = false
  private(set) var accessLookupStarted = false

  init(access: HerdSharingAccess) {
    self.access = access
  }

  func setError(_ error: Error) {
    self.error = error
  }

  func suspendAccessLookup() {
    shouldSuspendAccessLookup = true
  }

  func resumeAccessLookup() {
    shouldSuspendAccessLookup = false
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
    accessLookupStarted = true
    while shouldSuspendAccessLookup {
      await Task.yield()
    }
    if let error { throw error }
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
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }
}


@MainActor
extension HerdSharingConflictingStoreTests {
  func testManagementPreflightPublishesAndPersistsRemoteOwnerStopBlock() async throws {
    let herd = OwnerStopTestFixture.herd()
    let staleWritableAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let stoppedAccess = staleWritableAccess.applyingCreationState(.ownerStopCleanupPending)
    let base = OwnerStopSharingRepository(
      access: stoppedAccess,
      manageResult: HerdSharingActionResult(title: "Unused", message: "Unused")
    )
    let store = OwnerStopCleanupTestStore()
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: staleWritableAccess)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: OwnerStopHerdRepository(herd: herd),
      ownerStopCleanupStore: store
    )

    do {
      _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
      XCTFail("Remote owner-stop detection must block share management.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        return XCTFail("Unexpected sharing error: \(error)")
      }
    }

    XCTAssertTrue(store.isCleanupPending(for: herd.publicID))
    XCTAssertEqual(policy.snapshot.access?.creationState, .ownerStopCleanupPending)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertEqual(base.manageCallCount, 0)
  }

  func testRemoteAbsenceAccessRefreshPersistsOwnerStopCleanupBlock() async throws {
    let herd = OwnerStopTestFixture.herd()
    let access = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.ownerStopCleanupPending)
    let base = OwnerStopSharingRepository(
      access: access,
      manageResult: HerdSharingActionResult(title: "Unused", message: "Unused")
    )
    let store = OwnerStopCleanupTestStore()
    let policy = HerdCollaborationWritePolicy()
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: OwnerStopHerdRepository(herd: herd),
      ownerStopCleanupStore: store
    )

    let viewModel = HerdCollaborationViewModel()
    viewModel.load(
      herdRepository: OwnerStopHerdRepository(herd: herd),
      sharingRepository: repository,
      storageMode: .iCloud
    )
    let generationBeforeRefresh = policy.sharingStateGeneration

    await viewModel.refreshSharingAccess(
      using: repository,
      storageMode: .iCloud,
      writePolicy: policy
    )

    XCTAssertEqual(viewModel.sharingAccess?.creationState, .ownerStopCleanupPending)
    XCTAssertTrue(store.isCleanupPending(for: herd.publicID))
    XCTAssertEqual(policy.snapshot.access?.creationState, .ownerStopCleanupPending)
    XCTAssertFalse(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertEqual(policy.sharingStateGeneration, generationBeforeRefresh &+ 1)
  }

  func testOwnerStopPreparationPersistsBlockBeforeAsynchronousCleanupBegins() async throws {
    let herd = OwnerStopTestFixture.herd()
    let presentation = OwnerStopTestFixture.presentation(for: herd)
    let base = OwnerStopSharingRepository(
      access: HerdSharingAccess.ownerPrivateStore(participantCount: 1)
        .applyingCreationState(.existingOwnerShare),
      manageResult: HerdSharingActionResult(
        title: "Manage",
        message: "Manage owner share",
        sharePresentation: presentation
      )
    )
    let store = OwnerStopCleanupTestStore()
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: base.access)
    var didBeginCleanup = false
    let systemShare = OwnerStopTestSystemShare.make { _ in
      didBeginCleanup = true
    }
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: OwnerStopHerdRepository(herd: herd),
      ownerStopCleanupStore: store,
      ownerShareSystemShareResolver: { _ in systemShare }
    )

    _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
    try systemShare.prepareToStopSharing()

    XCTAssertTrue(store.isCleanupPending(for: herd.publicID))
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertFalse(didBeginCleanup)
  }

  func testOwnerStopDoesNotPurgeWhenDurableCleanupBlockCannotBeRecorded() async throws {
    let herd = OwnerStopTestFixture.herd()
    let presentation = OwnerStopTestFixture.presentation(for: herd)
    let base = OwnerStopSharingRepository(
      access: HerdSharingAccess.ownerPrivateStore(participantCount: 1)
        .applyingCreationState(.existingOwnerShare),
      manageResult: HerdSharingActionResult(
        title: "Manage",
        message: "Manage owner share",
        sharePresentation: presentation
      )
    )
    let store = OwnerStopCleanupTestStore(recordError: .durableMarkerFailed)
    var didAttemptPurge = false
    let systemShare = OwnerStopTestSystemShare.make { _ in
      didAttemptPurge = true
    }
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: HerdCollaborationWritePolicy(),
      herdRepository: OwnerStopHerdRepository(herd: herd),
      ownerStopCleanupStore: store,
      ownerShareSystemShareResolver: { _ in systemShare }
    )

    _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
    do {
      try await systemShare.stopSharing()
      XCTFail("Expected durable cleanup-marker failure.")
    } catch {
      XCTAssertEqual(error as? OwnerStopTestError, .durableMarkerFailed)
    }

    XCTAssertFalse(didAttemptPurge)
  }

  func testFailedDirectImportRefreshesAccessUsingReplacementCurrentHerd() async {
    let originalHerd = failedImportHerd(name: "Original Herd", offset: 1)
    let replacementHerd = failedImportHerd(name: "Accepted Replacement Herd", offset: 10)
    let herdRepository = FailedImportCurrentHerdRepository(currentHerd: originalHerd)
    let base = FailedImportCurrentHerdSharingRepository(
      herdRepository: herdRepository,
      replacementHerd: replacementHerd,
      replacementAccess: HerdSharingAccess.acceptedSharedStore(
        permission: .readOnly,
        participantCount: 2
      ).applyingCreationState(.acceptedParticipantShare)
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: herdRepository
    )

    do {
      _ = try await repository.importSharedBridgeData(
        herd: originalHerd,
        storageMode: .iCloud
      )
      XCTFail("Expected the direct bridge import to fail after replacing the current Herd.")
    } catch let error as FailedImportCurrentHerdTestError {
      XCTAssertEqual(error, .importFailedAfterReplacement)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(herdRepository.fetchCallCount, 1)
    XCTAssertEqual(base.accessHerdPublicIDs, [replacementHerd.publicID])
    XCTAssertEqual(policy.snapshot.access?.permission, .readOnly)
    XCTAssertEqual(policy.snapshot.access?.creationState, .acceptedParticipantShare)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .readOnlySharedHerd(reason: .animal, permission: .readOnly)
      )
    }
  }

  func testFailedDirectImportWithoutCurrentHerdRepositoryCannotRepublishWritableStaleAccess() async {
    let originalHerd = failedImportHerd(name: "Stale Original Herd", offset: 20)
    let base = FailedImportCurrentHerdSharingRepository(
      herdRepository: nil,
      replacementHerd: nil,
      replacementAccess: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )

    do {
      _ = try await repository.importSharedBridgeData(
        herd: originalHerd,
        storageMode: .iCloud
      )
      XCTFail("Expected the direct bridge import to fail.")
    } catch let error as FailedImportCurrentHerdTestError {
      XCTAssertEqual(error, .importFailedAfterReplacement)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.accessHerdPublicIDs, [originalHerd.publicID])
    XCTAssertNil(policy.snapshot.access)
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .pasture)
      )
    }
  }

  func testFailedDirectImportWithCurrentHerdRefetchFailureRemainsFailClosed() async {
    let originalHerd = failedImportHerd(name: "Original Herd", offset: 30)
    let herdRepository = FailedImportCurrentHerdRepository(
      currentHerd: originalHerd,
      failFetch: true
    )
    let base = FailedImportCurrentHerdSharingRepository(
      herdRepository: herdRepository,
      replacementHerd: nil,
      replacementAccess: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: herdRepository
    )

    do {
      _ = try await repository.importSharedBridgeData(
        herd: originalHerd,
        storageMode: .iCloud
      )
      XCTFail("Expected the direct bridge import to fail.")
    } catch let error as FailedImportCurrentHerdTestError {
      XCTAssertEqual(error, .importFailedAfterReplacement)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(herdRepository.fetchCallCount, 1)
    XCTAssertTrue(base.accessHerdPublicIDs.isEmpty)
    XCTAssertNil(policy.snapshot.access)
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
  }

  func testPrimaryPendingRecoveryReloadsReplacementHerdBeforeAccessRefresh() async throws {
    let originalHerd = failedImportHerd(name: "Original pending Herd", offset: 40)
    let replacementHerd = failedImportHerd(name: "Imported read-only Herd", offset: 50)
    let herdRepository = FailedImportCurrentHerdRepository(currentHerd: originalHerd)
    let sharingRepository = PrimaryActionReplacementSharingRepository(
      herdRepository: herdRepository,
      originalHerdID: originalHerd.publicID,
      replacementHerd: replacementHerd
    )
    let policy = HerdCollaborationWritePolicy()
    let viewModel = HerdCollaborationViewModel()
    viewModel.load(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud
    )
    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .iCloud,
      writePolicy: policy
    )
    XCTAssertEqual(viewModel.sharingAccess?.creationState, .pendingBridgeOperation)

    await viewModel.performPrimarySharingAction(
      herdRepository: herdRepository,
      using: sharingRepository,
      storageMode: .iCloud
    )
    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .iCloud,
      writePolicy: policy
    )

    XCTAssertEqual(sharingRepository.syncedHerdIDs, [originalHerd.publicID])
    XCTAssertEqual(viewModel.herd?.publicID, replacementHerd.publicID)
    XCTAssertEqual(
      sharingRepository.accessHerdIDs,
      [originalHerd.publicID, replacementHerd.publicID]
    )
    XCTAssertEqual(viewModel.sharingAccess?.permission, .readOnly)
    XCTAssertEqual(viewModel.sharingAccess?.creationState, .acceptedParticipantShare)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .herd)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .readOnlySharedHerd(reason: .herd, permission: .readOnly)
      )
    }
  }
}

private enum FailedImportCurrentHerdTestError: Error, Equatable {
  case importFailedAfterReplacement
  case currentHerdFetchFailed
}

private func failedImportHerd(name: String, offset: TimeInterval) -> HerdSummary {
  HerdSummary(
    publicID: UUID(),
    name: name,
    createdAt: Date(timeIntervalSince1970: offset),
    updatedAt: Date(timeIntervalSince1970: offset + 1),
    schemaVersion: 1
  )
}

@MainActor
private final class FailedImportCurrentHerdRepository: HerdRepository {
  private var currentHerd: HerdSummary
  private let failFetch: Bool
  private(set) var fetchCallCount = 0

  init(currentHerd: HerdSummary, failFetch: Bool = false) {
    self.currentHerd = currentHerd
    self.failFetch = failFetch
  }

  func replaceCurrentHerd(with herd: HerdSummary) {
    currentHerd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    fetchCallCount += 1
    if failFetch {
      throw FailedImportCurrentHerdTestError.currentHerdFetchFailed
    }
    return currentHerd
  }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    let renamed = HerdSummary(
      publicID: currentHerd.publicID,
      name: name,
      createdAt: currentHerd.createdAt,
      updatedAt: currentHerd.updatedAt,
      schemaVersion: currentHerd.schemaVersion
    )
    currentHerd = renamed
    return renamed
  }
}

@MainActor
private final class FailedImportCurrentHerdSharingRepository: HerdSharingRepository {
  private let herdRepository: FailedImportCurrentHerdRepository?
  private let replacementHerd: HerdSummary?
  private let replacementAccess: HerdSharingAccess
  private(set) var accessHerdPublicIDs: [UUID] = []

  init(
    herdRepository: FailedImportCurrentHerdRepository?,
    replacementHerd: HerdSummary?,
    replacementAccess: HerdSharingAccess
  ) {
    self.herdRepository = herdRepository
    self.replacementHerd = replacementHerd
    self.replacementAccess = replacementAccess
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
    if let herd {
      accessHerdPublicIDs.append(herd.publicID)
    }
    return replacementAccess
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
    if let replacementHerd {
      herdRepository?.replaceCurrentHerd(with: replacementHerd)
    }
    throw FailedImportCurrentHerdTestError.importFailedAfterReplacement
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
private final class PrimaryActionReplacementSharingRepository: HerdSharingRepository {
  private let herdRepository: FailedImportCurrentHerdRepository
  private let originalHerdID: UUID
  private let replacementHerd: HerdSummary
  private(set) var accessHerdIDs: [UUID] = []
  private(set) var syncedHerdIDs: [UUID] = []

  init(
    herdRepository: FailedImportCurrentHerdRepository,
    originalHerdID: UUID,
    replacementHerd: HerdSummary
  ) {
    self.herdRepository = herdRepository
    self.originalHerdID = originalHerdID
    self.replacementHerd = replacementHerd
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
    guard let herd else { throw HerdSharingActionError.shareRootMissing }
    accessHerdIDs.append(herd.publicID)
    if herd.publicID == originalHerdID {
      return HerdSharingAccess.ownerPrivateStore(participantCount: 1)
        .applyingCreationState(.pendingBridgeOperation)
    }
    return HerdSharingAccess.acceptedSharedStore(
      permission: .readOnly,
      participantCount: 2
    ).applyingCreationState(.acceptedParticipantShare)
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
    throw HerdSharingActionError.sharingStateUnavailable
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
    guard let herd else { throw HerdSharingActionError.shareRootMissing }
    syncedHerdIDs.append(herd.publicID)
    herdRepository.replaceCurrentHerd(with: replacementHerd)
    return HerdSharingActionResult(title: "Imported", message: "Imported replacement Herd")
  }
}


@MainActor
extension HerdSharingConflictingStoreTests {
  func testFailedOwnerStopCleanupRemainsDurablyBlockedAcrossRepositoryRecreation() async throws {
    let herd = OwnerStopTestFixture.herd()
    let presentation = OwnerStopTestFixture.presentation(for: herd)
    let writableAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let base = OwnerStopSharingRepository(
      access: writableAccess,
      manageResult: HerdSharingActionResult(
        title: "Manage",
        message: "Manage owner share",
        sharePresentation: presentation
      )
    )
    let suiteName = "HerdSharingConflictingStoreTests.OwnerStop.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let keyPrefix = "owner-stop-test.\(UUID().uuidString)"
    let firstStore = UserDefaultsHerdSharingOwnerStopCleanupStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: writableAccess)
    let systemShare = OwnerStopTestSystemShare.make { _ in
      throw OwnerStopTestError.cleanupFailed
    }
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: OwnerStopHerdRepository(herd: herd),
      ownerStopCleanupStore: firstStore,
      ownerShareSystemShareResolver: { _ in systemShare }
    )

    _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
    do {
      try await systemShare.stopSharing()
      XCTFail("Expected local owner-bridge purge failure.")
    } catch {
      XCTAssertEqual(error as? OwnerStopTestError, .cleanupFailed)
    }

    XCTAssertTrue(firstStore.isCleanupPending(for: herd.publicID))
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)

    let recreatedStore = UserDefaultsHerdSharingOwnerStopCleanupStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let recreatedRepository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      ownerStopCleanupStore: recreatedStore
    )
    let refreshedAccess = try await recreatedRepository.fetchSharingAccess(
      for: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(refreshedAccess.creationState, .ownerStopCleanupPending)
    XCTAssertFalse(refreshedAccess.allowsLocalMutations)
  }

  func testRetryOwnerStopCleanupClearsDurableBlockOnlyAfterPurgeSucceeds() async throws {
    let herd = OwnerStopTestFixture.herd()
    let presentation = OwnerStopTestFixture.presentation(for: herd)
    let writableAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let base = OwnerStopSharingRepository(
      access: writableAccess,
      manageResult: HerdSharingActionResult(
        title: "Manage",
        message: "Manage owner share",
        sharePresentation: presentation
      )
    )
    let suiteName = "HerdSharingConflictingStoreTests.OwnerStop.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let keyPrefix = "owner-stop-retry.\(UUID().uuidString)"
    let store = UserDefaultsHerdSharingOwnerStopCleanupStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    var cleanupAttemptCount = 0
    let systemShare = OwnerStopTestSystemShare.make { _ in
      cleanupAttemptCount += 1
      if cleanupAttemptCount == 1 {
        throw OwnerStopTestError.cleanupFailed
      }
      base.access = HerdSharingAccess.localOwnerBridgePending.applyingCreationState(
        .ownerBridgeVerificationRequired
      )
    }
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: writableAccess)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: OwnerStopHerdRepository(herd: herd),
      ownerStopCleanupStore: store,
      ownerShareSystemShareResolver: { _ in systemShare }
    )

    _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
    do {
      try await systemShare.stopSharing()
      XCTFail("Expected the first cleanup attempt to fail.")
    } catch {
      XCTAssertEqual(error as? OwnerStopTestError, .cleanupFailed)
    }
    XCTAssertTrue(store.isCleanupPending(for: herd.publicID))

    let result = try await repository.resetStaleOwnerSharingState(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Stop Sharing cleanup completed")
    XCTAssertEqual(cleanupAttemptCount, 2)
    XCTAssertEqual(base.manageCallCount, 1)
    XCTAssertEqual(base.cleanupManagementCallCount, 1)
    XCTAssertFalse(store.isCleanupPending(for: herd.publicID))
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
  }

  func testOwnerStopInvalidatesWritableAccessBeforeCleanupAndPublishesBlockingRefreshAfterCompletion() async throws {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Owner Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let presentation = HerdSharePresentationRequest(
      token: HerdShareToken(),
      title: herd.name,
      shareIdentifier: "owner-share",
      shareURL: URL(string: "https://www.icloud.com/share/owner-share")
    )
    let base = OwnerStopSharingRepository(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: true
      ).applyingCreationState(.existingOwnerShare),
      manageResult: HerdSharingActionResult(
        title: "Manage",
        message: "Manage owner share",
        sharePresentation: presentation
      )
    )
    let herdRepository = OwnerStopHerdRepository(herd: herd)
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: base.access)
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)

    var wasBlockedBeforeCleanup = false
    let systemShare = OwnerStopTestSystemShare.make { _ in
      wasBlockedBeforeCleanup = policy.snapshot.requiresVerifiedAccessBeforeWrite
        && !policy.snapshot.allowsLocalMutations
      base.access = HerdSharingAccess.localOwnerBridgePending.applyingCreationState(
        .ownerBridgeVerificationRequired
      )
    }
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: herdRepository,
      ownerShareSystemShareResolver: { request in
        XCTAssertEqual(request, presentation)
        return systemShare
      }
    )

    _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
    try await systemShare.stopSharing()

    XCTAssertTrue(wasBlockedBeforeCleanup)
    XCTAssertEqual(policy.snapshot.access?.creationState, .ownerBridgeVerificationRequired)
    XCTAssertFalse(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertEqual(base.fetchAccessCallCount, 2)
  }

  func testOwnerStopCompletionDoesNotRepublishUnexpectedWritableAccess() async throws {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Owner Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let presentation = HerdSharePresentationRequest(
      token: HerdShareToken(),
      title: herd.name,
      shareIdentifier: "owner-share",
      shareURL: nil
    )
    let writableAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let base = OwnerStopSharingRepository(
      access: writableAccess,
      manageResult: HerdSharingActionResult(
        title: "Manage",
        message: "Manage owner share",
        sharePresentation: presentation
      )
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: writableAccess)
    let systemShare = OwnerStopTestSystemShare.make { _ in }
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: OwnerStopHerdRepository(herd: herd),
      ownerShareSystemShareResolver: { _ in systemShare }
    )

    _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
    do {
      try await systemShare.stopSharing()
      XCTFail("Expected stale writable owner access to keep cleanup pending.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        return XCTFail("Unexpected sharing error: \(error)")
      }
    }

    XCTAssertNil(policy.snapshot.access)
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertEqual(base.fetchAccessCallCount, 2)
  }
}

@MainActor
private enum OwnerStopTestSystemShare {
  static func make(
    stopSharingHandler: @escaping @MainActor (CKShare) async throws -> Void
  ) -> CloudKitSystemShare {
    let zoneID = CKRecordZone.ID(
      zoneName: "owner-stop-test-zone",
      ownerName: CKCurrentUserDefaultName
    )
    let share = CKShare(recordZoneID: zoneID)
    return CloudKitSystemShare(
      title: "Owner Herd",
      share: share,
      containerProvider: {
        preconditionFailure("Owner-stop lifecycle tests must not present CloudKit UI.")
      },
      persistUpdatedShareHandler: { _ in },
      stopSharingHandler: stopSharingHandler
    )
  }
}

private enum OwnerStopTestError: Error, Equatable {
  case cleanupFailed
  case durableMarkerFailed
}

@MainActor
private final class OwnerStopCleanupTestStore: HerdSharingOwnerStopCleanupRecording {
  private let recordError: OwnerStopTestError?
  private var pendingHerdIDs: Set<UUID> = []

  init(recordError: OwnerStopTestError? = nil) {
    self.recordError = recordError
  }

  func isCleanupPending(for herdPublicID: UUID) -> Bool {
    pendingHerdIDs.contains(herdPublicID)
  }

  func recordCleanupPending(for herdPublicID: UUID) throws {
    if let recordError { throw recordError }
    pendingHerdIDs.insert(herdPublicID)
  }

  func clearCleanupPending(for herdPublicID: UUID) throws {
    pendingHerdIDs.remove(herdPublicID)
  }
}

@MainActor
private enum OwnerStopTestFixture {
  static func herd() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Owner Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }

  static func presentation(for herd: HerdSummary) -> HerdSharePresentationRequest {
    HerdSharePresentationRequest(
      token: HerdShareToken(),
      title: herd.name,
      shareIdentifier: "owner-share",
      shareURL: nil
    )
  }
}


@MainActor
private final class OwnerStopHerdRepository: HerdRepository {
  private let herd: HerdSummary

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    herd
  }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    herd
  }
}

@MainActor
private final class OwnerStopSharingRepository: HerdSharingRepository,
  HerdSharingRetainedOwnerShareCleanupManaging
{
  var access: HerdSharingAccess
  let manageResult: HerdSharingActionResult
  private(set) var fetchAccessCallCount = 0
  private(set) var manageCallCount = 0
  private(set) var cleanupManagementCallCount = 0

  init(access: HerdSharingAccess, manageResult: HerdSharingActionResult) {
    self.access = access
    self.manageResult = manageResult
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
    fetchAccessCallCount += 1
    return access
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    manageResult
  }

  func manageExistingShare(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    manageCallCount += 1
    return manageResult
  }

  func manageRetainedOwnerShareForStopCleanup(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    cleanupManagementCallCount += 1
    return manageResult
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
extension HerdSharingConflictingStoreTests {
  func testInitialAccessVerificationBlocksFirstWriteUntilAccessIsLoaded() {
    let policy = HerdCollaborationWritePolicy(
      requiresInitialAccessVerification: true
    )
    var refreshRequestCount = 0
    policy.setAccessRefreshRequestHandler { _ in
      refreshRequestCount += 1
    }

    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .animal)
      )
    }
    XCTAssertEqual(refreshRequestCount, 1)

    policy.clearAccess()
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .pasture)
      )
    }

    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )

    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
    XCTAssertNoThrow(try policy.validateCanWrite(reason: .animal))
  }

  func testAppDependenciesRequireInitialVerificationOnlyForICloudStorage() throws {
    let iCloudContainer = try TestSupport.makeModelContainer()
    let iCloudDependencies = AppDependencies(
      modelContainer: iCloudContainer,
      storageMode: .iCloud
    )
    XCTAssertTrue(
      iCloudDependencies.herdCollaborationWritePolicy.snapshot.requiresVerifiedAccessBeforeWrite
    )
    XCTAssertFalse(iCloudDependencies.herdCollaborationWritePolicy.snapshot.allowsLocalMutations)

    let localContainer = try TestSupport.makeModelContainer()
    let localDependencies = AppDependencies(
      modelContainer: localContainer,
      storageMode: .localOnly
    )
    XCTAssertFalse(
      localDependencies.herdCollaborationWritePolicy.snapshot.requiresVerifiedAccessBeforeWrite
    )
    XCTAssertTrue(localDependencies.herdCollaborationWritePolicy.snapshot.allowsLocalMutations)
  }

  func testFailedPostSyncAccessVerificationKeepsWritesBlockedUntilAccessIsVerified() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      ).applyingCreationState(.pendingBridgeOperation)
    )
    var refreshRequestCount = 0
    policy.setAccessRefreshRequestHandler { _ in
      refreshRequestCount += 1
    }

    policy.clearAccessAfterFailedSynchronization()

    XCTAssertNil(policy.snapshot.access)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .animal)
      )
    }
    XCTAssertEqual(refreshRequestCount, 1)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
  }

  func testOrdinaryClearAccessDoesNotCarryForwardAFormerSharedWriteBlock() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: .acceptedSharedStore(permission: .readOnly, participantCount: 2)
    )

    policy.clearAccess()

    XCTAssertNil(policy.snapshot.access)
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
    XCTAssertNoThrow(try policy.validateCanWrite(reason: .pasture))
  }

  func testFailedDirectImportPublishesPendingAccessBeforeAnotherLocalWrite() async {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Direct Import Failure Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let pendingAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 2,
      hasActiveSystemShare: true
    ).applyingCreationState(.pendingBridgeOperation)
    let base = SharedImportFailureSharingRepository(accessAfterFailure: pendingAccess)
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      ).applyingCreationState(.existingOwnerShare)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )

    do {
      _ = try await repository.importSharedBridgeData(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected the direct bridge import to fail.")
    } catch let error as SharedImportFailureTestError {
      XCTAssertEqual(error, .importFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.importCallCount, 1)
    XCTAssertEqual(base.accessCallCount, 1)
    XCTAssertEqual(policy.snapshot.access?.creationState, .pendingBridgeOperation)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingRecoveryPending(reason: .animal)
      )
    }
  }

  func testFailedDirectImportWithUnrefreshableAccessRequiresVerificationBeforeWrite() async {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Direct Import Access Failure Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let base = SharedImportFailureSharingRepository(
      accessAfterFailure: .localOwnerBridgePending,
      failAccessRefresh: true
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      ).applyingCreationState(.existingOwnerShare)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )

    do {
      _ = try await repository.importSharedBridgeData(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected the direct bridge import to fail.")
    } catch let error as SharedImportFailureTestError {
      XCTAssertEqual(error, .importFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.importCallCount, 1)
    XCTAssertEqual(base.accessCallCount, 1)
    XCTAssertNil(policy.snapshot.access)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .pasture)
      )
    }
  }

  func testPreAcceptInvitationFailureLeavesWritableAccessUntouched() async {
    let preAcceptError = HerdSharingActionError.cloudKitSharingFailed("Network unavailable before acceptance.")
    let base = SharedImportFailureSharingRepository(
      accessAfterFailure: .localOwnerBridgePending,
      invitationError: preAcceptError
    )
    let policy = HerdCollaborationWritePolicy()
    let originalAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: false
    ).applyingCreationState(.ready)
    policy.update(access: originalAccess)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )

    do {
      _ = try await repository.acceptShareInvitation(
        makeTestInvitation(),
        storageMode: .iCloud
      )
      XCTFail("Expected the invitation to fail before CloudKit acceptance.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, preAcceptError)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.invitationCallCount, 1)
    XCTAssertEqual(base.accessCallCount, 0)
    XCTAssertEqual(policy.snapshot.access, originalAccess)
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
    XCTAssertNoThrow(try policy.validateCanWrite(reason: .animal))
  }

  func testAcceptedInvitationImportFailureRequiresVerificationBeforeAnotherLocalWrite() async {
    let postAcceptError = HerdSharingActionError.bridgeImportRequiresAccessVerification(
      "Simulated committed invitation import failure."
    )
    let base = SharedImportFailureSharingRepository(
      accessAfterFailure: .localOwnerBridgePending,
      invitationError: postAcceptError
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )

    do {
      _ = try await repository.acceptShareInvitation(
        makeTestInvitation(),
        storageMode: .iCloud
      )
      XCTFail("Expected the invitation import to fail after CloudKit acceptance.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, postAcceptError)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.invitationCallCount, 1)
    XCTAssertEqual(base.accessCallCount, 0)
    XCTAssertNil(policy.snapshot.access)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .pasture)
      )
    }
  }

  func testUnscopedImportBoundaryPreservesRetryableBridgeImportFailure() {
    let original = HerdSharingActionError.bridgeImportFailed("Shared records are not available yet.")

    let mapped = HerdSharingCoreDataStore.unscopedImportBoundaryError(original)

    XCTAssertEqual(mapped as? HerdSharingActionError, original)
  }

  func testUnscopedImportBoundaryMarksNonRetryableFailureForAccessVerification() {
    let mapped = HerdSharingCoreDataStore.unscopedImportBoundaryError(
      SharedImportFailureTestError.importFailed
    )

    guard case .bridgeImportRequiresAccessVerification(let message)? = mapped as? HerdSharingActionError else {
      XCTFail("Expected the unscoped import boundary to require access verification.")
      return
    }
    XCTAssertFalse(message.isEmpty)
  }

  func testFailedDirectSyncPublishesPendingAccessBeforeAnotherLocalWrite() async {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Direct Sync Failure Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let pendingAccess = HerdSharingAccess.acceptedSharedStore(
      permission: .readWrite,
      participantCount: 2
    ).applyingCreationState(.pendingBridgeOperation)
    let base = SharedImportFailureSharingRepository(
      accessAfterFailure: pendingAccess,
      failSync: true
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.acceptedSharedStore(
        permission: .readWrite,
        participantCount: 2
      ).applyingCreationState(.acceptedParticipantShare)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected direct shared-data synchronization to fail.")
    } catch let error as SharedImportFailureTestError {
      XCTAssertEqual(error, .syncFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.syncCallCount, 1)
    XCTAssertEqual(base.accessCallCount, 1)
    XCTAssertEqual(policy.snapshot.access?.creationState, .pendingBridgeOperation)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingRecoveryPending(reason: .animal)
      )
    }
  }

  func testFailedDirectSyncWithUnrefreshableAccessRequiresVerificationBeforeWrite() async {
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Direct Sync Access Failure Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let base = SharedImportFailureSharingRepository(
      accessAfterFailure: .localOwnerBridgePending,
      failAccessRefresh: true,
      failSync: true
    )
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.acceptedSharedStore(
        permission: .readWrite,
        participantCount: 2
      ).applyingCreationState(.acceptedParticipantShare)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy
    )

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected direct shared-data synchronization to fail.")
    } catch let error as SharedImportFailureTestError {
      XCTAssertEqual(error, .syncFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.syncCallCount, 1)
    XCTAssertEqual(base.accessCallCount, 1)
    XCTAssertNil(policy.snapshot.access)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .pasture)
      )
    }
  }
}

private enum SharedImportFailureTestError: Error, Equatable {
  case importFailed
  case syncFailed
  case accessRefreshFailed
}

private func makeTestInvitation() -> HerdShareInvitation {
  HerdShareInvitation(
    token: HerdShareToken(),
    containerIdentifier: "iCloud.com.example.yaHerd",
    shareIdentifier: "test-share",
    rootIdentifier: "test-root",
    ownerIdentifier: "test-owner",
    ownerDisplayName: "Test Owner",
    participantRole: .privateUser,
    permission: .readWrite,
    status: .pending,
    shareURL: nil
  )
}

@MainActor
private final class SharedImportFailureSharingRepository: HerdSharingRepository {
  private let accessAfterFailure: HerdSharingAccess
  private let failAccessRefresh: Bool
  private let invitationError: HerdSharingActionError?
  private let failSync: Bool
  private(set) var importCallCount = 0
  private(set) var invitationCallCount = 0
  private(set) var syncCallCount = 0
  private(set) var accessCallCount = 0

  init(
    accessAfterFailure: HerdSharingAccess,
    failAccessRefresh: Bool = false,
    invitationError: HerdSharingActionError? = nil,
    failSync: Bool = false
  ) {
    self.accessAfterFailure = accessAfterFailure
    self.failAccessRefresh = failAccessRefresh
    self.invitationError = invitationError
    self.failSync = failSync
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
    if failAccessRefresh {
      throw SharedImportFailureTestError.accessRefreshFailed
    }
    return accessAfterFailure
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
    invitationCallCount += 1
    if let invitationError {
      throw invitationError
    }
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    importCallCount += 1
    throw SharedImportFailureTestError.importFailed
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
    if failSync {
      throw SharedImportFailureTestError.syncFailed
    }
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }
}
@MainActor
extension HerdSharingConflictingStoreTests {
  func testOrphanConflictCleanupRemovesOnlySelectedHerdGraph() async throws {
    let directory = conflictResolutionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try await makeConflictResolutionStore(at: directory)
    let privateStore = try XCTUnwrap(store.privateStore)

    let timestamp = Date(timeIntervalSince1970: 1_700_100_000)
    let discardedHerdID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let discardedAnimalID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    let retainedHerdID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    let retainedAnimalID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    try await seedConflictResolutionBridgeGraph(
      store: store,
      persistentStore: privateStore,
      herdID: discardedHerdID,
      herdName: "Discarded orphan",
      animalID: discardedAnimalID,
      timestamp: timestamp
    )
    try await seedConflictResolutionBridgeGraph(
      store: store,
      persistentStore: privateStore,
      herdID: retainedHerdID,
      herdName: "Unrelated retained herd",
      animalID: retainedAnimalID,
      timestamp: timestamp
    )

    try await store.deleteOrphanConflictBridgeGraph(
      herdPublicID: discardedHerdID,
      store: privateStore,
      storeDescription: "test owner private bridge"
    )

    do {
      _ = try await store.readBridgeSnapshot(
        from: privateStore,
        requestedHerdPublicID: discardedHerdID,
        storeDescription: "discarded orphan verification"
      )
      XCTFail("Expected the discarded orphan Herd graph to be absent.")
    } catch let error as HerdSharingBridgeSnapshotError {
      guard case .missingHerdRecord(let missingHerdID) = error else {
        XCTFail("Expected a missing Herd root after exact orphan cleanup, got \(error)")
        return
      }
      XCTAssertEqual(missingHerdID, discardedHerdID)
    }

    let retainedSnapshot = try await store.readBridgeSnapshot(
      from: privateStore,
      requestedHerdPublicID: retainedHerdID,
      storeDescription: "unrelated retained verification"
    )
    XCTAssertEqual(
      Set(retainedSnapshot.records(for: .herd).compactMap(\.parsedPublicID)),
      [retainedHerdID]
    )
    XCTAssertEqual(
      Set(retainedSnapshot.records(for: .animals).compactMap(\.parsedPublicID)),
      [retainedAnimalID]
    )
  }

  func testKeepOwnerRemovesOrphanSharedRootWithoutCloudKitMetadata() async throws {
    let directory = conflictResolutionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try await makeConflictResolutionStore(at: directory)
    let privateStore = try XCTUnwrap(store.privateStore)
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let timestamp = Date(timeIntervalSince1970: 1_700_200_000)
    let herdID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

    try await seedConflictResolutionBridgeGraph(
      store: store,
      persistentStore: privateStore,
      herdID: herdID,
      herdName: "Owner copy",
      animalID: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
      timestamp: timestamp
    )
    try await seedConflictResolutionBridgeGraph(
      store: store,
      persistentStore: sharedStore,
      herdID: herdID,
      herdName: "Orphan shared copy",
      animalID: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
      timestamp: timestamp
    )

    let herd = HerdSummary(
      publicID: herdID,
      name: "Owner copy",
      createdAt: timestamp,
      updatedAt: timestamp,
      schemaVersion: 1
    )
    let accessBefore = try await store.fetchSharingAccess(for: herd)
    XCTAssertTrue(accessBefore.hasConflictingBridgeRecords)

    let accessAfter = try await store.resolveBridgeConflict(
      for: herd,
      keeping: .keepOwnerShare
    )

    XCTAssertFalse(accessAfter.hasConflictingBridgeRecords)
    XCTAssertEqual(accessAfter.bridgeLocation, .ownerPrivateStore)
    XCTAssertFalse(accessAfter.hasActiveSystemShare)
    do {
      _ = try await store.readBridgeSnapshot(
        from: sharedStore,
        requestedHerdPublicID: herdID,
        storeDescription: "discarded orphan shared verification"
      )
      XCTFail("Expected the orphan shared Herd graph to be removed.")
    } catch let error as HerdSharingBridgeSnapshotError {
      guard case .missingHerdRecord(let missingHerdID) = error else {
        XCTFail("Expected a missing shared Herd root, got \(error)")
        return
      }
      XCTAssertEqual(missingHerdID, herdID)
    }
  }

  func testKeepAcceptedRejectsOrphanSharedRootWithoutCloudKitMetadata() async throws {
    let directory = conflictResolutionTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try await makeConflictResolutionStore(at: directory)
    let privateStore = try XCTUnwrap(store.privateStore)
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let timestamp = Date(timeIntervalSince1970: 1_700_300_000)
    let herdID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!

    try await seedConflictResolutionBridgeGraph(
      store: store,
      persistentStore: privateStore,
      herdID: herdID,
      herdName: "Owner copy",
      animalID: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!,
      timestamp: timestamp
    )
    try await seedConflictResolutionBridgeGraph(
      store: store,
      persistentStore: sharedStore,
      herdID: herdID,
      herdName: "Invalid accepted copy",
      animalID: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!,
      timestamp: timestamp
    )

    let herd = HerdSummary(
      publicID: herdID,
      name: "Owner copy",
      createdAt: timestamp,
      updatedAt: timestamp,
      schemaVersion: 1
    )

    do {
      _ = try await store.resolveBridgeConflict(
        for: herd,
        keeping: .keepAcceptedShare
      )
      XCTFail("Expected an orphan shared root without CKShare metadata to be non-retainable.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridge consistency failure, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("cannot be retained"))
    }

    let accessAfter = try await store.fetchSharingAccess(for: herd)
    XCTAssertTrue(accessAfter.hasConflictingBridgeRecords)
  }

  private func makeConflictResolutionStore(
    at directory: URL
  ) async throws -> HerdSharingCoreDataStore {
    let store = HerdSharingCoreDataStore(
      storeDirectoryURL: directory,
      journalFileURL: directory.appendingPathComponent("journal.json")
    )
    store.persistentContainer.persistentStoreDescriptions = [
      conflictResolutionPlainStoreDescription(
        at: directory.appendingPathComponent(HerdSharingCoreDataStore.privateStoreFileName)
      ),
      conflictResolutionPlainStoreDescription(
        at: directory.appendingPathComponent(HerdSharingCoreDataStore.sharedStoreFileName)
      ),
    ]
    try await store.loadIfNeeded()
    return store
  }

  private func seedConflictResolutionBridgeGraph(
    store: HerdSharingCoreDataStore,
    persistentStore: NSPersistentStore,
    herdID: UUID,
    herdName: String,
    animalID: UUID,
    timestamp: Date
  ) async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = Herd(
      publicID: herdID,
      name: herdName,
      createdAt: timestamp,
      updatedAt: timestamp
    )
    let animal = Animal(
      publicID: animalID,
      name: "Animal \(animalID.uuidString.prefix(4))",
      tagNumber: animalID.uuidString.prefix(4).description,
      birthDate: timestamp,
      sex: .female
    )
    animal.herd = herd
    context.insert(herd)
    context.insert(animal)
    try context.save()

    let actor = SwiftDataHerdSharingActor(modelContainer: container)
    let export = try await actor.makeExport(
      for: herd.toSummary(),
      storeDescription: "conflict-resolution-seed"
    )
    _ = try await store.writeBridgeSnapshot(export.snapshot, to: persistentStore)
  }

  private func conflictResolutionTestDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("HerdSharingBridgeConflictResolverIntegrationTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func conflictResolutionPlainStoreDescription(
    at url: URL
  ) -> NSPersistentStoreDescription {
    let description = NSPersistentStoreDescription(url: url)
    description.type = NSSQLiteStoreType
    description.shouldMigrateStoreAutomatically = true
    description.shouldInferMappingModelAutomatically = true
    return description
  }
}

// MARK: - Journal rollback compatibility

@MainActor
extension HerdSharingConflictingStoreTests {
  func testKnownParticipantWithUnavailableBridgeBlocksLocalWrites() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.localOwnerBridgePending
        .applyingCreationState(.notOwnedByCurrentDevice)
    )

    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .participantBridgeUnavailable(reason: .animal)
      )
    }
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertTrue(policy.snapshot.statusDescription.contains("accepted participant copy"))
  }

  func testUnverifiedOwnerBridgeBlocksLocalWritesUntilRecoveryDecision() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: HerdSharingAccess.localOwnerBridgePending
        .applyingCreationState(.ownerBridgeVerificationRequired)
    )

    XCTAssertThrowsError(try policy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .ownerSharingStateUnverified(reason: .pasture)
      )
    }
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertTrue(policy.snapshot.statusDescription.contains("owner bridge"))
  }
}
