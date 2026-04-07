import Foundation

struct RetireAnimalTagUseCase {
    let repository: any AnimalRepository

    func execute(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        try repository.retireTag(animalID: animalID, tagID: tagID)
    }
}
