import Foundation

struct PromoteAnimalTagUseCase {
    let repository: any AnimalRepository

    func execute(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        try repository.promoteTag(animalID: animalID, tagID: tagID)
    }
}
