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
    var isPresentingEditGroup = false

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

    func load(groupID: UUID, using repository: any PastureGroupDetailReader & PastureListReader) {
        do {
            detail = try LoadPastureGroupDetailUseCase(repository: repository).execute(id: groupID)
            allPastures = try LoadPasturesUseCase(repository: repository).execute()
            hasLoaded = true
            errorMessage = nil
        } catch {
            hasLoaded = true
            errorMessage = error.localizedDescription
        }
    }

    func beginEditing() {
        isPresentingEditGroup = true
    }

    func reloadAfterSave(groupID: UUID, using repository: any PastureGroupDetailReader & PastureListReader) {
        load(groupID: groupID, using: repository)
    }

    func toggleAssignment(_ row: PastureGroupAssignmentRow, using repository: any PastureGroupAssignRepository & PastureGroupDetailReader & PastureListReader) {
        let destinationGroupID = row.isAssignedToCurrentGroup ? nil : detail?.id
        assign(row.pasture.id, to: destinationGroupID, using: repository)
    }

    func assign(_ pastureID: UUID, to groupID: UUID?, using repository: any PastureGroupAssignRepository & PastureGroupDetailReader & PastureListReader) {
        do {
            try AssignPastureToGroupUseCase(repository: repository).execute(
                pastureID: pastureID,
                groupID: groupID
            )
            if let detail {
                load(groupID: detail.id, using: repository)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
