import Foundation

struct DeleteAnimalsUseCase {
    let repository: any AnimalRepository

    func execute(ids: [UUID]) throws {
        try repository.delete(ids: ids)
    }
}
