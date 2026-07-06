//
//  HerdSharingMutationSyncScheduler.swift
//  yaHerd
//

import Foundation

final class HerdSharingMutationSyncScheduler {
    private let lock = NSLock()
    private var syncRequestHandler: ((SharedDataMutationReason) -> Void)?
    private var pendingReason: SharedDataMutationReason?

    func attach(coordinator: HerdSharingSyncCoordinator) {
        let handler: (SharedDataMutationReason) -> Void = { [weak coordinator] reason in
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
            handler(pending)
        }
    }

    func requestSharedDataSyncAfterMutation(reason: SharedDataMutationReason) {
        lock.lock()
        if let syncRequestHandler {
            lock.unlock()
            syncRequestHandler(reason)
        } else {
            pendingReason = reason
            lock.unlock()
        }
    }
}
