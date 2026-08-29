//
//  HerdSharingSyncCoordinatorTests.swift
//  yaHerdTests
//

import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingSyncCoordinatorTests: XCTestCase {
  func testSyncNowSkipsLocalOnlyStorageBeforeRepositoryCall() async {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .localOnly,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertFalse(didSync)
    XCTAssertEqual(coordinator.lastSkippedReason, "iCloud Sync is not enabled.")
    XCTAssertEqual(sharingRepository.syncCallCount, 0)
  }

  func testSyncNowRunsManualSharedDataSync() async {
    let herd = makeHerdSummary()
    let herdRepository = StubHerdRepository(herd: herd)
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertTrue(didSync)
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(sharingRepository.syncedHerdPublicID, herd.publicID)
    XCTAssertEqual(coordinator.lastTriggerDescription, "manual sync")
    XCTAssertNil(coordinator.lastErrorMessage)
    XCTAssertNotNil(coordinator.lastSuccessMessage)
  }

  func testSyncNowStoresStructuredConflictReview() async {
    let herd = makeHerdSummary()
    let conflictReview = makeConflictReview()
    let herdRepository = StubHerdRepository(herd: herd)
    let sharingRepository = RecordingHerdSharingRepository(conflictReview: conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertTrue(didSync)
    XCTAssertEqual(coordinator.lastConflictReview, conflictReview)
  }

  func testClearConflictReviewClearsStoredReview() async {
    let herd = makeHerdSummary()
    let conflictReview = makeConflictReview()
    let herdRepository = StubHerdRepository(herd: herd)
    let sharingRepository = RecordingHerdSharingRepository(conflictReview: conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    _ = await coordinator.syncNow(trigger: .manual)
    coordinator.clearConflictReview()

    XCTAssertNil(coordinator.lastConflictReview)
  }

  func testAutomaticSyncDebouncesAndRunsOnce() async throws {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 10_000_000,
      minimumAutomaticSyncInterval: 0
    )

    coordinator.requestAutomaticSync(trigger: .appLaunch)
    coordinator.requestAutomaticSync(trigger: .appForeground)

    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(coordinator.lastTriggerDescription, "app foreground")
  }

  func testDataMutationSyncBypassesLifecycleThrottle() async throws {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 3_600
    )

    coordinator.requestAutomaticSync(trigger: .appForeground)
    try await Task.sleep(for: .milliseconds(20))
    coordinator.requestSharedDataSyncAfterMutation(reason: .animal)
    try await Task.sleep(for: .milliseconds(20))

    XCTAssertEqual(sharingRepository.syncCallCount, 2)
    XCTAssertEqual(coordinator.lastTriggerDescription, "animal change")
  }

  func testSyncNowUpdatesWritePolicyFromSharingAccess() async {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository(
      access: .acceptedSharedStore(permission: .readOnly, participantCount: 2)
    )
    let writePolicy = HerdCollaborationWritePolicy()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertTrue(didSync)
    XCTAssertFalse(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertEqual(writePolicy.snapshot.access?.permission, .readOnly)
  }

  func testSyncNowInvalidatesPriorWritablePolicyWhenInitialAccessRevalidationFails() async {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository(
      access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
        .applyingCreationState(.existingOwnerShare)
    )
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
        .applyingCreationState(.existingOwnerShare)
    )
    sharingRepository.setAccessError(HerdSharingActionError.ownerBridgeVerificationRequired)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let didSync = await coordinator.syncNow(trigger: .manual)

    XCTAssertFalse(didSync)
    XCTAssertTrue(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertNotNil(coordinator.lastErrorMessage)
  }

  func testRefreshSharingAccessNowUpdatesWritePolicyWithoutSyncingData() async {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository(
      access: .acceptedSharedStore(permission: .readOnly, participantCount: 2)
    )
    let writePolicy = HerdCollaborationWritePolicy()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let refreshed = await coordinator.refreshSharingAccessNow(trigger: .screenOpened("Animals"))

    XCTAssertTrue(refreshed)
    XCTAssertEqual(sharingRepository.accessCallCount, 1)
    XCTAssertEqual(sharingRepository.syncCallCount, 0)
    XCTAssertFalse(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertEqual(coordinator.lastAccessRefreshTriggerDescription, "Animals opened")
    XCTAssertNil(coordinator.lastAccessRefreshErrorMessage)
  }

  func testRefreshSharingAccessNowInvalidatesWritablePolicyWhenRevalidationFails() async {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository(
      access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
        .applyingCreationState(.existingOwnerShare)
    )
    let writePolicy = HerdCollaborationWritePolicy()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let firstRefresh = await coordinator.refreshSharingAccessNow(trigger: .appLaunch)
    XCTAssertTrue(firstRefresh)
    XCTAssertTrue(writePolicy.snapshot.allowsLocalMutations)

    sharingRepository.setAccessError(HerdSharingActionError.ownerBridgeVerificationRequired)
    let failedRefresh = await coordinator.refreshSharingAccessNow(
      trigger: .manual,
      minimumInterval: 0
    )

    XCTAssertFalse(failedRefresh)
    XCTAssertTrue(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertNotNil(coordinator.lastAccessRefreshErrorMessage)
    XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .herd)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .herd)
      )
    }
  }

  func testRefreshSharingAccessDiscardsResultWhenCurrentHerdChangesDuringLookup() async {
    let originalHerd = makeHerdSummary()
    let replacementHerd = makeHerdSummary()
    let herdRepository = StubHerdRepository(herd: originalHerd)
    let sharingRepository = RecordingHerdSharingRepository(
      access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
        .applyingCreationState(.existingOwnerShare)
    )
    sharingRepository.suspendAccessLookups()
    let writePolicy = HerdCollaborationWritePolicy(requiresInitialAccessVerification: true)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let refreshTask = Task { @MainActor in
      await coordinator.refreshSharingAccessNow(trigger: .manual, minimumInterval: 0)
    }
    while !sharingRepository.accessLookupStarted {
      await Task.yield()
    }
    herdRepository.replaceCurrentHerd(with: replacementHerd)
    sharingRepository.resumeAccessLookups()

    let refreshed = await refreshTask.value

    XCTAssertFalse(refreshed)
    XCTAssertEqual(sharingRepository.accessedHerdPublicIDs, [originalHerd.publicID])
    XCTAssertNil(writePolicy.snapshot.access)
    XCTAssertTrue(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertTrue(
      coordinator.lastAccessRefreshErrorMessage?.contains("current Herd changed") == true
    )
  }

  func testRefreshSharingAccessDiscardsSameHerdResultWhenSharingStateChangesDuringLookup() async {
    let herd = makeHerdSummary()
    let herdRepository = StubHerdRepository(herd: herd)
    let sharingRepository = RecordingHerdSharingRepository(
      access: .localOwnerBridgePending
    )
    sharingRepository.suspendAccessLookups()
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(access: .localOwnerBridgePending)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let refreshTask = Task { @MainActor in
      await coordinator.refreshSharingAccessNow(trigger: .manual, minimumInterval: 0)
    }
    while !sharingRepository.accessLookupStarted {
      await Task.yield()
    }

    // Models invitation acceptance publishing newer authority for the same Herd public ID.
    let participantAccess = HerdSharingAccess.acceptedSharedStore(
      permission: .readOnly,
      participantCount: 2
    )
    writePolicy.update(access: participantAccess)
    sharingRepository.resumeAccessLookups()

    let refreshed = await refreshTask.value

    XCTAssertFalse(refreshed)
    XCTAssertEqual(writePolicy.snapshot.access, participantAccess)
    XCTAssertFalse(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertTrue(
      coordinator.lastAccessRefreshErrorMessage?.contains("sharing state changed") == true
    )
  }

  func testPostSyncAccessRevalidationPreservesNewerPolicyStateWhenLookupBecomesStale()
    async
  {
    let herd = makeHerdSummary()
    let herdRepository = StubHerdRepository(herd: herd)
    let sharingRepository = RecordingHerdSharingRepository(
      access: .localOwnerBridgePending
    )
    sharingRepository.suspendAccessLookup(callNumber: 2)
    let writePolicy = HerdCollaborationWritePolicy()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let syncTask = Task { @MainActor in
      await coordinator.performSync(trigger: .manual)
    }
    while sharingRepository.accessCallCount < 2 {
      await Task.yield()
    }

    let ownerStopAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.ownerStopCleanupPending)
    writePolicy.update(access: ownerStopAccess)
    sharingRepository.resumeAccessLookups()

    let synchronized = await syncTask.value

    XCTAssertFalse(synchronized)
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(writePolicy.snapshot.access, ownerStopAccess)
    XCTAssertFalse(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertTrue(coordinator.lastErrorMessage?.contains("sharing state changed") == true)
  }

  func testRefreshSharingAccessNowThrottlesScreenOpenRequests() async {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let firstRefresh = await coordinator.refreshSharingAccessNow(
      trigger: .screenOpened("Animals"),
      minimumInterval: 60
    )
    let secondRefresh = await coordinator.refreshSharingAccessNow(
      trigger: .screenOpened("Pastures"),
      minimumInterval: 60
    )

    XCTAssertTrue(firstRefresh)
    XCTAssertFalse(secondRefresh)
    XCTAssertEqual(sharingRepository.accessCallCount, 1)
    XCTAssertEqual(
      coordinator.lastAccessRefreshSkippedReason,
      "Skipped sharing-access refresh because the previous access refresh was recent."
    )
  }

  func testMutationSchedulerRequestsCoordinatorSyncAfterAttach() async throws {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )
    let scheduler = HerdSharingMutationSyncScheduler(mutationDebounceNanoseconds: 0)

    scheduler.attach(coordinator: coordinator)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
    try await Task.sleep(for: .milliseconds(20))

    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(coordinator.lastTriggerDescription, "pasture change")
  }

  func testMutationSchedulerCoalescesToLatestReason() async throws {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )
    let scheduler = HerdSharingMutationSyncScheduler(mutationDebounceNanoseconds: 10_000_000)

    scheduler.attach(coordinator: coordinator)
    scheduler.requestSharedDataSyncAfterMutation(reason: .animal)
    scheduler.requestSharedDataSyncAfterMutation(reason: .working)
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(coordinator.lastTriggerDescription, "working change")
  }

  func testMutationSchedulerRetainsPendingReasonUntilCoordinatorAttaches() async throws {
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )
    let scheduler = HerdSharingMutationSyncScheduler(mutationDebounceNanoseconds: 0)

    scheduler.requestSharedDataSyncAfterMutation(reason: .fieldCheck)
    scheduler.attach(coordinator: coordinator)
    try await Task.sleep(for: .milliseconds(20))

    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(coordinator.lastTriggerDescription, "field check change")
  }

  func testResolveConflictByKeepingLocalRecordsStoresResolutionAndClearsActiveReview() async {
    let suiteName = "HerdSharingSyncCoordinatorTests.resolve.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let conflictReviewStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let conflictReview = makeConflictReview()
    conflictReviewStore.record(conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      conflictReviewStore: conflictReviewStore,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let resolved = await coordinator.resolveConflictByKeepingLocalRecords(
      conflictReview,
      syncAfterResolution: false
    )

    XCTAssertTrue(resolved)
    XCTAssertNil(coordinator.lastConflictReview)
    XCTAssertTrue(conflictReviewStore.reviewHistory.isEmpty)
    XCTAssertEqual(conflictReviewStore.resolutionHistory.first?.reviewID, conflictReview.id)
    XCTAssertEqual(sharingRepository.syncCallCount, 0)
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testResolveConflictByKeepingLocalRecordsCanRunSyncAfterResolution() async {
    let suiteName = "HerdSharingSyncCoordinatorTests.resolveSync.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let conflictReviewStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let conflictReview = makeConflictReview()
    conflictReviewStore.record(conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      conflictReviewStore: conflictReviewStore,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let resolved = await coordinator.resolveConflictByKeepingLocalRecords(
      conflictReview,
      syncAfterResolution: true
    )

    XCTAssertTrue(resolved)
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(conflictReviewStore.resolutionHistory.first?.reviewID, conflictReview.id)
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testResolveConflictByAcceptingSharedUpdatesStoresResolutionWithoutRepositoryWrite() async {
    let suiteName = "HerdSharingSyncCoordinatorTests.acceptUpdates.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let conflictReviewStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let conflictReview = makeUpdatedRecordConflictReview()
    conflictReviewStore.record(conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      conflictReviewStore: conflictReviewStore,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let resolved = await coordinator.resolveConflictByAcceptingSharedUpdates(
      conflictReview,
      syncAfterResolution: false
    )

    XCTAssertTrue(resolved)
    XCTAssertEqual(sharingRepository.acceptSharedDeleteCallCount, 0)
    XCTAssertEqual(sharingRepository.syncCallCount, 0)
    XCTAssertNil(coordinator.lastConflictReview)
    XCTAssertEqual(conflictReviewStore.resolutionHistory.first?.reviewID, conflictReview.id)
    XCTAssertEqual(
      conflictReviewStore.resolutionHistory.first?.choice,
      Optional(HerdSharingConflictResolutionChoice.acceptSharedUpdates)
    )
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testResolveConflictByAcceptingSharedDeletesDeletesRecordsStoresResolutionAndRunsSync() async
  {
    let suiteName = "HerdSharingSyncCoordinatorTests.acceptDelete.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let conflictReviewStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let conflictReview = makeConflictReview()
    conflictReviewStore.record(conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      conflictReviewStore: conflictReviewStore,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )

    let resolved = await coordinator.resolveConflictByAcceptingSharedDeletes(
      conflictReview,
      syncAfterResolution: true
    )

    XCTAssertTrue(resolved)
    XCTAssertEqual(sharingRepository.acceptSharedDeleteCallCount, 1)
    XCTAssertEqual(sharingRepository.acceptedSharedDeleteReview, Optional(conflictReview))
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertNil(coordinator.lastConflictReview)
    XCTAssertEqual(conflictReviewStore.resolutionHistory.first?.reviewID, conflictReview.id)
    XCTAssertEqual(
      conflictReviewStore.resolutionHistory.first?.choice,
      Optional(HerdSharingConflictResolutionChoice.acceptSharedDeletes)
    )
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testRestoreLocalFieldsCanResolveReviewAndRunSync() async {
    let suiteName = "HerdSharingSyncCoordinatorTests.restoreResolve.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let conflictReviewStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let conflictReview = makeUpdatedRecordConflictReview()
    conflictReviewStore.record(conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      conflictReviewStore: conflictReviewStore,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )
    let selections = [
      HerdSharingLocalFieldRestoreSelection(
        sourceEntityName: "SharedAnimalRecord",
        publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        fieldName: "tagNumber"
      )
    ]

    let restored = await coordinator.restoreLocalFieldsFromConflict(
      selections,
      in: conflictReview,
      syncAfterResolution: true,
      resolveAfterRestore: true
    )

    XCTAssertTrue(restored)
    XCTAssertEqual(sharingRepository.restoreLocalFieldsCallCount, 1)
    XCTAssertEqual(sharingRepository.restoredLocalFieldSelections, selections)
    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertNil(coordinator.lastConflictReview)
    XCTAssertTrue(conflictReviewStore.reviewHistory.isEmpty)
    XCTAssertEqual(conflictReviewStore.resolutionHistory.first?.reviewID, conflictReview.id)
    XCTAssertEqual(
      conflictReviewStore.resolutionHistory.first?.choice,
      Optional(HerdSharingConflictResolutionChoice.restoreLocalFields)
    )
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testRestoreLocalFieldsWithoutResolveKeepsReviewOpen() async {
    let suiteName = "HerdSharingSyncCoordinatorTests.restoreOnly.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let conflictReviewStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    let herdRepository = StubHerdRepository(herd: makeHerdSummary())
    let sharingRepository = RecordingHerdSharingRepository()
    let conflictReview = makeUpdatedRecordConflictReview()
    conflictReviewStore.record(conflictReview)
    let coordinator = HerdSharingSyncCoordinator(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud,
      conflictReviewStore: conflictReviewStore,
      automaticDebounceNanoseconds: 0,
      minimumAutomaticSyncInterval: 0
    )
    let selections = [
      HerdSharingLocalFieldRestoreSelection(
        sourceEntityName: "SharedAnimalRecord",
        publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        fieldName: "tagNumber"
      )
    ]

    let restored = await coordinator.restoreLocalFieldsFromConflict(
      selections,
      in: conflictReview,
      syncAfterResolution: false
    )

    XCTAssertTrue(restored)
    XCTAssertEqual(sharingRepository.restoreLocalFieldsCallCount, 1)
    XCTAssertEqual(coordinator.lastConflictReview, conflictReview)
    XCTAssertEqual(conflictReviewStore.reviewHistory.first, conflictReview)
    XCTAssertTrue(conflictReviewStore.resolutionHistory.isEmpty)
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  private func makeHerdSummary() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Test Herd",
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 1),
      schemaVersion: 1
    )
  }

  private func makeUpdatedRecordConflictReview() -> HerdSharingConflictReview {
    HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Test sync",
      detectedAt: Date(timeIntervalSince1970: 100),
      existingLocalRecordUpdateCount: 1,
      updatedRecordConflicts: [
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedModifiedAt: Date(timeIntervalSince1970: 30),
          fieldChanges: [
            HerdSharingUpdatedRecordFieldChange(
              fieldName: "tagNumber",
              localValueDescription: "12",
              sharedValueDescription: "14"
            )
          ]
        )
      ],
      preventedDeleteConflicts: []
    )
  }

  private func makeConflictReview() -> HerdSharingConflictReview {
    HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Test sync",
      detectedAt: Date(timeIntervalSince1970: 100),
      existingLocalRecordUpdateCount: 2,
      preventedDeleteConflicts: [
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedDeletedAt: Date(timeIntervalSince1970: 10)
        )
      ]
    )
  }
}

@MainActor
private final class StubHerdRepository: HerdRepository {
  private var herd: HerdSummary

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    herd
  }

  func replaceCurrentHerd(with herd: HerdSummary) {
    self.herd = herd
  }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    HerdSummary(
      publicID: herd.publicID,
      name: name,
      createdAt: herd.createdAt,
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: herd.schemaVersion
    )
  }
}

