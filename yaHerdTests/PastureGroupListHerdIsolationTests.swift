import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class PastureGroupListHerdIsolationTests: XCTestCase {
    func testPendingDeletionCannotDeleteAfterSwitchingHerds() {
        let originalID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let group = makeGroup()
        let repository = GroupListDeletionProbe(groups: [group])
        let model = PastureGroupListViewModel()
        model.requestDelete(group, selection: selection)

        selection.select(UUID())
        model.deleteGroup(id: group.id, using: repository, selection: selection)

        XCTAssertTrue(repository.validatedIDs.isEmpty)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        XCTAssertNil(model.groupPendingDeletion)
    }

    func testPendingDeletionCannotDeleteAfterSelectionRoundTrip() {
        let originalID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let group = makeGroup()
        let repository = GroupListDeletionProbe(groups: [group])
        let model = PastureGroupListViewModel()
        model.requestDelete(group, selection: selection)

        selection.select(UUID())
        selection.select(originalID)
        model.deleteGroup(id: group.id, using: repository, selection: selection)

        XCTAssertTrue(repository.validatedIDs.isEmpty)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        XCTAssertNil(model.groupPendingDeletion)
    }

    func testUnchangedSelectionDeletesConfirmedGroup() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let group = makeGroup()
        let repository = GroupListDeletionProbe(groups: [group])
        let model = PastureGroupListViewModel()
        model.requestDelete(group, selection: selection)

        model.deleteGroup(id: group.id, using: repository, selection: selection)

        XCTAssertEqual(repository.validatedIDs, [[group.id]])
        XCTAssertEqual(repository.deletedIDs, [[group.id]])
        XCTAssertNil(model.groupPendingDeletion)
        XCTAssertTrue(model.groups.isEmpty)
    }

    func testHerdSwitchResetsPendingConfirmationAndOldList() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let group = makeGroup()
        let repository = GroupListDeletionProbe(groups: [group])
        let model = PastureGroupListViewModel()
        model.load(using: repository)
        model.requestDelete(group, selection: selection)
        model.requestAddGroup()
        model.errorMessage = "Previous Herd error"

        model.resetForHerdChange()

        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertNil(model.groupPendingDeletion)
        XCTAssertFalse(model.isPresentingAddGroup)
        XCTAssertNil(model.errorMessage)
    }

    private func makeGroup() -> PastureGroupSummary {
        PastureGroupSummary(
            id: UUID(), name: "Spring Rotation",
            grazeDays: 7, restDays: 21, pastureCount: 1
        )
    }
}

@MainActor
private final class GroupListDeletionProbe: PastureGroupListRepository {
    var groups: [PastureGroupSummary]
    private(set) var validatedIDs: [[UUID]] = []
    private(set) var deletedIDs: [[UUID]] = []

    init(groups: [PastureGroupSummary]) {
        self.groups = groups
    }

    func fetchPastureGroups() throws -> [PastureGroupSummary] {
        groups
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        validatedIDs.append(ids)
    }

    func deleteGroups(ids: [UUID]) throws {
        deletedIDs.append(ids)
        groups.removeAll { ids.contains($0.id) }
    }
}
