import Foundation

struct CreateAnimalUseCase {
    let repository: any AnimalCreating

    func execute(input: AnimalInput) throws -> AnimalDetailSnapshot {
        try repository.create(input: input)
    }
}
