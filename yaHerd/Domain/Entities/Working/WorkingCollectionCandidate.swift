import Foundation

struct WorkingCollectionCandidate: Hashable {
    let animalID: UUID
    let activeSessionID: UUID?

    init(animalID: UUID, activeSessionID: UUID?) {
        self.animalID = animalID
        self.activeSessionID = activeSessionID
    }
}
