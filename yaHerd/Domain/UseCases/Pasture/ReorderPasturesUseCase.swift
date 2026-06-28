import Foundation

struct ReorderPasturesUseCase {
    let repository: any PastureOrdering

    func execute(ids: [UUID]) throws {
        try repository.reorder(ids: ids)
    }
}
