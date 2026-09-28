import Foundation

@MainActor
struct ReorderPasturesUseCase {
    let repository: any PastureOrdering

    func execute(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        guard Set(ids).count == ids.count else {
            throw PastureRepositoryError.duplicatePastureIDs
        }

        try await repository.reorder(ids: ids)
    }
}
