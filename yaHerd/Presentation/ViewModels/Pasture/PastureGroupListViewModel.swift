import Foundation
import Observation

@MainActor
@Observable
final class PastureGroupListViewModel {
    var groups: [PastureGroupSummary] = []
    var errorMessage: String?
    var isPresentingAddGroup = false
    var groupPendingDeletion: PastureGroupSummary?

    func load(using repository: any PastureGroupListReader) {
        do {
            groups = try repository.fetchPastureGroups()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func requestAddGroup() {
        isPresentingAddGroup = true
    }

    func requestDelete(_ group: PastureGroupSummary) {
        groupPendingDeletion = group
    }

    func clearPendingDeletion() {
        groupPendingDeletion = nil
    }

    func deleteGroup(id: UUID, using repository: any PastureGroupDeleteRepository & PastureGroupListReader) {
        do {
            try DeletePastureGroupsUseCase(repository: repository).execute(ids: [id])
            groupPendingDeletion = nil
            load(using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
