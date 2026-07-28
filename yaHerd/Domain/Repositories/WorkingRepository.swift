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
protocol WorkingTreatmentTemplateListReader {
    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary]
}

@MainActor
protocol WorkingTreatmentTemplateDetailReader {
    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot?
}

@MainActor
protocol WorkingQueueItemEditorReader {
    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot?
}

@MainActor
protocol WorkingSessionStarting {
    @discardableResult
    func startSession(input: WorkingSessionStartInput) throws -> UUID
}

@MainActor
extension WorkingSessionStarting {
    @discardableResult
    func startSession(input: WorkingSessionStartInput) throws -> UUID {
        throw WorkingRepositoryError.sessionStartUnavailable
    }
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
    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) throws
}

@MainActor
protocol WorkingPrimaryTagReplacing {
    @discardableResult
    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) throws -> WorkingQueueItemEditorSnapshot
}

@MainActor
extension WorkingPrimaryTagReplacing {
    @discardableResult
    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) throws -> WorkingQueueItemEditorSnapshot {
        throw WorkingRepositoryError.tagReplacementUnavailable
    }
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
protocol WorkingSessionCompleting {
    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) throws
}

@MainActor
protocol WorkingSessionReopening {
    func reopenSession(id: UUID) throws
}

@MainActor
extension WorkingSessionReopening {
    func reopenSession(id: UUID) throws {
        throw WorkingRepositoryError.sessionReopenUnavailable
    }
}

@MainActor
protocol WorkingTreatmentTemplateCreating {
    @discardableResult
    func createTemplate(name: String, items: [WorkingTreatmentPlanItem]) throws -> UUID
}

@MainActor
protocol WorkingTreatmentTemplateUpdating {
    func updateTemplate(id: UUID, name: String, items: [WorkingTreatmentPlanItem]) throws
}

@MainActor
protocol WorkingTreatmentTemplateDeleting {
    func deleteTemplates(ids: [UUID]) throws
}

@MainActor
protocol WorkingSessionsRepository: WorkingSessionListReader, WorkingSessionDeleting {}

@MainActor
protocol WorkingSessionDetailRepository:
    WorkingSessionDetailReader,
    WorkingSessionDeleting,
    WorkingSessionReopening
{}

@MainActor
protocol NewWorkingSessionRepository:
    WorkingTreatmentTemplateListReader,
    WorkingTreatmentTemplateDetailReader,
    WorkingSessionStarting
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
    WorkingPrimaryTagReplacing,
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
    WorkingSessionCompleting
{}

@MainActor
protocol WorkingTreatmentTemplatesRepository:
    WorkingTreatmentTemplateListReader,
    WorkingTreatmentTemplateDeleting
{}

@MainActor
protocol WorkingTreatmentTemplateEditorRepository:
    WorkingTreatmentTemplateDetailReader,
    WorkingTreatmentTemplateUpdating
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
    WorkingTreatmentTemplatesRepository,
    WorkingTreatmentTemplateCreating,
    WorkingTreatmentTemplateEditorRepository
{}
