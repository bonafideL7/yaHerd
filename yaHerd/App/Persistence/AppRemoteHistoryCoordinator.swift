import Foundation

/// Owned by the app runtime, not a scene or feature. It provides the single
/// acknowledgement boundary between persistent history and the mutation stream.
@MainActor
final class AppRemoteHistoryCoordinator {
    private let wakeups: CoreDataHistoryWakeups
    private let task: Task<Void, Never>

    init(
        contextFactory: CoreDataContextFactory,
        wakeups: CoreDataHistoryWakeups,
        mutationCenter: ApplicationMutationCenter,
        herdDirectory: HerdDirectoryController
    ) {
        self.wakeups = wakeups
        let consumer = CoreDataPersistentHistoryConsumer(contextFactory: contextFactory)
        task = Task {
            await consumer.run(wakeups: wakeups) { changes in
                guard !contextFactory.herdImportState.blocksHerdAccess else { return false }
                // Resolve access first; feature reloads must see the new selection.
                herdDirectory.refresh(reportErrors: false)
                guard !contextFactory.herdImportState.blocksHerdAccess else { return false }
                mutationCenter.recordRemoteChanges(
                    storeID: changes.storeID,
                    changedEntities: changes.entityNames,
                    requiresFullRefresh: changes.requiresFullRefresh
                )
                return true
            }
        }
        // Catch commits made before the consumer was created or during downtime.
        wakeups.requestProcessing()
    }

    deinit { task.cancel() }

    func requestProcessing() { wakeups.requestProcessing() }
}
