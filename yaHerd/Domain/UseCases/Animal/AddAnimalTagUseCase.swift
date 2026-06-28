import Foundation

struct AddAnimalTagUseCase {
    let repository: any AnimalTagAdding

    func execute(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        try repository.addTag(animalID: animalID, input: input)
    }
}
