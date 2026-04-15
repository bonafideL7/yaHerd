import Foundation

struct CompleteWorkingQueueItemUseCase {
    let repository: any WorkingRepository

    func execute(queueItemID: UUID, sessionID: UUID, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws {
        try repository.complete(queueItemID: queueItemID, inSessionID: sessionID, treatmentEntries: treatmentEntries, pregnancyCheck: pregnancyCheck, markCastrated: markCastrated, observationNotes: observationNotes)
    }
}

struct SaveWorkingQueueItemEditsUseCase {
    let repository: any WorkingRepository

    func execute(queueItemID: UUID, sessionID: UUID, input: WorkingSessionAnimalEditInput) throws {
        try repository.saveEdits(forQueueItemID: queueItemID, inSessionID: sessionID, input: input)
    }
}

struct DeleteWorkingQueueItemDataUseCase {
    let repository: any WorkingRepository

    func execute(queueItemID: UUID, sessionID: UUID) throws {
        try repository.deleteWorkData(forQueueItemID: queueItemID, inSessionID: sessionID)
    }
}
