//
//  HerdCollaborationViewModel.swift
//  yaHerd
//

import Foundation
import Observation

@MainActor
@Observable
final class HerdCollaborationViewModel {
  private var herdRepository: (any HerdRepository)?
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
      .pendingBridgeOperation, .ownershipConfirmationRequired, .ownerBridgeVerificationRequired,
      .ownerStopCleanupPending, .conflictingBridgeRecords, .notOwnedByCurrentDevice:
      return true
    case .unknown, nil:
      return false
    }
  }

  var primarySharingActionTitle: String {
    switch sharingAccess?.creationState {
    case .ready:
      "Share Herd"
    case .existingOwnerShare:
      "Manage Herd Sharing"
    case .acceptedParticipantShare:
      "Sync Shared Herd"
    case .unresolvedBridgeRecord:
      "Resume Herd Sharing"
    case .conflictingBridgeRecords:
      "Resolve Bridge Conflict"
    case .pendingBridgeOperation:
      "Resolve Sharing State"
    case .ownershipConfirmationRequired:
      "Confirm Local Ownership"
    case .ownerBridgeVerificationRequired:
      "Resolve Owner Sharing State"
    case .ownerStopCleanupPending:
      "Retry Stop Sharing Cleanup"
    case .notOwnedByCurrentDevice:
      "Detach Stale Shared Herd"
    case .unknown, nil:
      "Checking Sharing State"
    }
  }

  var primarySharingActionSystemImage: String {
    switch sharingAccess?.creationState {
    case .ready:
      "square.and.arrow.up"
    case .existingOwnerShare:
      "person.2.badge.gearshape"
    case .unresolvedBridgeRecord:
      "arrow.clockwise.icloud"
    case .acceptedParticipantShare, .pendingBridgeOperation:
      "arrow.triangle.2.circlepath.icloud"
    case .conflictingBridgeRecords:
      "exclamationmark.triangle"
    case .ownershipConfirmationRequired:
      "checkmark.shield"
    case .ownerBridgeVerificationRequired:
      "icloud.and.arrow.down"
    case .ownerStopCleanupPending:
      "arrow.clockwise.icloud"
    case .notOwnedByCurrentDevice:
      "person.crop.circle.badge.minus"
    case .unknown, nil:
      "hourglass"
    }
  }

  var primarySharingActionMessage: String {
    switch sharingAccess?.creationState {
    case .ready:
      "No existing share, participant bridge, unresolved bridge record, or pending bridge operation was found. This installation has confirmed local-owner authority and can create a new share."
    case .existingOwnerShare:
      "This herd already has an owner CloudKit share. Open sharing management instead of creating another share."
    case .acceptedParticipantShare:
      "This device participates in an accepted CloudKit share. Synchronize the shared herd instead of creating a second share."
    case .unresolvedBridgeRecord:
      "An interrupted sharing attempt left the owner bridge root without a CloudKit share. Resume that existing bridge instead of creating a second root."
    case .conflictingBridgeRecords:
      "The Herd root exists in both the owner private bridge store and an accepted shared store. Choose which CloudKit relationship to keep; the discarded relationship is stopped and a recovery import is required before export resumes."
    case .pendingBridgeOperation:
      "A previous bridge import, export, or reconciliation operation is unfinished. Recovery synchronization imports shared changes before any export or share management."
    case .ownershipConfirmationRequired:
      "This installation has no durable local-owner authorization for this Herd root. Confirm ownership deliberately before creating or resuming an owner share. This can apply to a fresh local Herd or to a stale participant copy only after that participation was explicitly detached; last-writer device metadata is not ownership proof."
    case .ownerBridgeVerificationRequired:
      "This restored Herd or iCloud account may already have owner-sharing history, but the owner bridge is not currently available. Refresh CloudKit access first. Reset the stale owner state only after confirming that no owner share remains on another device."
    case .ownerStopCleanupPending:
      "Stop Sharing finished in CloudKit, but yaHerd could not finish purging the local owner bridge. Local edits remain blocked across launches until you retry cleanup successfully."
    case .notOwnedByCurrentDevice:
      "This Herd is locally marked as an accepted participant copy, but its accepted bridge is no longer present. Detach the stale participant state only if the share was revoked, left, or permanently removed."
    case .unknown, nil:
      "Refresh sharing access before creating or managing a CloudKit share."
    }
  }

  func load(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) {
    do {
      self.herdRepository = herdRepository
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
    guard storageMode == .iCloud else {
      sharingAccess = nil
      sharingAccessMessage = "Enable iCloud Sync to inspect CloudKit share permissions."
      return
    }

    do {
      let requestedHerd = herd
      let access = try await sharingRepository.fetchSharingAccess(
        for: requestedHerd,
        storageMode: storageMode
      )
      if let requestedHerd, let herdRepository {
        let durableHerd = try herdRepository.fetchCurrentHerd()
        guard durableHerd.publicID == requestedHerd.publicID else {
          throw HerdSharingActionError.bridgeImportRequiresAccessVerification(
            "The current Herd changed while CloudKit sharing access was being verified. The stale access result was discarded."
          )
        }
      }
      sharingAccess = access
      writePolicy?.update(access: access)
      sharingAccessMessage = nil
    } catch HerdSharingActionError.iCloudSyncRequired {
      sharingAccess = nil
      writePolicy?.clearAccessAfterFailedSynchronization()
      sharingAccessMessage = "Enable iCloud Sync to inspect CloudKit share permissions."
    } catch HerdSharingActionError.shareRootMissing {
      sharingAccess = nil
      writePolicy?.clearAccessAfterFailedSynchronization()
      sharingAccessMessage = "No Herd share root is available yet."
    } catch {
      sharingAccess = nil
      // An authoritative access read can fail because the iCloud account or remote share changed.
      // Invalidate prior writable authority; requiring a successful refresh also preserves the
      // fail-closed behavior of previously read-only, conflicting, and recovery-blocked states.
      writePolicy?.clearAccessAfterFailedSynchronization()
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
    herdRepository: any HerdRepository,
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async {
    let completed: Bool
    switch sharingAccess?.creationState {
    case .ready:
      completed = await startSharing(
        using: sharingRepository,
        storageMode: storageMode,
        conflictReviewStore: conflictReviewStore
      )
    case .existingOwnerShare, .unresolvedBridgeRecord:
      completed = await manageExistingShare(
        using: sharingRepository,
        storageMode: storageMode,
        conflictReviewStore: conflictReviewStore
      )
    case .acceptedParticipantShare, .pendingBridgeOperation:
      completed = await syncSharedBridgeData(
        using: sharingRepository,
        storageMode: storageMode,
        conflictReviewStore: conflictReviewStore
      )
    case .conflictingBridgeRecords:
      errorMessage = "Choose which bridge relationship to keep in the confirmation dialog before continuing."
      successMessage = nil
      completed = false
    case .ownershipConfirmationRequired:
      errorMessage = HerdSharingActionError.ownershipConfirmationRequired.errorDescription
      successMessage = nil
      completed = false
    case .ownerBridgeVerificationRequired:
      errorMessage = HerdSharingActionError.ownerBridgeVerificationRequired.errorDescription
      successMessage = nil
      completed = false
    case .ownerStopCleanupPending:
      errorMessage = "Retry the failed Stop Sharing cleanup before making local changes."
      successMessage = nil
      completed = false
    case .notOwnedByCurrentDevice:
      errorMessage = HerdSharingActionError.herdOwnershipRequired.errorDescription
      successMessage = nil
      completed = false
    case .unknown, nil:
      errorMessage = HerdSharingActionError.sharingStateUnavailable.errorDescription
      successMessage = nil
      completed = false
    }

    // Invitation recovery can replace the single SwiftData Herd and its public ID. Reload before
    // any caller refreshes sharing access so a stale pre-import identity cannot publish authority
    // for the newly imported Herd. Applying this to every successful primary action also keeps the
    // primary button aligned with the dedicated invitation/import/sync controls.
    if completed {
      load(
        herdRepository: herdRepository,
        sharingRepository: sharingRepository,
        storageMode: storageMode
      )
    }
  }

  @discardableResult
  func startSharing(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async -> Bool {
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
      return true
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      sharePresentation = nil
      return false
    }
  }

  @discardableResult
  func manageExistingShare(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil
  ) async -> Bool {
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
      return true
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      sharePresentation = nil
      return false
    }
  }

  @discardableResult
  func confirmLocalHerdOwnership(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      guard let herd else {
        throw HerdSharingActionError.shareRootMissing
      }
      let result = try await sharingRepository.confirmLocalHerdOwnership(
        herd: herd,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      errorMessage = nil
      return true
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      return false
    }
  }

  @discardableResult
  func resetStaleOwnerSharingState(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      guard let herd else {
        throw HerdSharingActionError.shareRootMissing
      }
      let result = try await sharingRepository.resetStaleOwnerSharingState(
        herd: herd,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      errorMessage = nil
      return true
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      return false
    }
  }

  @discardableResult
  func detachStaleParticipantState(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      guard let herd else {
        throw HerdSharingActionError.shareRootMissing
      }
      let result = try await sharingRepository.detachStaleParticipantState(
        herd: herd,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      errorMessage = nil
      return true
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      return false
    }
  }

  @discardableResult
  func resolveBridgeConflict(
    keeping resolution: HerdSharingBridgeConflictResolution,
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      guard let herd else {
        throw HerdSharingActionError.shareRootMissing
      }
      let result = try await sharingRepository.resolveBridgeConflict(
        herd: herd,
        keeping: resolution,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      errorMessage = nil
      return true
    } catch {
      errorMessage = UserVisibleErrorMessage.make(error)
      successMessage = nil
      return false
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

  func clearConflictResolutionHistory(in conflictReviewStore: HerdSharingConflictReviewStore? = nil) {
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