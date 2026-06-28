import Foundation

struct UpdateAnimalUseCase {
    let repository: any AnimalUpdating

    func execute(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        try repository.update(id: id, input: input)
    }
}
