import Foundation

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

struct EmptyAnimalRepository: AnimalRepository {
    func fetchAnimals() throws -> [AnimalSummary] { [] }
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? { nil }
    func fetchPastureOptions() throws -> [PastureOption] { [] }
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] { [] }
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] { [] }
    func create(input: AnimalInput) throws -> AnimalDetailSnapshot { fatalError() }
    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot { fatalError() }
    func delete(ids: [UUID]) throws {}
    func archive(ids: [UUID]) throws {}
    func restore(ids: [UUID]) throws {}
    func move(ids: [UUID], toPastureID: UUID?) throws {}
    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot { fatalError() }
    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { fatalError() }
    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot { fatalError() }
    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot { fatalError() }
    func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot { fatalError() }
}
