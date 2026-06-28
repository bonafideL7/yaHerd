import Foundation

protocol WorkingSessionListReader {
    func fetchSessions() throws -> [WorkingSessionSummary]
}

protocol WorkingSessionDetailReader {
    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot?
}

protocol WorkingProtocolTemplateListReader {
    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary]
}

protocol WorkingProtocolTemplateDetailReader {
    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot?
}

protocol WorkingQueueItemEditorReader {
    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot?
}

protocol WorkingSessionCreating {
    @discardableResult
    func createSession(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID
}

protocol WorkingAnimalCollecting {
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws
}

protocol WorkingQueueItemCompleting {
    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) throws
}

protocol WorkingQueueItemEditSaving {
    func saveEdits(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID, input: WorkingSessionAnimalEditInput) throws
}

protocol WorkingQueueItemDataDeleting {
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws
}

protocol WorkingSessionDeleting {
    func deleteSession(id: UUID) throws
}

protocol WorkingDestinationSaving {
    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws
}

protocol WorkingSessionFinishing {
    func finishSession(id: UUID) throws
}

protocol WorkingProtocolTemplateCreating {
    @discardableResult
    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID
}

protocol WorkingProtocolTemplateUpdating {
    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws
}

protocol WorkingProtocolTemplateDeleting {
    func deleteTemplates(ids: [UUID]) throws
}


protocol WorkingSessionsRepository: WorkingSessionListReader, WorkingSessionDeleting {}

protocol WorkingSessionDetailRepository: WorkingSessionDetailReader, WorkingSessionDeleting {}

protocol NewWorkingSessionRepository:
    WorkingProtocolTemplateListReader,
    WorkingProtocolTemplateDetailReader,
    WorkingSessionCreating
{}

protocol WorkingCollectAnimalsRepository:
    WorkingSessionDetailReader,
    WorkingAnimalCollecting
{}

protocol WorkingQueueRepository: WorkingSessionDetailReader {}

protocol WorkingQueueItemEditingRepository:
    WorkingQueueItemEditorReader,
    WorkingQueueItemEditSaving,
    WorkingQueueItemDataDeleting
{}

protocol WorkingChuteRepository:
    WorkingQueueItemEditorReader,
    WorkingQueueItemCompleting
{}

protocol WorkingFinishSessionRepository:
    WorkingSessionDetailReader,
    WorkingDestinationSaving,
    WorkingSessionFinishing
{}

protocol WorkingProtocolTemplatesRepository:
    WorkingProtocolTemplateListReader,
    WorkingProtocolTemplateDeleting
{}

protocol WorkingProtocolTemplateEditorRepository:
    WorkingProtocolTemplateDetailReader,
    WorkingProtocolTemplateUpdating
{}

protocol WorkingRepository:
    WorkingSessionsRepository,
    WorkingSessionDetailRepository,
    NewWorkingSessionRepository,
    WorkingCollectAnimalsRepository,
    WorkingQueueRepository,
    WorkingQueueItemEditingRepository,
    WorkingChuteRepository,
    WorkingFinishSessionRepository,
    WorkingProtocolTemplatesRepository,
    WorkingProtocolTemplateCreating,
    WorkingProtocolTemplateEditorRepository
{}
