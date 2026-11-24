import Foundation
import Observation

struct PastureGroupAssignmentRow: Identifiable, Hashable {
    let pasture: PastureSummary
    let groupID: UUID

    var id: UUID { pasture.id }
    var isAssignedToCurrentGroup: Bool { pasture.groupID == groupID }
    var isAssignedToAnotherGroup: Bool { pasture.groupID != nil && pasture.groupID != groupID }
    var assignmentDescription: String? {
        guard let groupName = pasture.groupName else { return nil }
        return isAssignedToCurrentGroup ? "Assigned" : "Assigned to \(groupName)"
    }
}

@MainActor
@Observable
final class PastureGroupDetailViewModel {
    var detail: PastureGroupDetailSnapshot?
    var allPastures: [PastureSummary] = []
    var errorMessage: String?
    var hasLoaded = false
    // Presentation identity is captured when editing begins, independently of live reads.
    var editingGroup: PastureGroupDetailSnapshot?

    var navigationTitle: String {
        detail?.name ?? "Pasture Group"
    }

    var assignmentRows: [PastureGroupAssignmentRow] {
        guard let detail else { return [] }
        return allPastures
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { pasture in
                PastureGroupAssignmentRow(pasture: pasture, groupID: detail.id)
            }
    }

    func load(
        groupID: UUID,
        using repository: any PastureGroupDetailReader & PastureListReader,
        expectedHerdID: UUID?,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        guard let expectedHerdID,
              selection.currentHerdID == expectedHerdID,
              selection.selectionRevision == expectedSelectionRevision else {
            resetForHerdChange()
            return
        }

        do {
            // Only publish a complete group/pasture pair. A partially imported
            // graph must not combine a new group with older assignment rows.
            let fetchedDetail = try repository.fetchPastureGroupDetail(id: groupID)
            let fetchedPastures = try repository.fetchPastures()
            detail = fetchedDetail
            allPastures = fetchedPastures
            hasLoaded = true
            errorMessage = nil
        } catch {
            // A failed refresh cannot authorize edits through retained rows.
            detail = nil
            allPastures = []
            hasLoaded = true
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func beginEditing(
        expectedHerdID: UUID?,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        guard let expectedHerdID,
              selection.currentHerdID == expectedHerdID,
              selection.selectionRevision == expectedSelectionRevision else {
            resetForHerdChange()
            return
        }
        guard let detail else { return }
        editingGroup = detail
    }

    func reloadAfterSave(
        groupID: UUID,
        using repository: any PastureGroupDetailReader & PastureListReader,
        expectedHerdID: UUID?,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        load(
            groupID: groupID, using: repository,
            expectedHerdID: expectedHerdID,
            expectedSelectionRevision: expectedSelectionRevision,
            selection: selection
        )
    }

    func resetForHerdChange() {
        detail = nil
        allPastures = []
        errorMessage = nil
        hasLoaded = false
        editingGroup = nil
    }

    func toggleAssignment(
        _ row: PastureGroupAssignmentRow,
        using repository: any PastureGroupAssignRepository & PastureGroupDetailReader & PastureListReader,
        expectedHerdID: UUID,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        // The repository uses the live selection. A retained detail action
        // must not redirect an earlier Herd's assignment to the new Herd,
        // including a switch away and back to the same UUID.
        guard selection.currentHerdID == expectedHerdID,
              selection.selectionRevision == expectedSelectionRevision,
              let detail,
              detail.id == row.groupID,
              assignmentRows.contains(row) else { return }
        let destinationGroupID = row.isAssignedToCurrentGroup ? nil : detail.id
        assign(
            row.pasture.id, to: destinationGroupID, using: repository,
            expectedHerdID: expectedHerdID,
            expectedSelectionRevision: expectedSelectionRevision,
            selection: selection
        )
    }

    private func assign(
        _ pastureID: UUID,
        to groupID: UUID?,
        using repository: any PastureGroupAssignRepository & PastureGroupDetailReader & PastureListReader,
        expectedHerdID: UUID,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        do {
            try AssignPastureToGroupUseCase(repository: repository).execute(
                pastureID: pastureID,
                groupID: groupID
            )
            if let detail {
                load(
                    groupID: detail.id, using: repository,
                    expectedHerdID: expectedHerdID,
                    expectedSelectionRevision: expectedSelectionRevision,
                    selection: selection
                )
            }
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