@MainActor
private final class RecordingHerdSharingRepository: HerdSharingRepository {
  private let access: HerdSharingAccess
  private let conflictReview: HerdSharingConflictReview?
  private var accessError: Error?
  private var shouldSuspendAccessLookups = false
  private var suspendedAccessCallNumber: Int?
  private(set) var accessCallCount = 0
  private(set) var accessLookupStarted = false
  private(set) var accessedHerdPublicIDs: [UUID] = []
  private(set) var syncCallCount = 0
  private(set) var acceptSharedDeleteCallCount = 0
  private(set) var restoreLocalFieldsCallCount = 0
  private(set) var syncedHerdPublicID: UUID?
  private(set) var acceptedSharedDeleteReview: HerdSharingConflictReview?
  private(set) var restoredLocalFieldSelections: [HerdSharingLocalFieldRestoreSelection] = []

  init(
    access: HerdSharingAccess = .localOwnerBridgePending,
    conflictReview: HerdSharingConflictReview? = nil
  ) {
    self.access = access
    self.conflictReview = conflictReview
  }

  func setAccessError(_ error: Error) {
    accessError = error
  }

  func suspendAccessLookups() {
    shouldSuspendAccessLookups = true
    suspendedAccessCallNumber = nil
  }

  func suspendAccessLookup(callNumber: Int) {
    shouldSuspendAccessLookups = true
    suspendedAccessCallNumber = callNumber
  }

  func resumeAccessLookups() {
    shouldSuspendAccessLookups = false
    suspendedAccessCallNumber = nil
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
    let accessCallNumber = accessCallCount
    if let herd { accessedHerdPublicIDs.append(herd.publicID) }
    accessLookupStarted = true
    while shouldSuspendAccessLookups,
          suspendedAccessCallNumber == nil || suspendedAccessCallNumber == accessCallNumber
    {
      await Task.yield()
    }
    if let accessError { throw accessError }
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
    acceptSharedDeleteCallCount += 1
    acceptedSharedDeleteReview = review
    return HerdSharingActionResult(
      title: "Shared deletes accepted",
      message: "Deleted shared records."
    )
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    restoreLocalFieldsCallCount += 1
    restoredLocalFieldSelections = selections
    return HerdSharingActionResult(
      title: "Local fields restored",
      message: "Restored selected fields."
    )
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    syncCallCount += 1
    syncedHerdPublicID = herd?.publicID
    return HerdSharingActionResult(
      title: "Synced",
      message: "Shared data synced.",
      conflictReview: conflictReview
    )
  }
}
