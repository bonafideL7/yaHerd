import Foundation

@MainActor
protocol AnimalSummaryReading {
    func fetchAnimals() throws -> [AnimalSummary]
}

@MainActor
protocol AnimalDetailReading {
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot?
}

@MainActor
protocol AnimalTimelineReading {
    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent]
}

@MainActor
protocol AnimalStatusReferenceReading {
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption]
}

@MainActor
protocol AnimalParentOptionReading {
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption]
}

@MainActor
protocol AnimalOffspringDraftReading {
    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed?
}

@MainActor
protocol AnimalCreating {
    @discardableResult
    func create(input: AnimalInput) throws -> AnimalDetailSnapshot
}

@MainActor
protocol AnimalUpdating {
    @discardableResult
    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot
}

@MainActor
protocol AnimalDeleting {
    func delete(ids: [UUID]) throws
}

@MainActor
protocol AnimalArchiving {
    func archive(ids: [UUID]) throws
}

@MainActor
protocol AnimalRestoring {
    func restore(ids: [UUID]) throws
}

@MainActor
protocol AnimalPastureMoving {
    func move(ids: [UUID], toPastureID: UUID?) throws
}

@MainActor
protocol AnimalTagAdding {
    @discardableResult
    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot
}

@MainActor
protocol AnimalTagUpdating {
    @discardableResult
    func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot
}

@MainActor
protocol AnimalTagPromoting {
    @discardableResult
    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot
}

@MainActor
protocol AnimalTagRetiring {
    @discardableResult
    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot
}

@MainActor
protocol AnimalHealthRecordAdding {
    @discardableResult
    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot
}

@MainActor
protocol AnimalPregnancyCheckAdding {
    @discardableResult
    func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot
}

@MainActor
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

@MainActor
protocol AnimalEditorRepository:
    AnimalStatusReferenceReading,
    AnimalCreating,
    AnimalTagAdding
{}

@MainActor
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

@MainActor
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
