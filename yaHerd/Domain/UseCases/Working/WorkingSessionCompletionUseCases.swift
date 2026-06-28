import Foundation

struct DeleteWorkingSessionUseCase {
    let repository: any WorkingSessionDeleting

    func execute(sessionID: UUID) throws {
        try repository.deleteSession(id: sessionID)
    }
}

struct SaveWorkingDestinationsUseCase {
    let repository: any WorkingDestinationSaving

    func execute(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {
        try repository.saveDestinations(sessionID: sessionID, assignments: assignments)
    }
}

struct FinishWorkingSessionUseCase {
    let repository: any WorkingSessionFinishing

    func execute(sessionID: UUID) throws {
        try repository.finishSession(id: sessionID)
    }
}
