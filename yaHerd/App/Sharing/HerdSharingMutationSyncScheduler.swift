//
//  HerdSharingMutationSyncScheduler.swift
//  yaHerd
//

import Foundation

/// Coalesces local mutation notifications before asking the sharing coordinator to synchronize.
///
/// The scheduler is main-actor isolated because every mutation originates from a repository backed
/// by the app's main `ModelContext`, and the destination coordinator is also main-actor isolated.
/// Keeping the entire state machine on one actor removes the previous lock and
/// unsafe sendability escape hatch.
@MainActor
final class HerdSharingMutationSyncScheduler {
  private let mutationDebounceNanoseconds: UInt64
  private weak var coordinator: HerdSharingSyncCoordinator?
  private var pendingReason: SharedDataMutationReason?
  private var pendingSyncTask: Task<Void, Never>?

  init(mutationDebounceNanoseconds: UInt64 = 1_500_000_000) {
    self.mutationDebounceNanoseconds = mutationDebounceNanoseconds
  }

  func attach(coordinator: HerdSharingSyncCoordinator) {
    self.coordinator = coordinator

    guard let pendingReason else { return }
    self.pendingReason = nil
    requestSharedDataSyncAfterMutation(reason: pendingReason)
  }

  func detach() {
    coordinator = nil
    pendingSyncTask?.cancel()
    pendingSyncTask = nil
  }

  func requestSharedDataSyncAfterMutation(reason: SharedDataMutationReason) {
    pendingReason = reason
    pendingSyncTask?.cancel()

    guard coordinator != nil else { return }

    let debounceNanoseconds = mutationDebounceNanoseconds
    pendingSyncTask = Task { @MainActor [weak self] in
      guard let self else { return }

      if debounceNanoseconds > 0 {
        do {
          try await Task.sleep(for: .nanoseconds(debounceNanoseconds))
        } catch {
          return
        }
      }

      flushPendingRequest()
    }
  }

  func cancelPendingSync() {
    pendingSyncTask?.cancel()
    pendingSyncTask = nil
    pendingReason = nil
  }

  private func flushPendingRequest() {
    guard let coordinator, let pendingReason else {
      pendingSyncTask = nil
      return
    }

    self.pendingReason = nil
    pendingSyncTask = nil
    PerformanceLog.event(
      "HerdSharingMutationSyncScheduler flushed coalesced mutation sync for \(pendingReason.displayName)"
    )
    coordinator.requestSharedDataSyncAfterMutation(reason: pendingReason)
  }
}
