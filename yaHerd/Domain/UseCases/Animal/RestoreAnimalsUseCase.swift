import Foundation

struct RestoreAnimalsUseCase {
    let repository: any AnimalRepository

    func execute(ids: [UUID]) throws {
        try repository.restore(ids: ids)
    }
}
