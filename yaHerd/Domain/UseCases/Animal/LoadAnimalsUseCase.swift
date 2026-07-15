import Foundation

@MainActor
struct LoadAnimalsUseCase {
    let repository: any AnimalSummaryReading

    func execute() throws -> [AnimalSummary] {
        try repository.fetchAnimals()
    }
}
