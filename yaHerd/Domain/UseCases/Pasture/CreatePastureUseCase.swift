import Foundation

struct CreatePastureUseCase {
    let repository: any PastureRepository

    func execute(input: PastureInput) throws -> PastureDetailSnapshot {
        let normalized = try PastureInputValidator(repository: repository).validate(
            input: input,
            excluding: nil
        )
        return try repository.create(input: normalized)
    }
}
