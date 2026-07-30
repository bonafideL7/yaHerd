import Foundation

@MainActor
struct ReadModelBackedAnimalRepository: AnimalRepository, AnimalListReadModelProviding {
    let base: any AnimalRepository
    let animalListReadModel: any AnimalListReadModel

    func fetchAnimals() throws -> [AnimalSummary] {
        try base.fetchAnimals()
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        try base.fetchAnimalDetail(id: id)
    }

    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] {
        try base.fetchTimeline(id: id)
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        try base.fetchStatusReferenceOptions()
    }

    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] {
        try base.fetchParentOptions(excluding: excludedAnimalID)
    }

    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? {
        try base.fetchOffspringDraftSeed(forDamID: damID)
    }

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        try base.create(input: input)
    }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        try base.update(id: id, input: input)
    }

    func delete(ids: [UUID]) throws {
        try base.delete(ids: ids)
    }

    func archive(ids: [UUID]) throws {
        try base.archive(ids: ids)
    }

    func restore(ids: [UUID]) throws {
        try base.restore(ids: ids)
    }

    func move(ids: [UUID], toPastureID: UUID?) throws {
        try base.move(ids: ids, toPastureID: toPastureID)
    }

    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        try base.addTag(animalID: animalID, input: input)
    }

    func updateTag(
        animalID: UUID,
        tagID: UUID,
        input: AnimalTagInput
    ) throws -> AnimalDetailSnapshot {
        try base.updateTag(animalID: animalID, tagID: tagID, input: input)
    }

    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        try base.promoteTag(animalID: animalID, tagID: tagID)
    }

    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        try base.retireTag(animalID: animalID, tagID: tagID)
    }

    func addHealthRecord(
        animalID: UUID,
        input: HealthRecordInput
    ) throws -> AnimalDetailSnapshot {
        try base.addHealthRecord(animalID: animalID, input: input)
    }

    func addPregnancyCheck(
        animalID: UUID,
        input: PregnancyCheckInput
    ) throws -> AnimalDetailSnapshot {
        try base.addPregnancyCheck(animalID: animalID, input: input)
    }
}
