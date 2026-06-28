import Foundation

protocol AnimalSummaryReading {
    func fetchAnimals() throws -> [AnimalSummary]
}

protocol AnimalDetailReading {
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot?
}

protocol AnimalTimelineReading {
    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent]
}

protocol AnimalStatusReferenceReading {
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption]
}

protocol AnimalParentOptionReading {
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption]
}

protocol AnimalOffspringDraftReading {
    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed?
}

protocol AnimalCreating {
    @discardableResult
    func create(input: AnimalInput) throws -> AnimalDetailSnapshot
}

protocol AnimalUpdating {
    @discardableResult
    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot
}

protocol AnimalDeleting {
    func delete(ids: [UUID]) throws
}

protocol AnimalArchiving {
    func archive(ids: [UUID]) throws
}

protocol AnimalRestoring {
    func restore(ids: [UUID]) throws
}

protocol AnimalPastureMoving {
    func move(ids: [UUID], toPastureID: UUID?) throws
}

protocol AnimalTagAdding {
    @discardableResult
    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot
}

protocol AnimalTagUpdating {
    @discardableResult
    func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot
}

protocol AnimalTagPromoting {
    @discardableResult
    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot
}

protocol AnimalTagRetiring {
    @discardableResult
    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot
}

protocol AnimalHealthRecordAdding {
    @discardableResult
    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot
}

protocol AnimalPregnancyCheckAdding {
    @discardableResult
    func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot
}

protocol AnimalListRepository:
    AnimalSummaryReading,
    AnimalDetailReading,
    AnimalCreating,
    AnimalUpdating,
    AnimalDeleting,
    AnimalArchiving,
    AnimalRestoring,
    AnimalPastureMoving
{}

protocol AnimalEditorRepository:
    AnimalStatusReferenceReading,
    AnimalCreating,
    AnimalTagAdding
{}

protocol AnimalDetailRepository:
    AnimalDetailReading,
    AnimalStatusReferenceReading,
    AnimalOffspringDraftReading,
    AnimalUpdating,
    AnimalDeleting,
    AnimalArchiving,
    AnimalRestoring,
    AnimalTagAdding,
    AnimalTagUpdating,
    AnimalTagPromoting,
    AnimalTagRetiring
{}

protocol AnimalRepository:
    AnimalListRepository,
    AnimalEditorRepository,
    AnimalDetailRepository,
    AnimalTimelineReading,
    AnimalParentOptionReading,
    AnimalHealthRecordAdding,
    AnimalPregnancyCheckAdding
{}

struct HealthRecordInput: Hashable {
    var date: Date
    var treatment: String
    var notes: String?
}

struct PregnancyCheckInput: Hashable {
    var date: Date
    var result: PregnancyResult
    var technician: String?
    var estimatedDaysPregnant: Int?
    var dueDate: Date?
    var sireAnimalID: UUID?
}
