import Foundation

struct ReorderPasturesUseCase {
    let repository: any PastureRepository

    func execute(ids: [UUID]) throws {
        try repository.reorder(ids: ids)
    }
}
