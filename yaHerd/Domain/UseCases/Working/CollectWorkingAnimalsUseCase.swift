import Foundation

struct CollectWorkingAnimalsUseCase {
    let repository: any WorkingAnimalCollecting

    func execute(sessionID: UUID, animalIDs: [UUID]) throws {
        try repository.collectAnimals(sessionID: sessionID, animalIDs: animalIDs)
    }
}
