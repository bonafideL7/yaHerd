import Foundation

struct LoadAnimalsUseCase {
    let repository: any AnimalRepository

    func execute() throws -> [AnimalSummary] {
        try repository.fetchAnimals()
    }
}
