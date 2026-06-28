import Foundation

struct LoadAnimalParentOptionsUseCase {
    let repository: any AnimalParentOptionReading

    func execute(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] {
        try repository.fetchParentOptions(excluding: excludedAnimalID)
    }
}
