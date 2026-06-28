import Foundation

struct RestoreAnimalsUseCase {
    let repository: any AnimalRestoring

    func execute(ids: [UUID]) throws {
        try repository.restore(ids: ids)
    }
}
