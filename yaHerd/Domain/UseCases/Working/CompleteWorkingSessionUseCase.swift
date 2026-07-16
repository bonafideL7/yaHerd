import Foundation

@MainActor
struct CompleteWorkingSessionUseCase {
    let repository: any WorkingFinishSessionRepository

    func execute(
        sessionID: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) throws {
        guard let session = try repository.fetchSessionDetail(id: sessionID) else {
            throw WorkingRepositoryError.sessionNotFound
        }
        guard session.status != .finished else {
            throw WorkingRepositoryError.sessionAlreadyFinished
        }

        let assignmentIDs = assignments.map(\.queueItemID)
        guard Set(assignmentIDs).count == assignmentIDs.count else {
            throw WorkingRepositoryError.duplicateQueueItemAssignments
        }

        let sessionQueueItemIDs = Set(session.queueItems.map(\.id))
        guard Set(assignmentIDs) == sessionQueueItemIDs else {
            throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
        }

        try repository.completeSession(id: sessionID, assignments: assignments)
    }
}
