import Foundation

struct UpdateAnimalUseCase {
    let repository: any AnimalRepository

    func execute(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        try repository.update(id: id, input: input)
    }
}
