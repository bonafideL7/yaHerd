import Foundation

@MainActor
struct UpdatePastureUseCase {
    let repository: any PastureUpdateRepository

    func execute(id: UUID, input: PastureInput) async throws -> PastureDetailSnapshot {
        let normalized = try PastureInputValidator(repository: repository).validate(
            input: input,
            excluding: id
        )
        return try await repository.update(id: id, input: normalized)
    }
}
