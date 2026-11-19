import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class PastureGroupAssignmentHerdIsolationTests: XCTestCase {
    func testAssignmentRejectsDifferentSelectedHerdBeforeRepositoryAccess() throws {
        let (model, row, repository, selection) = makeFixture()
        let origin = try XCTUnwrap(selection.currentHerdID)
        let revision = selection.selectionRevision

        selection.select(UUID())
        model.toggleAssignment(
            row, using: repository,
            expectedHerdID: origin,
            expectedSelectionRevision: revision,
            selection: selection
        )

        XCTAssertTrue(repository.validatedPastureIDs.isEmpty)
        XCTAssertTrue(repository.validatedGroupIDs.isEmpty)
        XCTAssertTrue(repository.assignments.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testAssignmentRejectsSelectionRoundTripBackToSameHerd() throws {
        let (model, row, repository, selection) = makeFixture()
        let origin = try XCTUnwrap(selection.currentHerdID)
        let revision = selection.selectionRevision

        selection.select(UUID())
        selection.select(origin)
        model.toggleAssignment(
            row, using: repository,
            expectedHerdID: origin,
            expectedSelectionRevision: revision,
            selection: selection
        )

        XCTAssertTrue(repository.validatedPastureIDs.isEmpty)
        XCTAssertTrue(repository.assignments.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testAssignmentRejectsRevokedSelectionWithoutWriting() throws {
        let (model, row, repository, selection) = makeFixture()
        let origin = try XCTUnwrap(selection.currentHerdID)
        let revision = selection.selectionRevision

        selection.deferCurrentHerdUntilImportReady()
        model.toggleAssignment(
            row, using: repository,
            expectedHerdID: origin,
            expectedSelectionRevision: revision,
            selection: selection
        )

        XCTAssertTrue(repository.validatedPastureIDs.isEmpty)
        XCTAssertTrue(repository.assignments.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testAssignmentInUnchangedHerdUsesExistingValidationAndReload() throws {
        let (model, row, repository, selection) = makeFixture()
        let origin = try XCTUnwrap(selection.currentHerdID)

        model.toggleAssignment(
            row, using: repository,
            expectedHerdID: origin,
            expectedSelectionRevision: selection.selectionRevision,
            selection: selection
        )

        XCTAssertEqual(repository.validatedPastureIDs, [[row.pasture.id]])
        XCTAssertEqual(repository.validatedGroupIDs, [[row.groupID]])
        XCTAssertEqual(repository.assignments.count, 1)
        XCTAssertEqual(repository.assignments.first?.pastureID, row.pasture.id)
        XCTAssertEqual(repository.assignments.first?.groupID, row.groupID)
        XCTAssertEqual(repository.groupReads, 1)
        XCTAssertEqual(repository.pastureReads, 1)
        XCTAssertNil(model.errorMessage)
    }

    private func makeFixture() -> (
        PastureGroupDetailViewModel,
        PastureGroupAssignmentRow,
        AssignmentRepositoryProbe,
        AppCurrentHerdSelection
    ) {
        let groupID = UUID()
        let pasture = PastureTestSupport.makeSummary(name: "North")
        let row = PastureGroupAssignmentRow(pasture: pasture, groupID: groupID)
        let model = PastureGroupDetailViewModel()
        let detail = PastureGroupDetailSnapshot(
            id: groupID, name: "North Rotation", grazeDays: 7,
            restDays: 21, pastures: []
        )
        model.detail = detail
        model.allPastures = [pasture]
        let repository = AssignmentRepositoryProbe(detail: detail, pastures: [pasture])
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        return (model, row, repository, selection)
    }
}

@MainActor
private final class AssignmentRepositoryProbe: PastureGroupDetailRepository {
    let detail: PastureGroupDetailSnapshot
    let pastures: [PastureSummary]
    private(set) var validatedPastureIDs: [[UUID]] = []
    private(set) var validatedGroupIDs: [[UUID]] = []
    private(set) var assignments: [(pastureID: UUID, groupID: UUID?)] = []
    private(set) var groupReads = 0
    private(set) var pastureReads = 0

    init(detail: PastureGroupDetailSnapshot, pastures: [PastureSummary]) {
        self.detail = detail
        self.pastures = pastures
    }

    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? {
        groupReads += 1
        return detail
    }

    func fetchPastures() throws -> [PastureSummary] {
        pastureReads += 1
        return pastures
    }

    func validatePastureIDsExist(_ ids: [UUID]) throws {
        validatedPastureIDs.append(ids)
    }

    func validatePastureGroupIDsExist(_ ids: [UUID]) throws {
        validatedGroupIDs.append(ids)
    }

    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws {
        assignments.append((pastureID, groupID))
    }
}
