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

  private func makeHerdSummary() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Test Herd",
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 1),
      schemaVersion: 1
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
  private(set) var syncCallCount = 0
  private(set) var syncedHerdPublicID: UUID?

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

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    syncCallCount += 1
    syncedHerdPublicID = herd?.publicID
    return HerdSharingActionResult(title: "Synced", message: "Shared data synced.")
  }
}
