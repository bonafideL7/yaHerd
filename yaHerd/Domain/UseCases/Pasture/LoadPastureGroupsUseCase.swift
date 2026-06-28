import Foundation

struct LoadPastureGroupsUseCase {
    let repository: any PastureGroupListReader

    func execute() throws -> [PastureGroupSummary] {
        try repository.fetchPastureGroups()
    }
}
