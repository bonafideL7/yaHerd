import Foundation

struct LoadAnimalParentOptionsUseCase {
    let repository: any AnimalRepository

    func execute(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] {
        try repository.fetchParentOptions(excluding: excludedAnimalID)
    }
}
