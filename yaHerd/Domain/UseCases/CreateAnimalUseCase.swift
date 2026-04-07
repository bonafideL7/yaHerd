import Foundation

struct CreateAnimalUseCase {
    let repository: any AnimalRepository

    func execute(input: AnimalInput) throws -> AnimalDetailSnapshot {
        try repository.create(input: input)
    }
}
