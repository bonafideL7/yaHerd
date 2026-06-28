import Foundation

struct RetireAnimalTagUseCase {
    let repository: any AnimalTagRetiring

    func execute(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        try repository.retireTag(animalID: animalID, tagID: tagID)
    }
}
