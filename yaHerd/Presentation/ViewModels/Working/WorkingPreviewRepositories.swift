import Foundation

private enum PreviewRepositoryError: LocalizedError {
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation):
            return "Preview repository does not support \(operation)."
        }
    }
}

struct EmptyWorkingRepository: WorkingRepository {
    func fetchSessions() throws -> [WorkingSessionSummary] { [] }
    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? { nil }
    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] { [] }
    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot? { nil }
    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot? { nil }
    func createSession(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID { UUID() }
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {}
    func complete(queueItemID: UUID, inSessionID sessionID: UUID, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws {}
    func saveEdits(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID, input: WorkingSessionAnimalEditInput) throws {}
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {}
    func deleteSession(id: UUID) throws {}
    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {}
    func finishSession(id: UUID) throws {}
    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID { UUID() }
    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws {}
    func deleteTemplates(ids: [UUID]) throws {}
}


struct EmptyPastureRepository: PastureRepository {
    func fetchPastures() throws -> [PastureSummary] { [] }
    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? { nil }
    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] { [] }
    func fetchPastureOptions() throws -> [PastureOption] { [] }
    func validatePastureIDsExist(_ ids: [UUID]) throws {}
    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool { false }
    func groupNameExists(_ name: String) throws -> Bool { false }
    func create(input: PastureInput) throws -> PastureDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("creating pastures") }
    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("updating pastures") }
    func reorder(ids: [UUID]) throws {}
    func delete(ids: [UUID]) throws {}
    func createGroup(input: PastureGroupInput) throws {}
}

struct EmptyAnimalRepository: AnimalRepository {
    func fetchAnimals() throws -> [AnimalSummary] { [] }
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? { nil }
    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] { [] }
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] { [] }
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] { [] }
    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? { nil }
    func create(input: AnimalInput) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("creating animals") }
    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("updating animals") }
    func delete(ids: [UUID]) throws {}
    func archive(ids: [UUID]) throws {}
    func restore(ids: [UUID]) throws {}
    func move(ids: [UUID], toPastureID: UUID?) throws {}
    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("adding tags") }
    func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("updating tags") }
    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("promoting tags") }
    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("retiring tags") }
    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("adding health records") }
    func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot { throw PreviewRepositoryError.unsupportedOperation("adding pregnancy checks") }
}
