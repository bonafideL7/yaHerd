import Foundation

@MainActor
final class CoreDataWorkingAppRepository: WorkingRepository {
    private let working: CoreDataWorkingRepository
    private let templates: CoreDataWorkingTreatmentTemplateRepository

    init(
        working: CoreDataWorkingRepository,
        templates: CoreDataWorkingTreatmentTemplateRepository
    ) {
        self.working = working
        self.templates = templates
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            working: CoreDataWorkingRepository(
                selection: selection,
                assembly: assembly
            ),
            templates: CoreDataWorkingTreatmentTemplateRepository(
                selection: selection,
                assembly: assembly
            )
        )
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        try working.fetchSessions()
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        try working.fetchSessionDetail(id: id)
    }

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        try templates.fetchTemplates()
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        try templates.fetchTemplateDetail(id: id)
    }

    func fetchQueueItemEditor(
        sessionID: UUID,
        queueItemID: UUID
    ) throws -> WorkingQueueItemEditorSnapshot? {
        try working.fetchQueueItemEditor(
            sessionID: sessionID,
            queueItemID: queueItemID
        )
    }

    func startSession(input: WorkingSessionStartInput) async throws -> UUID {
        try await working.startSession(input: input)
    }

    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) async throws {
        try await working.collectAnimals(
            sessionID: sessionID,
            animalIDs: animalIDs
        )
    }

    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) async throws {
        try await working.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: treatmentEntries,
            pregnancyCheck: pregnancyCheck,
            markCastrated: markCastrated,
            observationNotes: observationNotes
        )
    }

    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) async throws {
        try await working.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: input
        )
    }

    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) async throws {
        try await working.updateSessionTreatments(
            id: id,
            plannedTreatments: plannedTreatments
        )
    }

    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) async throws -> WorkingQueueItemEditorSnapshot {
        try await working.replacePrimaryTag(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: input
        )
    }

    func deleteWorkData(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID
    ) async throws {
        try await working.deleteWorkData(
            forQueueItemID: queueItemID,
            inSessionID: sessionID
        )
    }

    func deleteSession(id: UUID) async throws {
        try await working.deleteSession(id: id)
    }

    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) async throws {
        try await working.completeSession(
            id: id,
            assignments: assignments
        )
    }

    func reopenSession(id: UUID) async throws {
        try await working.reopenSession(id: id)
    }

    func createTemplate(
        name: String,
        items: [WorkingTreatmentPlanItem]
    ) throws -> UUID {
        try templates.createTemplate(name: name, items: items)
    }

    func updateTemplate(
        id: UUID,
        name: String,
        items: [WorkingTreatmentPlanItem]
    ) throws {
        try templates.updateTemplate(id: id, name: name, items: items)
    }

    func deleteTemplates(ids: [UUID]) throws {
        try templates.deleteTemplates(ids: ids)
    }
}
