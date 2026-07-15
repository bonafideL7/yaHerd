//
//  RecoveryModeHerdSharingRepository.swift
//  yaHerd
//

@MainActor
final class RecoveryModeHerdSharingRepository: HerdSharingRepository {
  func fetchSharingReadiness(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) -> HerdSharingReadiness {
    .recoveryModeReadOnly
  }

  func fetchSharingAccess(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess {
    throw HerdSharingActionError.recoveryModeReadOnly
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.recoveryModeReadOnly
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.recoveryModeReadOnly
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.recoveryModeReadOnly
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.recoveryModeReadOnly
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.recoveryModeReadOnly
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.recoveryModeReadOnly
  }
}
