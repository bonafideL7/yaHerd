import Foundation

struct LoadAnimalsUseCase {
    let repository: any AnimalSummaryReading

    func execute() throws -> [AnimalSummary] {
        try repository.fetchAnimals()
    }
}
