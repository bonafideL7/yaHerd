import Foundation

@MainActor
struct ArchiveAnimalsUseCase {
    let repository: any AnimalArchiving

    func execute(ids: [UUID]) throws {
        try repository.archive(ids: ids)
    }
}
