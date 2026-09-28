import Foundation

@MainActor
struct CreatePastureUseCase {
    let repository: any PastureCreateRepository

    func execute(input: PastureInput) async throws -> PastureDetailSnapshot {
        let normalized = try PastureInputValidator(repository: repository).validate(
            input: input,
            excluding: nil
        )
        return try await repository.create(input: normalized)
    }
}
