import Foundation

struct MoveAnimalsUseCase {
    let repository: any AnimalRepository

    func execute(ids: [UUID], toPastureID pastureID: UUID?) throws {
        try repository.move(ids: ids, toPastureID: pastureID)
    }
}
