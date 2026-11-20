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
    private var loadedHerdID: UUID?
    private var loadedSelectionRevision: UInt64?

    var loadedSelectionIdentity: (herdID: UUID, revision: UInt64)? {
        guard let loadedHerdID, let loadedSelectionRevision else { return nil }
        return (loadedHerdID, loadedSelectionRevision)
    }

    func isLoadedForCurrentSelection(_ selection: AppCurrentHerdSelection) -> Bool {
        guard let identity = loadedSelectionIdentity else { return false }
        return selection.currentHerdID == identity.herdID
            && selection.selectionRevision == identity.revision
    }

    func load(
        using repository: any PastureGroupListReader,
        selection: AppCurrentHerdSelection
    ) {
        do {
            groups = try repository.fetchPastureGroups()
            loadedHerdID = selection.currentHerdID
            loadedSelectionRevision = selection.selectionRevision
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func requestAddGroup() {
        isPresentingAddGroup = true
    }

    func requestDelete(
        _ group: PastureGroupSummary,
        originatingHerdID: UUID?,
        originatingSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        // A row's action may execute after its Herd is no longer selected.
        // Never re-stamp an obsolete row with the current Herd's identity.
        guard let originatingHerdID,
              selection.currentHerdID == originatingHerdID,
              selection.selectionRevision == originatingSelectionRevision,
              loadedHerdID == originatingHerdID,
              loadedSelectionRevision == originatingSelectionRevision,
              groups.contains(where: { $0.id == group.id }) else {
            return
        }
        groupPendingDeletion = group
        pendingDeletionHerdID = originatingHerdID
        pendingDeletionSelectionRevision = originatingSelectionRevision
    }

    func clearPendingDeletion() {
        groupPendingDeletion = nil
        pendingDeletionHerdID = nil
        pendingDeletionSelectionRevision = nil
    }

    func resetForHerdChange() {
        groups = []
        loadedHerdID = nil
        loadedSelectionRevision = nil
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
              pendingDeletionSelectionRevision == selection.selectionRevision,
              loadedHerdID == pendingDeletionHerdID,
              loadedSelectionRevision == pendingDeletionSelectionRevision else {
            clearPendingDeletion()
            return
        }

        do {
            try DeletePastureGroupsUseCase(repository: repository).execute(ids: [id])
            clearPendingDeletion()
            load(using: repository, selection: selection)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
