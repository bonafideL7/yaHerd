import Foundation

@MainActor
protocol WorkingSessionListReader {
    func fetchSessions() throws -> [WorkingSessionSummary]
}

@MainActor
protocol WorkingSessionDetailReader {
    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot?
}

@MainActor
protocol WorkingProtocolTemplateListReader {
    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary]
}

@MainActor
protocol WorkingProtocolTemplateDetailReader {
    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot?
}

@MainActor
protocol WorkingQueueItemEditorReader {
    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot?
}

@MainActor
protocol WorkingSessionCreating {
    @discardableResult
    func createSession(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID
}

@MainActor
protocol WorkingAnimalCollecting {
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws
}

@MainActor
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

@MainActor
protocol WorkingQueueItemEditSaving {
    func saveEdits(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID, input: WorkingSessionAnimalEditInput) throws
}

@MainActor
protocol WorkingQueueItemDataDeleting {
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws
}

@MainActor
protocol WorkingSessionDeleting {
    func deleteSession(id: UUID) throws
}

@MainActor
protocol WorkingDestinationSaving {
    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws
}

@MainActor
protocol WorkingSessionFinishing {
    func finishSession(id: UUID) throws
}

@MainActor
protocol WorkingProtocolTemplateCreating {
    @discardableResult
    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID
}

@MainActor
protocol WorkingProtocolTemplateUpdating {
    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws
}

@MainActor
protocol WorkingProtocolTemplateDeleting {
    func deleteTemplates(ids: [UUID]) throws
}


@MainActor
protocol WorkingSessionsRepository: WorkingSessionListReader, WorkingSessionDeleting {}

@MainActor
protocol WorkingSessionDetailRepository: WorkingSessionDetailReader, WorkingSessionDeleting {}

@MainActor
protocol NewWorkingSessionRepository:
    WorkingProtocolTemplateListReader,
    WorkingProtocolTemplateDetailReader,
    WorkingSessionCreating
{}

@MainActor
protocol WorkingCollectAnimalsRepository:
    WorkingSessionDetailReader,
    WorkingAnimalCollecting
{}

@MainActor
protocol WorkingQueueRepository: WorkingSessionDetailReader {}

@MainActor
protocol WorkingQueueItemEditingRepository:
    WorkingQueueItemEditorReader,
    WorkingQueueItemEditSaving,
    WorkingQueueItemDataDeleting
{}

@MainActor
protocol WorkingChuteRepository:
    WorkingQueueItemEditorReader,
    WorkingQueueItemCompleting
{}

@MainActor
protocol WorkingFinishSessionRepository:
    WorkingSessionDetailReader,
    WorkingDestinationSaving,
    WorkingSessionFinishing
{}

@MainActor
protocol WorkingProtocolTemplatesRepository:
    WorkingProtocolTemplateListReader,
    WorkingProtocolTemplateDeleting
{}

@MainActor
protocol WorkingProtocolTemplateEditorRepository:
    WorkingProtocolTemplateDetailReader,
    WorkingProtocolTemplateUpdating
{}

@MainActor
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
