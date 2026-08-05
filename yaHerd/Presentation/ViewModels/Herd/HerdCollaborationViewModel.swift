//
//  HerdCollaborationViewModel.swift
//  yaHerd
//

import Foundation
import Observation

@MainActor
@Observable
final class HerdCollaborationViewModel {
  private(set) var herd: HerdSummary?
  private(set) var readiness: HerdSharingReadiness?
  private(set) var sharingAccess: HerdSharingAccess?
  private(set) var sharingAccessMessage: String?
  private(set) var isSharingActionInProgress = false
  var draftName = ""
  var errorMessage: String?
  var successMessage: String?
  var latestConflictReview: HerdSharingConflictReview?
  var latestReconciliationReview: HerdSharingReconciliationReview?
  var sharePresentation: HerdSharePresentationRequest?

  var canStartSharing: Bool {
    readiness?.shareActionEnabled == true
      && herd != nil
      && sharingAccess?.creationState.allowsNewShare == true
      && !isSharingActionInProgress
  }

  var canPerformPrimarySharingAction: Bool {
    guard readiness?.shareActionEnabled == true, herd != nil, !isSharingActionInProgress else {
      return false
    }

    switch sharingAccess?.creationState {
    case .ready, .existingOwnerShare, .acceptedParticipantShare, .unresolvedBridgeRecord,
      .pendingBridgeOperation:
      return true
    case .unknown, .notOwnedByCurrentDevice, nil:
      return false
    }
  }

  var primarySharingActionTitle: String {
    sharingAccess?.creationState.primaryActionTitle ?? "Checking Sharing State"
  }

  var primarySharingActionSystemImage: String {
    sharingAccess?.creationState.primaryActionSystemImage ?? "hourglass"
  }

  var primarySharingActionMessage: String {
    sharingAccess?.creationState.message
      ?? "Refresh sharing access before creating or managing a CloudKit share."
  }

  func load(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) {
    do {
      let loadedHerd = try herdRepository.fetchCurrentHerd()
      herd = loadedHerd
      draftName = loadedHerd.name
      readiness = sharingRepository.fetchSharingReadiness(
        for: loadedHerd,
        storageMode: storageMode
      )
      sharingAccess = nil
      sharingAccessMessage = nil
      errorMessage = nil
    } catch {
      herd = nil
      sharingAccess = nil
      sharingAccessMessage = nil
      readiness = sharingRepository.fetchSharingReadiness(
        for: nil,
        storageMode: storageMode
      )
      errorMessage = UserVisibleErrorMessage.make(error)
    }
  }

  func loadLatestConflictReview(from conflictReviewStore: HerdSharingConflictReviewStore?) {
    latestConflictReview = conflictReviewStore?.latestReview
  }

  func refreshSharingAccess(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    writePolicy: HerdCollaborationWritePolicy? = nil
  ) async {
    do {
      let access = try await sharingRepository.fetchSharingAccess(
        for: herd,
        storageMode: storageMode
      )
      sharingAccess = access
      writePolicy?.update(access: access)
      sharingAccessMessage = nil
    } catch HerdSharingActionError.iCloudSyncRequired {
      sharingAccess = nil
      writePolicy?.clearAccess()
      sharingAccessMessage = "Enable iCloud Sync to inspect CloudKit share permissions."
    } catch HerdSharingActionError.shareRootMissing {
      sharingAccess = nil
      writePolicy?.clearAccess()
      sharingAccessMessage = "No Herd share root is available yet."
    } catch {
      sharingAccess = nil
      writePolicy?.clearAccess()
      sharingAccessMessage = UserVisibleErrorMessage.make(error)
    }
  }

  func saveName(
    using repository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) {
    do {
      let renamedHerd = try repository.renameCurrentHerd(to: draftName)
      herd = renamedHerd
      draftName = renamedHerd.name
      readiness = sharingRepository.fetchSharingReadiness(
        for: renamedHerd,
        storageMode: storageMode
      )
      sharingAccess = nil
      sharingAccessMessage = nil
      successMessage = "Herd name saved."
      errorMessage = nil
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
    }
  }

  func performPrimarySharingAction(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async {
    switch sharingAccess?.creationState {
    case .ready:
      await startSharing(
        using: sharingRepository,
        storageMode: storageMode,
        conflictReviewStore: conflictReviewStore
      )
    case .existingOwnerShare:
      await manageExistingShare(
        using: sharingRepository,
        storageMode: storageMode,
        conflictReviewStore: conflictReviewStore
      )
    case .acceptedParticipantShare, .unresolvedBridgeRecord, .pendingBridgeOperation:
      _ = await syncSharedBridgeData(
        using: sharingRepository,
        storageMode: storageMode,
        conflictReviewStore: conflictReviewStore
      )
    case .notOwnedByCurrentDevice:
      errorMessage = HerdSharingActionError.herdOwnershipRequired.errorDescription
      successMessage = nil
    case .unknown, nil:
      errorMessage = HerdSharingActionError.sharingStateUnavailable.errorDescription
      successMessage = nil
    }
  }

  func startSharing(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      let result = try await StartHerdSharingUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      sharePresentation = result.sharePresentation
      successMessage = result.sharePresentation == nil ? "\(result.title): \(result.message)" : nil
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      recordReconciliationReview(result.reconciliationReview)
      errorMessage = nil
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      sharePresentation = nil
    }
  }

