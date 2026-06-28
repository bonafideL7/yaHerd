import Foundation

struct DeleteAnimalsUseCase {
    let repository: any AnimalDeleting

    func execute(ids: [UUID]) throws {
        try repository.delete(ids: ids)
    }
}
