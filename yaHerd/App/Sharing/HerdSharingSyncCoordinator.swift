//
//  HerdSharingSyncCoordinator.swift
//  yaHerd
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class HerdSharingSyncCoordinator {
  enum Trigger: Equatable, Sendable {
    case appLaunch
    case appForeground
    case manual
    case screenOpened(String)
    case writePolicyPreflight(SharedDataMutationReason)
    case shareInvitationAccepted
    case dataMutation(SharedDataMutationReason)

    var displayName: String {
      switch self {
      case .appLaunch:
        "app launch"
      case .appForeground:
        "app foreground"
      case .manual:
        "manual sync"
      case .screenOpened(let screenName):
        "\(screenName) opened"
      case .writePolicyPreflight(let reason):
        "\(reason.displayName) edit preflight"
      case .shareInvitationAccepted:
        "share invitation accepted"
      case .dataMutation(let reason):
        "\(reason.displayName) change"
      }
    }

    var shouldThrottleAutomaticRequests: Bool {
      switch self {
      case .appLaunch, .appForeground, .screenOpened:
        true
      case .manual, .writePolicyPreflight, .shareInvitationAccepted, .dataMutation:
        false
      }
    }
  }

  private let herdRepository: any HerdRepository
  private let sharingRepository: any HerdSharingRepository
  private let storageMode: HerdStorageMode
  private let writePolicy: HerdCollaborationWritePolicy?
  private let conflictReviewStore: HerdSharingConflictReviewStore?
  private let automaticDebounceNanoseconds: UInt64
  private let minimumAutomaticSyncInterval: TimeInterval

  private var pendingAutomaticSyncTask: Task<Void, Never>?
  private var lastAutomaticSyncRequestedAt: Date?
  private var lastAccessRefreshRequestedAt: Date?
  private var queuedMutationReason: SharedDataMutationReason?

  private(set) var isRefreshingSharingAccess = false
  private(set) var isSyncing = false
  private(set) var lastTriggerDescription: String?
  private(set) var lastStartedAt: Date?
  private(set) var lastFinishedAt: Date?
  private(set) var lastSuccessMessage: String?
  private(set) var lastConflictReview: HerdSharingConflictReview?
  private(set) var lastErrorMessage: String?
  private(set) var lastSkippedReason: String?
  private(set) var lastAccessRefreshTriggerDescription: String?
  private(set) var lastAccessRefreshStartedAt: Date?
  private(set) var lastAccessRefreshFinishedAt: Date?
  private(set) var lastAccessRefreshErrorMessage: String?
  private(set) var lastAccessRefreshSkippedReason: String?

  init(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    writePolicy: HerdCollaborationWritePolicy? = nil,
    conflictReviewStore: HerdSharingConflictReviewStore? = nil,
    automaticDebounceNanoseconds: UInt64 = 3_000_000_000,
    minimumAutomaticSyncInterval: TimeInterval = 60
  ) {
    self.herdRepository = herdRepository
    self.sharingRepository = sharingRepository
    self.storageMode = storageMode
    self.writePolicy = writePolicy
    self.conflictReviewStore = conflictReviewStore
    self.automaticDebounceNanoseconds = automaticDebounceNanoseconds
    self.minimumAutomaticSyncInterval = minimumAutomaticSyncInterval
    self.lastConflictReview = conflictReviewStore?.latestReview
  }

  func requestAutomaticSync(trigger: Trigger) {
    guard storageMode == .iCloud else {
      lastSkippedReason = "iCloud Sync is not enabled."
      return
    }

    guard !isSyncing else {
      if case .dataMutation(let reason) = trigger {
        queuedMutationReason = reason
        lastSkippedReason = "Queued shared-data sync after the current sync finishes."
      } else {
        lastSkippedReason = "A shared-data sync is already running."
      }
      return
    }

    let now = Date.now
    if trigger.shouldThrottleAutomaticRequests,
      let lastAutomaticSyncRequestedAt,
      now.timeIntervalSince(lastAutomaticSyncRequestedAt) < minimumAutomaticSyncInterval
    {
      lastSkippedReason =
        "Skipped automatic shared-data sync because the previous automatic sync request was recent."
      return
    }

    if trigger.shouldThrottleAutomaticRequests {
      lastAutomaticSyncRequestedAt = now
    }
    lastSkippedReason = nil
    pendingAutomaticSyncTask?.cancel()

    let debounceNanoseconds = automaticDebounceNanoseconds
    pendingAutomaticSyncTask = Task { @MainActor [weak self, debounceNanoseconds] in
      if debounceNanoseconds > 0 {
        do {
          try await Task.sleep(nanoseconds: debounceNanoseconds)
        } catch {
          return
        }
      }

      await self?.runScheduledAutomaticSync(trigger: trigger)
    }
  }

  func requestSharedDataSyncAfterMutation(reason: SharedDataMutationReason) {
    requestAutomaticSync(trigger: .dataMutation(reason))
  }

  func requestSharingAccessRefreshForMutationPreflight(reason: SharedDataMutationReason) {
    Task { @MainActor [weak self] in
      await self?.refreshSharingAccessNow(trigger: .writePolicyPreflight(reason))
    }
  }

  @discardableResult
  func refreshSharingAccessNow(trigger: Trigger, minimumInterval: TimeInterval = 5) async -> Bool {
    guard storageMode == .iCloud else {
      lastAccessRefreshSkippedReason = "iCloud Sync is not enabled."
      return false
    }

    guard !isRefreshingSharingAccess else {
      lastAccessRefreshSkippedReason = "A sharing-access refresh is already running."
      return false
    }

    let now = Date.now
    if trigger.shouldThrottleAutomaticRequests,
      let lastAccessRefreshRequestedAt,
      now.timeIntervalSince(lastAccessRefreshRequestedAt) < minimumInterval
    {
      lastAccessRefreshSkippedReason =
        "Skipped sharing-access refresh because the previous access refresh was recent."
      return false
    }

    lastAccessRefreshRequestedAt = now
    isRefreshingSharingAccess = true
    lastAccessRefreshTriggerDescription = trigger.displayName
    lastAccessRefreshStartedAt = now
    lastAccessRefreshSkippedReason = nil
    defer {
      isRefreshingSharingAccess = false
      lastAccessRefreshFinishedAt = .now
    }

    do {
      let herd = try LoadCurrentHerdUseCase(repository: herdRepository).execute()
      let access = try await LoadHerdSharingAccessUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      writePolicy?.update(access: access)
      lastAccessRefreshErrorMessage = nil
      return true
    } catch HerdSharingActionError.iCloudSyncRequired {
      writePolicy?.clearAccess()
      lastAccessRefreshErrorMessage = "Enable iCloud Sync to inspect CloudKit share permissions."
      return false
    } catch HerdSharingActionError.shareRootMissing {
      writePolicy?.clearAccess()
      lastAccessRefreshErrorMessage = "No Herd share root is available yet."
      return false
    } catch {
      lastAccessRefreshErrorMessage = error.localizedDescription
      return false
    }
  }

  func cancelPendingAutomaticSync() {
    pendingAutomaticSyncTask?.cancel()
    pendingAutomaticSyncTask = nil
  }

  func clearConflictReview() {
    conflictReviewStore?.clearLatestReview()
    lastConflictReview = conflictReviewStore?.latestReview
  }

  func clearAllConflictReviews() {
    conflictReviewStore?.clearAllReviews()
    lastConflictReview = conflictReviewStore?.latestReview
  }

  @discardableResult
  func resolveConflictByKeepingLocalRecords(
    _ review: HerdSharingConflictReview,
    syncAfterResolution: Bool
  ) async -> Bool {
    guard conflictReviewStore?.resolve(review, choice: .keepLocalRecords) != nil else {
      lastSkippedReason = "No active conflict report was available to resolve."
      return false
    }

    lastConflictReview = conflictReviewStore?.latestReview

    guard syncAfterResolution else { return true }

    _ = await syncNow(trigger: .manual)
    return true
  }

  @discardableResult
  func resolveConflictByAcceptingSharedUpdates(
    _ review: HerdSharingConflictReview,
    syncAfterResolution: Bool
  ) async -> Bool {
    guard review.updatedRecordConflictCount > 0 || review.existingLocalRecordUpdateCount > 0 else {
      lastSkippedReason = "This conflict report does not contain imported shared updates."
      return false
    }

    guard conflictReviewStore?.resolve(review, choice: .acceptSharedUpdates) != nil else {
      lastSkippedReason = "No active conflict report was available to resolve."
      return false
    }

    lastConflictReview = conflictReviewStore?.latestReview
    lastSuccessMessage = "Shared updates accepted: imported shared values were kept in SwiftData."
    lastErrorMessage = nil
    lastSkippedReason = nil

    guard syncAfterResolution else { return true }

    _ = await syncNow(trigger: .manual)
    return true
  }

  @discardableResult
  func resolveConflictByAcceptingSharedDeletes(
    _ review: HerdSharingConflictReview,
    syncAfterResolution: Bool
  ) async -> Bool {
    guard review.preventedDeleteCount > 0 else {
      lastSkippedReason = "This conflict report does not contain skipped shared deletes."
      return false
    }

    do {
      let result = try await AcceptPreventedSharedDeletesUseCase(repository: sharingRepository)
        .execute(
          review: review,
          storageMode: storageMode
        )
      lastSuccessMessage = "\(result.title): \(result.message)"
      lastErrorMessage = nil
      lastSkippedReason = nil
      _ = conflictReviewStore?.resolve(review, choice: .acceptSharedDeletes)
      lastConflictReview = conflictReviewStore?.latestReview

      guard syncAfterResolution else { return true }

      _ = await syncNow(trigger: .manual)
      return true
    } catch {
      lastErrorMessage = error.localizedDescription
      lastSuccessMessage = nil
      return false
    }
  }

  @discardableResult
  func restoreLocalFieldsFromConflict(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    syncAfterResolution: Bool,
    resolveAfterRestore: Bool = false
  ) async -> Bool {
    guard !selections.isEmpty else {
      lastSkippedReason = "Select one or more local field values to restore."
      return false
    }

    do {
      let result = try await RestoreLocalConflictFieldsUseCase(repository: sharingRepository)
        .execute(
          selections: selections,
          review: review,
          storageMode: storageMode
        )
      lastSuccessMessage = "\(result.title): \(result.message)"
      lastErrorMessage = nil
      lastSkippedReason = nil

      if resolveAfterRestore {
        guard conflictReviewStore?.resolve(review, choice: .restoreLocalFields) != nil else {
          lastSkippedReason =
            "Local fields were restored, but no active conflict report was available to resolve."
          return false
        }
        lastConflictReview = conflictReviewStore?.latestReview
      }

      guard syncAfterResolution else { return true }

      _ = await syncNow(trigger: .manual)
      return true
    } catch {
      lastErrorMessage = error.localizedDescription
      lastSuccessMessage = nil
      return false
    }
  }

  @discardableResult
  func syncNow(trigger: Trigger) async -> Bool {
    cancelPendingAutomaticSync()
    return await performSync(trigger: trigger)
  }

  @discardableResult
  private func runScheduledAutomaticSync(trigger: Trigger) async -> Bool {
    pendingAutomaticSyncTask = nil
    return await performSync(trigger: trigger)
  }

  @discardableResult
  private func performSync(trigger: Trigger) async -> Bool {
    guard storageMode == .iCloud else {
      lastSkippedReason = "iCloud Sync is not enabled."
      return false
    }

    guard !isSyncing else {
      lastSkippedReason = "A shared-data sync is already running."
      return false
    }

    isSyncing = true
    lastTriggerDescription = trigger.displayName
    lastStartedAt = .now
    lastSkippedReason = nil
    defer {
      isSyncing = false
      lastFinishedAt = .now
      if let queuedMutationReason {
        self.queuedMutationReason = nil
        requestAutomaticSync(trigger: .dataMutation(queuedMutationReason))
      }
    }

    do {
      let herd = try LoadCurrentHerdUseCase(repository: herdRepository).execute()
      let access = try await LoadHerdSharingAccessUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      writePolicy?.update(access: access)
      let result = try await SyncSharedHerdDataUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      lastSuccessMessage = "\(result.title): \(result.message)"
      recordConflictReview(result.conflictReview)
      lastErrorMessage = nil
      return true
    } catch {
      lastErrorMessage = error.localizedDescription
      lastSuccessMessage = nil
      return false
    }
  }

  private func recordConflictReview(_ review: HerdSharingConflictReview?) {
    conflictReviewStore?.record(review)
    if let review, review.hasConflicts {
      lastConflictReview = review
    } else if lastConflictReview == nil {
      lastConflictReview = conflictReviewStore?.latestReview
    }
  }
}

private struct HerdSharingSyncCoordinatorKey: EnvironmentKey {
  static let defaultValue: HerdSharingSyncCoordinator? = nil
}

extension EnvironmentValues {
  var herdSharingSyncCoordinator: HerdSharingSyncCoordinator? {
    get { self[HerdSharingSyncCoordinatorKey.self] }
    set { self[HerdSharingSyncCoordinatorKey.self] = newValue }
  }
}