  func manageExistingShare(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      guard let herd else {
        throw HerdSharingActionError.shareRootMissing
      }
      let result = try await sharingRepository.manageExistingShare(
        herd: herd,
        storageMode: storageMode
      )
      sharePresentation = result.sharePresentation
      successMessage = result.sharePresentation == nil ? "\(result.title): \(result.message)" : nil
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      recordReconciliationReview(result.reconciliationReview)
      errorMessage = nil
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      sharePresentation = nil
    }
  }

  @discardableResult
  func acceptPendingInvitation(
    _ invitation: HerdShareInvitation?,
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      let result = try await AcceptHerdShareInvitationUseCase(repository: sharingRepository)
        .execute(
          invitation: invitation,
          storageMode: storageMode
        )
      successMessage = "\(result.title): \(result.message)"
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      recordReconciliationReview(result.reconciliationReview)
      errorMessage = nil
      return true
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      return false
    }
  }

  @discardableResult
  func importSharedBridgeData(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async -> Bool {
    isSharingActionInProgress = true
    ReliabilityLog.syncEvent(
      "HerdCollaborationViewModel.importSharedBridgeData", detail: storageMode.displayName)
    defer { isSharingActionInProgress = false }

    do {
      let result = try await sharingRepository.importSharedBridgeData(
        herd: herd,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      recordReconciliationReview(result.reconciliationReview)
      errorMessage = nil
      return true
    } catch {
      ReliabilityLog.syncFailure("HerdCollaborationViewModel.importSharedBridgeData", error: error)
      errorMessage = UserVisibleErrorMessage.importFailed(error)
      successMessage = nil
      return false
    }
  }

  @discardableResult
  func syncSharedBridgeData(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async -> Bool {
    isSharingActionInProgress = true
    ReliabilityLog.syncEvent(
      "HerdCollaborationViewModel.syncSharedBridgeData", detail: storageMode.displayName)
    defer { isSharingActionInProgress = false }

    do {
      let result = try await SyncSharedHerdDataUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      recordReconciliationReview(result.reconciliationReview)
      errorMessage = nil
      return true
    } catch {
      ReliabilityLog.syncFailure("HerdCollaborationViewModel.syncSharedBridgeData", error: error)
      errorMessage = UserVisibleErrorMessage.syncFailed(error)
      successMessage = nil
      return false
    }
  }

  func dismissSharePresentation() {
    sharePresentation = nil
  }

  func resetDraftName() {
    draftName = herd?.name ?? ""
    errorMessage = nil
    successMessage = nil
  }

  func clearMessages() {
    errorMessage = nil
    successMessage = nil
  }

  func clearConflictReview(in conflictReviewStore: HerdSharingConflictReviewStore? = nil) {
    conflictReviewStore?.clearLatestReview()
    latestConflictReview = conflictReviewStore?.latestReview
  }

  func clearAllConflictReviews(in conflictReviewStore: HerdSharingConflictReviewStore? = nil) {
    conflictReviewStore?.clearAllReviews()
    latestConflictReview = nil
  }

  func resolveConflictByKeepingLocalRecords(
    _ review: HerdSharingConflictReview,
    in conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) {
    guard conflictReviewStore?.resolve(review, choice: .keepLocalRecords) != nil else {
      errorMessage = "No active conflict report was available to resolve."
      successMessage = nil
      return
    }

    latestConflictReview = conflictReviewStore?.latestReview
    successMessage =
      "Conflict report resolved by keeping local records. Run Sync Shared Data to re-export local records."
    errorMessage = nil
  }

  func resolveConflictByAcceptingSharedUpdates(
    _ review: HerdSharingConflictReview,
    in conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) {
    guard review.updatedRecordConflictCount > 0 || review.existingLocalRecordUpdateCount > 0 else {
      errorMessage = "This conflict report does not contain imported shared updates."
      successMessage = nil
      return
    }

    guard conflictReviewStore?.resolve(review, choice: .acceptSharedUpdates) != nil else {
      errorMessage = "No active conflict report was available to resolve."
      successMessage = nil
      return
    }

    latestConflictReview = conflictReviewStore?.latestReview
    successMessage =
      "Conflict report resolved by accepting shared updates. Imported shared values were kept in SwiftData."
    errorMessage = nil
  }

  func clearConflictResolutionHistory(in conflictReviewStore: HerdSharingConflictReviewStore? = nil)
  {
    conflictReviewStore?.clearResolutionHistory()
  }

  private func recordReconciliationReview(
    _ review: HerdSharingReconciliationReview?
  ) {
    guard let review else { return }
    latestReconciliationReview = review
  }

  private func recordConflictReview(
    _ review: HerdSharingConflictReview?,
    in conflictReviewStore: HerdSharingConflictReviewStore?
  ) {
    conflictReviewStore?.record(review)
    if let review, review.hasConflicts {
      latestConflictReview = review
    } else if latestConflictReview == nil {
      latestConflictReview = conflictReviewStore?.latestReview
    }
  }
}
