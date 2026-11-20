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
        model.load(using: repository, selection: selection)
        model.requestDelete(
            group,
            originatingHerdID: selection.currentHerdID,
            originatingSelectionRevision: selection.selectionRevision,
            selection: selection
        )

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
        model.load(using: repository, selection: selection)
        model.requestDelete(
            group,
            originatingHerdID: selection.currentHerdID,
            originatingSelectionRevision: selection.selectionRevision,
            selection: selection
        )

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
        model.load(using: repository, selection: selection)
        model.requestDelete(
            group,
            originatingHerdID: selection.currentHerdID,
            originatingSelectionRevision: selection.selectionRevision,
            selection: selection
        )

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
        model.load(using: repository, selection: selection)
        model.requestDelete(
            group,
            originatingHerdID: selection.currentHerdID,
            originatingSelectionRevision: selection.selectionRevision,
            selection: selection
        )
        model.requestAddGroup()
        model.errorMessage = "Previous Herd error"

        model.resetForHerdChange()

        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertNil(model.groupPendingDeletion)
        XCTAssertFalse(model.isPresentingAddGroup)
        XCTAssertNil(model.errorMessage)
    }

    func testLateSwipeFromPreviousHerdCannotStampSameUUIDOnCurrentHerd() {
        let originalHerdID = UUID()
        let nextHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let group = makeGroup()
        let repository = GroupListDeletionProbe(groups: [group])
        let model = PastureGroupListViewModel()
        model.load(using: repository, selection: selection)

        // A retained row callback executes after B replaces the list with
        // a different Herd's group that happens to have the same UUID.
        selection.select(nextHerdID)
        model.resetForHerdChange()
        repository.groups = [group]
        model.load(using: repository, selection: selection)
        model.requestDelete(
            group,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: originalRevision,
            selection: selection
        )
        model.deleteGroup(id: group.id, using: repository, selection: selection)

        XCTAssertNil(model.groupPendingDeletion)
        XCTAssertTrue(repository.validatedIDs.isEmpty)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        XCTAssertEqual(repository.groups.map(\.id), [group.id])
    }

    func testLateSwipeCannotReactivateAfterReturningToOriginalHerd() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let originalRevision = selection.selectionRevision
        let group = makeGroup()
        let repository = GroupListDeletionProbe(groups: [group])
        let model = PastureGroupListViewModel()
        model.load(using: repository, selection: selection)

        selection.select(UUID())
        selection.select(herdID)
        model.resetForHerdChange()
        model.load(using: repository, selection: selection)
        model.requestDelete(
            group,
            originatingHerdID: herdID,
            originatingSelectionRevision: originalRevision,
            selection: selection
        )
        model.deleteGroup(id: group.id, using: repository, selection: selection)

        XCTAssertNil(model.groupPendingDeletion)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        XCTAssertEqual(repository.groups.count, 1)
    }

    func testRowFromPreviousListIsRejectedBeforeReloadCompletes() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let group = makeGroup()
        let repository = GroupListDeletionProbe(groups: [group])
        let model = PastureGroupListViewModel()
        model.load(using: repository, selection: selection)

        selection.select(UUID())
        model.requestDelete(
            group,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: originalRevision,
            selection: selection
        )

        XCTAssertNil(model.groupPendingDeletion)
        XCTAssertEqual(repository.groups.count, 1)
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
