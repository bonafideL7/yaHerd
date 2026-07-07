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

    try await Task.sleep(nanoseconds: 50_000_000)

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
    try await Task.sleep(nanoseconds: 20_000_000)
    coordinator.requestSharedDataSyncAfterMutation(reason: .animal)
    try await Task.sleep(nanoseconds: 20_000_000)

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
    let scheduler = HerdSharingMutationSyncScheduler()

    scheduler.attach(coordinator: coordinator)
    scheduler.requestSharedDataSyncAfterMutation(reason: .pasture)
    try await Task.sleep(nanoseconds: 20_000_000)

    XCTAssertEqual(sharingRepository.syncCallCount, 1)
    XCTAssertEqual(coordinator.lastTriggerDescription, "pasture change")
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

  func testResolveConflictByAcceptingSharedDeletesDeletesRecordsStoresResolutionAndRunsSync() async {
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

  private func makeHerdSummary() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Test Herd",
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 1),
      schemaVersion: 1
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
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: herd.schemaVersion
    )
  }
}

@MainActor
private final class RecordingHerdSharingRepository: HerdSharingRepository {
  private let access: HerdSharingAccess
  private let conflictReview: HerdSharingConflictReview?
  private(set) var accessCallCount = 0
  private(set) var syncCallCount = 0
  private(set) var acceptSharedDeleteCallCount = 0
  private(set) var syncedHerdPublicID: UUID?
  private(set) var acceptedSharedDeleteReview: HerdSharingConflictReview?

  init(
    access: HerdSharingAccess = .localOwnerBridgePending,
    conflictReview: HerdSharingConflictReview? = nil
  ) {
    self.access = access
    self.conflictReview = conflictReview
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

  func importSharedBridgeData(storageMode: HerdStorageMode) async throws -> HerdSharingActionResult
  {
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
