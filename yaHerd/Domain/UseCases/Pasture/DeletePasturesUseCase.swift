import Foundation

struct DeletePasturesUseCase {
    let pastureRepository: any PastureDeleteRepository
    let animalRepository: any AnimalPastureMoving
    let fieldCheckRepository: any FieldCheckPastureCleanupWriter

    func execute(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try validateUnique(ids)
        try pastureRepository.validatePastureIDsExist(ids)

        let residentAnimalIDs = try ids.flatMap { pastureID in
            try pastureRepository.fetchResidentAnimals(pastureID: pastureID).map(\.id)
        }

        if !residentAnimalIDs.isEmpty {
            try animalRepository.move(ids: residentAnimalIDs, toPastureID: nil)
        }

        try fieldCheckRepository.deleteSessions(forPastureIDs: ids)
        try pastureRepository.delete(ids: ids)
    }

    private func validateUnique(_ ids: [UUID]) throws {
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }
    }
}
