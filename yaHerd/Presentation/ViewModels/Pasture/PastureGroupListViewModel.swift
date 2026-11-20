import Foundation
import Observation

@MainActor
@Observable
final class PastureGroupListViewModel {
    var groups: [PastureGroupSummary] = []
    var errorMessage: String?
    var isPresentingAddGroup = false
    var groupPendingDeletion: PastureGroupSummary?

    private var pendingDeletionHerdID: UUID?
    private var pendingDeletionSelectionRevision: UInt64?

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

    func requestDelete(_ group: PastureGroupSummary, selection: AppCurrentHerdSelection) {
        guard let herdID = selection.currentHerdID else {
            clearPendingDeletion()
            return
        }
        groupPendingDeletion = group
        pendingDeletionHerdID = herdID
        pendingDeletionSelectionRevision = selection.selectionRevision
    }

    func clearPendingDeletion() {
        groupPendingDeletion = nil
        pendingDeletionHerdID = nil
        pendingDeletionSelectionRevision = nil
    }

    func resetForHerdChange() {
        groups = []
        errorMessage = nil
        isPresentingAddGroup = false
        clearPendingDeletion()
    }

    func deleteGroup(
        id: UUID,
        using repository: any PastureGroupDeleteRepository & PastureGroupListReader,
        selection: AppCurrentHerdSelection
    ) {
        guard groupPendingDeletion?.id == id,
              pendingDeletionHerdID == selection.currentHerdID,
              pendingDeletionSelectionRevision == selection.selectionRevision else {
            clearPendingDeletion()
            return
        }

        do {
            try DeletePastureGroupsUseCase(repository: repository).execute(ids: [id])
            clearPendingDeletion()
            load(using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
