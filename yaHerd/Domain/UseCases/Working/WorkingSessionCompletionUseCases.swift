import Foundation

@MainActor
struct DeleteWorkingSessionUseCase {
    let repository: any WorkingSessionDeleting

    func execute(sessionID: UUID) throws {
        try repository.deleteSession(id: sessionID)
    }
}

@MainActor
struct SaveWorkingDestinationsUseCase {
    let repository: any WorkingDestinationSaving

    func execute(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {
        try repository.saveDestinations(sessionID: sessionID, assignments: assignments)
    }
}

@MainActor
struct FinishWorkingSessionUseCase {
    let repository: any WorkingSessionFinishing

    func execute(sessionID: UUID) throws {
        try repository.finishSession(id: sessionID)
    }
}
