import Foundation

struct DeletePasturesUseCase {
    let repository: any PastureRepository

    func execute(ids: [UUID]) throws {
        try repository.delete(ids: ids)
    }
}
