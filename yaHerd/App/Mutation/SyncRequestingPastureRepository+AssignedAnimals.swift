import Foundation

extension SyncRequestingPastureRepository {
    func fetchAssignedAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        try base.fetchAssignedAnimals(pastureID: pastureID)
    }
}
