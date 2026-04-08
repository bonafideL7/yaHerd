import Foundation

struct ArchiveAnimalsUseCase {
    let repository: any AnimalRepository

    func execute(ids: [UUID]) throws {
        try repository.archive(ids: ids)
    }
}
