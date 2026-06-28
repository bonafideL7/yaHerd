import Foundation

struct DeletePastureGroupsUseCase {
    let repository: any PastureGroupDeleteRepository

    func execute(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try repository.validatePastureGroupIDsExist(ids)
        try repository.deleteGroups(ids: ids)
    }
}
