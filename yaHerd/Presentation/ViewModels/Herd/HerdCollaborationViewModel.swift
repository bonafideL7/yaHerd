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
  var systemShare: HerdSystemShare?

  var canStartSharing: Bool {
    readiness?.shareActionEnabled == true && herd != nil && !isSharingActionInProgress
  }

  func load(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) {
    do {
      let loadedHerd = try LoadCurrentHerdUseCase(repository: herdRepository).execute()
      herd = loadedHerd
      draftName = loadedHerd.name
      readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
        herd: loadedHerd,
        storageMode: storageMode
      )
      sharingAccess = nil
      sharingAccessMessage = nil
      errorMessage = nil
    } catch {
      herd = nil
      sharingAccess = nil
      sharingAccessMessage = nil
      readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
        herd: nil,
        storageMode: storageMode
      )
      errorMessage = error.localizedDescription
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
      let access = try await LoadHerdSharingAccessUseCase(repository: sharingRepository).execute(
        herd: herd,
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
      sharingAccessMessage = error.localizedDescription
    }
  }

  func saveName(
    using repository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) {
    do {
      let renamedHerd = try RenameCurrentHerdUseCase(repository: repository).execute(
        name: draftName)
      herd = renamedHerd
      draftName = renamedHerd.name
      readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
        herd: renamedHerd,
        storageMode: storageMode
      )
      sharingAccess = nil
      sharingAccessMessage = nil
      successMessage = "Herd name saved."
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
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
      systemShare = result.systemShare
      successMessage = result.systemShare == nil ? "\(result.title): \(result.message)" : nil
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      successMessage = nil
      systemShare = nil
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
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
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
    defer { isSharingActionInProgress = false }

    do {
      let result = try await ImportSharedHerdDataUseCase(repository: sharingRepository).execute(
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
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
    defer { isSharingActionInProgress = false }

    do {
      let result = try await SyncSharedHerdDataUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      recordConflictReview(result.conflictReview, in: conflictReviewStore)
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      successMessage = nil
      return false
    }
  }

  func dismissSystemShare() {
    systemShare = nil
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
