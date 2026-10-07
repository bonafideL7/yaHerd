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
    func startSession(input: WorkingSessionStartInput) async throws -> UUID
}

@MainActor
extension WorkingSessionStarting {
    @discardableResult
    func startSession(input: WorkingSessionStartInput) async throws -> UUID {
        throw WorkingRepositoryError.sessionStartUnavailable
    }
}

@MainActor
protocol WorkingAnimalCollecting {
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) async throws
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
    ) async throws
}

@MainActor
protocol WorkingQueueItemEditSaving {
    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) async throws
}

@MainActor
protocol WorkingSessionTreatmentUpdating {
    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) async throws
}

@MainActor
extension WorkingSessionTreatmentUpdating {
    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) async throws {
        throw WorkingRepositoryError.sessionTreatmentUpdateUnavailable
    }
}

@MainActor
protocol WorkingPrimaryTagReplacing {
    @discardableResult
    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) async throws -> WorkingQueueItemEditorSnapshot
}

@MainActor
extension WorkingPrimaryTagReplacing {
    @discardableResult
    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) async throws -> WorkingQueueItemEditorSnapshot {
        throw WorkingRepositoryError.tagReplacementUnavailable
    }
}

@MainActor
protocol WorkingQueueItemDataDeleting {
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) async throws
}

@MainActor
protocol WorkingSessionDeleting {
    func deleteSession(id: UUID) async throws
}

@MainActor
protocol WorkingSessionCompleting {
    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) async throws
}

@MainActor
protocol WorkingSessionReopening {
    func reopenSession(id: UUID) async throws
}

@MainActor
extension WorkingSessionReopening {
    func reopenSession(id: UUID) async throws {
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
    WorkingSessionReopening,
    WorkingSessionTreatmentUpdating
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
    WorkingSessionTreatmentUpdating,
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
