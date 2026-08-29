import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdCollaborationStorageModeTests: XCTestCase {
  func testLocalOnlyAccessRefreshLeavesWritePolicyWritableAndSkipsCloudKitRepository() async {
    let herd = makeHerd()
    let herdRepository = StorageModeHerdRepository(herd: herd)
    let sharingRepository = StorageModeSharingRepository(error: .iCloudSyncRequired)
    let writePolicy = HerdCollaborationWritePolicy()
    let viewModel = HerdCollaborationViewModel()
    viewModel.load(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .localOnly
    )

    XCTAssertTrue(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertFalse(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)

    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .localOnly,
      writePolicy: writePolicy
    )

    XCTAssertEqual(sharingRepository.fetchAccessCallCount, 0)
    XCTAssertNil(writePolicy.snapshot.access)
    XCTAssertFalse(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertTrue(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertNoThrow(try writePolicy.validateCanWrite(reason: .animal))
  }

  func testICloudAccessFailureStillInvalidatesPreviouslyWritablePolicy() async {
    let herd = makeHerd()
    let herdRepository = StorageModeHerdRepository(herd: herd)
    let sharingRepository = StorageModeSharingRepository(error: .iCloudSyncRequired)
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let viewModel = HerdCollaborationViewModel()
    viewModel.load(
      herdRepository: herdRepository,
      sharingRepository: sharingRepository,
      storageMode: .iCloud
    )

    await viewModel.refreshSharingAccess(
      using: sharingRepository,
      storageMode: .iCloud,
      writePolicy: writePolicy
    )

    XCTAssertEqual(sharingRepository.fetchAccessCallCount, 1)
    XCTAssertNil(writePolicy.snapshot.access)
    XCTAssertTrue(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(writePolicy.snapshot.allowsLocalMutations)
  }

  private func makeHerd() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Storage Mode Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }
}

@MainActor
private final class StorageModeHerdRepository: HerdRepository {
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
private final class StorageModeSharingRepository: HerdSharingRepository {
  private let error: HerdSharingActionError
  private(set) var fetchAccessCallCount = 0

  init(error: HerdSharingActionError) {
    self.error = error
  }

  func fetchSharingReadiness(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) -> HerdSharingReadiness {
    storageMode == .iCloud ? .sharingAdapterAvailable : .iCloudSyncRequired
  }

  func fetchSharingAccess(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess {
    fetchAccessCallCount += 1
    throw error
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw error
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw error
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw error
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw error
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw error
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw error
  }
}
