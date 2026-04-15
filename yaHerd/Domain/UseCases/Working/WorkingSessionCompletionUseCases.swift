import Foundation

struct DeleteWorkingSessionUseCase {
    let repository: any WorkingRepository

    func execute(sessionID: UUID) throws {
        try repository.deleteSession(id: sessionID)
    }
}

struct SaveWorkingDestinationsUseCase {
    let repository: any WorkingRepository

    func execute(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {
        try repository.saveDestinations(sessionID: sessionID, assignments: assignments)
    }
}

struct FinishWorkingSessionUseCase {
    let repository: any WorkingRepository

    func execute(sessionID: UUID) throws {
        try repository.finishSession(id: sessionID)
    }
}
