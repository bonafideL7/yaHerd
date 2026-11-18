import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class PastureGroupEditorHerdIsolationTests: XCTestCase {
    func testCreateDoesNotWriteAfterHerdSwitch() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let revision = selection.selectionRevision
        let repository = GroupWriteProbe()
        let model = configuredForm()

        selection.select(UUID())

        XCTAssertThrowsError(
            try model.create(
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: revision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.nameCheckCount, 0)
        XCTAssertEqual(repository.createCount, 0)
    }

    func testCreateDoesNotWriteAfterSelectionRoundTrip() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let revision = selection.selectionRevision
        let repository = GroupWriteProbe()
        let model = configuredForm()

        selection.select(UUID())
        selection.select(origin)

        XCTAssertThrowsError(
            try model.create(
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: revision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.createCount, 0)
    }

    func testUpdateDoesNotWriteAfterHerdRevocation() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let revision = selection.selectionRevision
        let repository = GroupWriteProbe()
        let model = configuredForm()

        selection.select(nil)

        XCTAssertThrowsError(
            try model.update(
                id: UUID(),
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: revision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testUpdateDoesNotWriteAfterSelectionRoundTrip() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let revision = selection.selectionRevision
        let repository = GroupWriteProbe()
        let model = configuredForm()

        selection.select(UUID())
        selection.select(origin)

        XCTAssertThrowsError(
            try model.update(
                id: UUID(),
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: revision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testCreateInUnchangedHerdCallsRepository() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let repository = GroupWriteProbe()
        let model = configuredForm()

        XCTAssertThrowsError(
            try model.create(
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is GroupWriteProbe.ProbeError)
        }
        XCTAssertEqual(repository.createCount, 1)
        XCTAssertEqual(repository.nameCheckCount, 1)
    }

    func testUpdateInUnchangedHerdCallsRepository() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let repository = GroupWriteProbe()
        let model = configuredForm()

        XCTAssertThrowsError(
            try model.update(
                id: UUID(),
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is GroupWriteProbe.ProbeError)
        }
        XCTAssertEqual(repository.updateCount, 1)
        XCTAssertEqual(repository.nameCheckCount, 1)
    }

    private func configuredForm() -> PastureGroupFormViewModel {
        let model = PastureGroupFormViewModel()
        model.name = "Spring Rotation"
        return model
    }
}

@MainActor
private final class GroupWriteProbe: PastureGroupEditorRepository {
    enum ProbeError: Error {
        case attempted
    }

    private(set) var nameCheckCount = 0
    private(set) var createCount = 0
    private(set) var updateCount = 0

    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        nameCheckCount += 1
        return false
    }

    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        createCount += 1
        throw ProbeError.attempted
    }

    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot {
        updateCount += 1
        throw ProbeError.attempted
    }
}
