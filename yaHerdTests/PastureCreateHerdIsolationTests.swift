import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class PastureCreateHerdIsolationTests: XCTestCase {
    func testCreateDoesNotWriteAfterHerdSwitch() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let revision = selection.selectionRevision
        let repository = PastureCreateRepositorySpy()
        let model = configuredForm()

        selection.select(UUID())

        XCTAssertThrowsError(
            try create(model, using: repository, selection: selection, herdID: origin, revision: revision)
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(repository.receivedExcludingIDs.isEmpty)
        XCTAssertTrue(repository.createdInputs.isEmpty)
    }

    func testCreateDoesNotWriteAfterSelectionRoundTrip() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let revision = selection.selectionRevision
        let repository = PastureCreateRepositorySpy()
        let model = configuredForm()

        selection.select(UUID())
        selection.select(origin)

        XCTAssertThrowsError(
            try create(model, using: repository, selection: selection, herdID: origin, revision: revision)
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(repository.receivedExcludingIDs.isEmpty)
        XCTAssertTrue(repository.createdInputs.isEmpty)
    }

    func testCreateDoesNotWriteAfterSelectedHerdBecomesUnavailable() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let revision = selection.selectionRevision
        let repository = PastureCreateRepositorySpy()
        let model = configuredForm()

        selection.select(nil)

        XCTAssertThrowsError(
            try create(model, using: repository, selection: selection, herdID: origin, revision: revision)
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(repository.receivedExcludingIDs.isEmpty)
        XCTAssertTrue(repository.createdInputs.isEmpty)
    }

    func testCreateInUnchangedHerdPersistsNormalizedInput() throws {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let repository = PastureCreateRepositorySpy()
        let model = configuredForm()

        try create(
            model, using: repository, selection: selection,
            herdID: origin, revision: selection.selectionRevision
        )

        XCTAssertEqual(repository.receivedExcludingIDs.count, 1)
        XCTAssertEqual(repository.createdInputs, [
            PastureInput(name: "North", acreage: 10, usableAcreage: 8, targetAcresPerHead: 2)
        ])
    }

    private func configuredForm() -> PastureFormViewModel {
        let model = PastureFormViewModel()
        model.name = "  North  "
        model.acreageText = "10"
        return model
    }

    private func create(
        _ model: PastureFormViewModel,
        using repository: any PastureCreateRepository,
        selection: AppCurrentHerdSelection,
        herdID: UUID,
        revision: UInt64
    ) throws {
        try model.create(
            using: repository,
            defaultTargetAcresPerHead: 2,
            usableAcreagePercentDefault: 80,
            expectedHerdID: herdID,
            expectedSelectionRevision: revision,
            selection: selection
        )
    }
}
