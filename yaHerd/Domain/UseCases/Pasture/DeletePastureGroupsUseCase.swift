import Foundation

@MainActor
struct DeletePastureGroupsUseCase {
    let repository: any PastureGroupDeleteRepository

    func execute(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try repository.validatePastureGroupIDsExist(ids)
        try await repository.deleteGroups(ids: ids)
    }
}
