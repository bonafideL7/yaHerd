import Foundation

struct UpdateAnimalTagUseCase {
    let repository: any AnimalRepository

    func execute(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        try repository.updateTag(animalID: animalID, tagID: tagID, input: input)
    }
}
