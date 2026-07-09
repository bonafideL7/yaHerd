//
//  HerdSharingMutationSyncScheduler.swift
//  yaHerd
//

import Foundation

final class HerdSharingMutationSyncScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private let mutationDebounceNanoseconds: UInt64
    private var syncRequestHandler: (@Sendable (SharedDataMutationReason) -> Void)?
    private var pendingReason: SharedDataMutationReason?
    private var pendingSyncTask: Task<Void, Never>?

    init(mutationDebounceNanoseconds: UInt64 = 1_500_000_000) {
        self.mutationDebounceNanoseconds = mutationDebounceNanoseconds
    }

    func attach(coordinator: HerdSharingSyncCoordinator) {
        let handler: @Sendable (SharedDataMutationReason) -> Void = { [weak coordinator] reason in
            Task { @MainActor in
                coordinator?.requestSharedDataSyncAfterMutation(reason: reason)
            }
        }

        let pending: SharedDataMutationReason?
        lock.lock()
        syncRequestHandler = handler
        pending = pendingReason
        pendingReason = nil
        lock.unlock()

        if let pending {
            requestSharedDataSyncAfterMutation(reason: pending)
        }
    }

    func requestSharedDataSyncAfterMutation(reason: SharedDataMutationReason) {
        let shouldSchedule: Bool

        lock.lock()
        pendingReason = reason
        pendingSyncTask?.cancel()
        shouldSchedule = syncRequestHandler != nil
        if shouldSchedule {
            pendingSyncTask = Task { [weak self, mutationDebounceNanoseconds] in
                if mutationDebounceNanoseconds > 0 {
                    do {
                        try await Task.sleep(nanoseconds: mutationDebounceNanoseconds)
                    } catch {
                        return
                    }
                }

                self?.flushPendingRequest()
            }
        }
        lock.unlock()
    }

    private func flushPendingRequest() {
        let handler: (@Sendable (SharedDataMutationReason) -> Void)?
        let reason: SharedDataMutationReason?

        lock.lock()
        handler = syncRequestHandler
        reason = pendingReason
        pendingReason = nil
        pendingSyncTask = nil
        lock.unlock()

        guard let handler, let reason else { return }
        PerformanceLog.event("HerdSharingMutationSyncScheduler flushed coalesced mutation sync for \(reason.displayName)")
        handler(reason)
    }
}
