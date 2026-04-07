import Foundation

protocol AnimalRepository {
    func fetchAnimals() throws -> [AnimalSummary]
    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot?
    func fetchPastureOptions() throws -> [PastureOption]
    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption]
    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption]
    @discardableResult
    func create(input: AnimalInput) throws -> AnimalDetailSnapshot
    @discardableResult
    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot
    func delete(ids: [UUID]) throws
    func archive(ids: [UUID]) throws
    func restore(ids: [UUID]) throws
    func move(ids: [UUID], toPastureID: UUID?) throws
    @discardableResult
    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot
    @discardableResult
    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot
    @discardableResult
    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot
}
