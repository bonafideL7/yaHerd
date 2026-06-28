import Foundation

struct UpdatePastureUseCase {
    let repository: any PastureUpdateRepository

    func execute(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        let normalized = try PastureInputValidator(repository: repository).validate(
            input: input,
            excluding: id
        )
        return try repository.update(id: id, input: normalized)
    }
}
