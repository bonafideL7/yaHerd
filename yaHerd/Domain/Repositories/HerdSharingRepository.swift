//
//  HerdSharingRepository.swift
//  yaHerd
//

@MainActor
protocol HerdSharingRepository: AnyObject {
  func fetchSharingReadiness(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) -> HerdSharingReadiness

  func fetchSharingAccess(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func manageExistingShare(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func confirmLocalHerdOwnership(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func detachStaleParticipantState(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func resolveBridgeConflict(
    herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult
}

extension HerdSharingRepository {
  func manageExistingShare(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.shareManagementUnavailable
  }

  func confirmLocalHerdOwnership(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.ownershipConfirmationRequired
  }

  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.ownerBridgeVerificationRequired
  }

  func detachStaleParticipantState(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.herdOwnershipRequired
  }

  func resolveBridgeConflict(
    herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.unresolvedSharingBridge
  }
}
