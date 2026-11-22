import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class PastureDetailEditorHerdIsolationTests: XCTestCase {
    func testEditingRejectsASelectionSwitchBeforeAnyWrite() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let pastureID = UUID()
        let repository = PastureDetailEditProbe(pastureID: pastureID)
        let model = loadedEditor(pastureID: pastureID, repository: repository, selection: selection)

        selection.select(UUID())
        model.save(
            pastureID: pastureID,
            using: repository,
            expectedHerdID: originalHerdID,
            expectedSelectionRevision: originalRevision,
            selection: selection
        )

        XCTAssertTrue(repository.updatedIDs.isEmpty)
        XCTAssertTrue(repository.checkedNames.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testEditingRejectsSelectionRoundTripToOriginalHerd() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let pastureID = UUID()
        let repository = PastureDetailEditProbe(pastureID: pastureID)
        let model = loadedEditor(pastureID: pastureID, repository: repository, selection: selection)

        selection.select(UUID())
        selection.select(originalHerdID)
        model.save(
            pastureID: pastureID,
            using: repository,
            expectedHerdID: originalHerdID,
            expectedSelectionRevision: originalRevision,
            selection: selection
        )

        XCTAssertTrue(repository.updatedIDs.isEmpty)
        XCTAssertTrue(repository.checkedNames.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testEditingRejectsRevokedHerdWithoutWriting() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let pastureID = UUID()
        let repository = PastureDetailEditProbe(pastureID: pastureID)
        let model = loadedEditor(pastureID: pastureID, repository: repository, selection: selection)

        selection.select(nil)
        model.save(
            pastureID: pastureID,
            using: repository,
            expectedHerdID: originalHerdID,
            expectedSelectionRevision: originalRevision,
            selection: selection
        )

        XCTAssertTrue(repository.updatedIDs.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testEditingUnchangedHerdPersistsAndUpdatesDisplayedDetail() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let pastureID = UUID()
        let repository = PastureDetailEditProbe(pastureID: pastureID)
        let model = loadedEditor(pastureID: pastureID, repository: repository, selection: selection)

        model.save(
            pastureID: pastureID,
            using: repository,
            expectedHerdID: originalHerdID,
            expectedSelectionRevision: selection.selectionRevision,
            selection: selection
        )

        XCTAssertEqual(repository.updatedIDs, [pastureID])
        XCTAssertEqual(repository.updatedInputs.map(\.name), ["Renamed pasture"])
        XCTAssertEqual(model.detail?.name, "Renamed pasture")
        XCTAssertFalse(model.isEditing)
        XCTAssertNil(model.errorMessage)
    }

    private func loadedEditor(
        pastureID: UUID,
        repository: PastureDetailEditProbe,
        selection: AppCurrentHerdSelection
    ) -> PastureDetailViewModel {
        let model = PastureDetailViewModel()
        XCTAssertTrue(model.load(
            pastureID: pastureID, using: repository,
            expectedHerdID: selection.currentHerdID,
            expectedSelectionRevision: selection.selectionRevision, selection: selection
        ))
        model.beginEditing(
            expectedHerdID: selection.currentHerdID,
            expectedSelectionRevision: selection.selectionRevision, selection: selection
        )
        model.form.name = "Renamed pasture"
        return model
    }
}

@MainActor
private final class PastureDetailEditProbe: PastureDetailEditingRepository {
    private var currentDetail: PastureDetailSnapshot
    private(set) var checkedNames: [String] = []
    private(set) var updatedIDs: [UUID] = []
    private(set) var updatedInputs: [PastureInput] = []

    init(pastureID: UUID) {
        currentDetail = PastureTestSupport.makeDetail(id: pastureID, name: "Original pasture")
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        id == currentDetail.id ? currentDetail : nil
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        []
    }

    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        checkedNames.append(name)
        return false
    }

    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot {
        updatedIDs.append(id)
        updatedInputs.append(input)
        currentDetail = PastureTestSupport.makeDetail(id: id, name: input.name)
        return currentDetail
    }
}
