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

    var displayName: String {
      switch self {
      case .appLaunch:
        "app launch"
      case .appForeground:
        "app foreground"
      case .manual:
        "manual sync"
      }
    }
  }

  private let herdRepository: any HerdRepository
  private let sharingRepository: any HerdSharingRepository
  private let storageMode: HerdStorageMode
  private let automaticDebounceNanoseconds: UInt64
  private let minimumAutomaticSyncInterval: TimeInterval

  private var pendingAutomaticSyncTask: Task<Void, Never>?
  private var lastAutomaticSyncRequestedAt: Date?

  private(set) var isSyncing = false
  private(set) var lastTriggerDescription: String?
  private(set) var lastStartedAt: Date?
  private(set) var lastFinishedAt: Date?
  private(set) var lastSuccessMessage: String?
  private(set) var lastErrorMessage: String?
  private(set) var lastSkippedReason: String?

  init(
    herdRepository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode,
    automaticDebounceNanoseconds: UInt64 = 3_000_000_000,
    minimumAutomaticSyncInterval: TimeInterval = 60
  ) {
    self.herdRepository = herdRepository
    self.sharingRepository = sharingRepository
    self.storageMode = storageMode
    self.automaticDebounceNanoseconds = automaticDebounceNanoseconds
    self.minimumAutomaticSyncInterval = minimumAutomaticSyncInterval
  }

  func requestAutomaticSync(trigger: Trigger) {
    guard storageMode == .iCloud else {
      lastSkippedReason = "iCloud Sync is not enabled."
      return
    }

    guard !isSyncing else {
      lastSkippedReason = "A shared-data sync is already running."
      return
    }

    let now = Date.now
    if let lastAutomaticSyncRequestedAt,
      now.timeIntervalSince(lastAutomaticSyncRequestedAt) < minimumAutomaticSyncInterval
    {
      lastSkippedReason =
        "Skipped automatic shared-data sync because the previous automatic sync request was recent."
      return
    }

    lastAutomaticSyncRequestedAt = now
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

  func cancelPendingAutomaticSync() {
    pendingAutomaticSyncTask?.cancel()
    pendingAutomaticSyncTask = nil
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
    }

    do {
      let herd = try LoadCurrentHerdUseCase(repository: herdRepository).execute()
      let result = try await SyncSharedHerdDataUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      lastSuccessMessage = "\(result.title): \(result.message)"
      lastErrorMessage = nil
      return true
    } catch {
      lastErrorMessage = error.localizedDescription
      lastSuccessMessage = nil
      return false
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
