import Foundation

extension AnimalListViewModel {
    func performPrimarySwipeAction(
        animalID: UUID,
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        performPrimarySwipeAction(
            animalID: animalID,
            hardDelete: false,
            using: repository,
            pastureRepository: pastureRepository
        )
    }
}
