import Foundation

struct CollectWorkingAnimalsUseCase {
    let repository: any WorkingRepository

    func execute(sessionID: UUID, animalIDs: [UUID]) throws {
        try repository.collectAnimals(sessionID: sessionID, animalIDs: animalIDs)
    }
}
