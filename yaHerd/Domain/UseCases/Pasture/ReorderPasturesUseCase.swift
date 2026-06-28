import Foundation

struct ReorderPasturesUseCase {
    let repository: any PastureOrdering

    func execute(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }

        try repository.reorder(ids: ids)
    }
}
