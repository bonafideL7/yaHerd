import Foundation

@MainActor
struct DeletePasturesUseCase: PastureDeletionPerforming {
    let pastureRepository: any PastureDeleteRepository
    let animalRepository: any AnimalPastureMoving
    let fieldCheckRepository: any FieldCheckPastureArchiveWriter

    // Transitional implementation supplied by the current single-stack runtime.
    // The final M10 Core Data assembly supplies DeletePasturesAtomicallyUseCase instead.
    func deletePastures(ids: [UUID], archivedAt: Date) async throws {
        try await execute(ids: ids, archivedAt: archivedAt)
    }

    func execute(ids: [UUID], archivedAt: Date = .now) async throws {
        guard !ids.isEmpty else { return }
        try validateUnique(ids)
        try pastureRepository.validatePastureIDsExist(ids)

        let residentAnimalIDs = try ids.flatMap { pastureID in
            try pastureRepository.fetchResidentAnimals(pastureID: pastureID).map(\.id)
        }

        if !residentAnimalIDs.isEmpty {
            try animalRepository.move(ids: residentAnimalIDs, toPastureID: nil)
        }

        try await fieldCheckRepository.archiveSessionsForDeletedPastures(ids, archivedAt: archivedAt)
        try pastureRepository.delete(ids: ids)
    }

    private func validateUnique(_ ids: [UUID]) throws {
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }
    }
}
