import Foundation

struct CreateWorkingSessionUseCase {
    let repository: any WorkingRepository
    func execute(date: Date, sourcePasture: Pasture?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> WorkingSession {
        try repository.createSession(date: date, sourcePasture: sourcePasture, protocolName: protocolName, protocolItems: protocolItems)
    }
}

struct CollectWorkingAnimalsUseCase {
    let repository: any WorkingRepository
    func execute(session: WorkingSession, animals: [Animal]) throws {
        try repository.collectAnimals(session: session, animals: animals)
    }
}

struct CompleteWorkingQueueItemUseCase {
    let repository: any WorkingRepository
    func execute(queueItem: WorkingQueueItem, session: WorkingSession, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws {
        try repository.complete(queueItem: queueItem, in: session, treatmentEntries: treatmentEntries, pregnancyCheck: pregnancyCheck, markCastrated: markCastrated, observationNotes: observationNotes)
    }
}

struct SaveWorkingQueueItemEditsUseCase {
    let repository: any WorkingRepository
    func execute(queueItem: WorkingQueueItem, session: WorkingSession, input: WorkingSessionAnimalEditInput) throws {
        try repository.saveEdits(for: queueItem, in: session, input: input)
    }
}

struct DeleteWorkingQueueItemDataUseCase {
    let repository: any WorkingRepository
    func execute(queueItem: WorkingQueueItem, session: WorkingSession) throws {
        try repository.deleteWorkData(for: queueItem, in: session)
    }
}

struct DeleteWorkingSessionUseCase {
    let repository: any WorkingRepository
    func execute(session: WorkingSession) throws {
        try repository.deleteSession(session)
    }
}

struct FinishWorkingSessionUseCase {
    let repository: any WorkingRepository
    func execute(session: WorkingSession) throws {
        try repository.finishSession(session)
    }
}

struct CreateWorkingProtocolTemplateUseCase {
    let repository: any WorkingRepository
    func execute(name: String, items: [WorkingProtocolItem]) throws -> WorkingProtocolTemplate {
        try repository.createTemplate(name: name, items: items)
    }
}

struct UpdateWorkingProtocolTemplateUseCase {
    let repository: any WorkingRepository
    func execute(template: WorkingProtocolTemplate, name: String, items: [WorkingProtocolItem]) throws {
        try repository.updateTemplate(template, name: name, items: items)
    }
}

struct DeleteWorkingProtocolTemplatesUseCase {
    let repository: any WorkingRepository
    func execute(_ templates: [WorkingProtocolTemplate]) throws {
        try repository.deleteTemplates(templates)
    }
}
