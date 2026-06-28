import Foundation

struct WorkingCollectionRules {
    static func validateCollection(
        existingAnimalIDs: Set<UUID>,
        candidates: [WorkingCollectionCandidate],
        sessionID: UUID
    ) throws {
        for candidate in candidates {
            if existingAnimalIDs.contains(candidate.animalID) {
                throw WorkingRepositoryError.duplicateAnimalCollection
            }

            if let activeSessionID = candidate.activeSessionID, activeSessionID != sessionID {
                throw WorkingRepositoryError.animalAlreadyInAnotherSession
            }
        }
    }
}
