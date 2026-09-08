import Foundation

@MainActor
struct SwiftDataWorkingSessionCompletionPlan {
    struct Entry {
        let queueItem: WorkingQueueItem
        let destinationPasture: Pasture?
    }

    static func make(
        session: WorkingSession,
        destinationsByQueueItemID: [UUID: UUID?],
        resolvePasture: (UUID?) throws -> Pasture?
    ) throws -> [Entry] {
        try session.queueItems.map { item in
            guard let assignedPastureID = destinationsByQueueItemID[item.publicID] else {
                throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
            }

            let destination = try resolvePasture(assignedPastureID)
                ?? session.sourcePasture
            return Entry(
                queueItem: item,
                destinationPasture: destination
            )
        }
    }
}
