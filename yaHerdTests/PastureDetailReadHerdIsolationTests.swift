import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class PastureDetailReadHerdIsolationTests: XCTestCase {
    func testChangedHerdClearsDetailResidentsAndUnsavedDraftWithoutReadingNewStore() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let revision = selection.selectionRevision
        let pastureID = UUID()
        let repository = PastureDetailReadProbe(pastureID: pastureID)
        let model = PastureDetailViewModel()

        XCTAssertTrue(model.load(
            pastureID: pastureID, using: repository,
            expectedHerdID: herdID, expectedSelectionRevision: revision, selection: selection
        ))
        model.beginEditing(
            expectedHerdID: herdID, expectedSelectionRevision: revision, selection: selection
        )
        model.form.name = "Unsaved old-Herd name"
        XCTAssertEqual(model.residentAnimals.count, 1)

        selection.select(UUID())

        XCTAssertFalse(model.load(
            pastureID: pastureID, using: repository,
            expectedHerdID: herdID, expectedSelectionRevision: revision, selection: selection
        ))
        XCTAssertEqual(repository.detailFetches, 1)
        XCTAssertEqual(repository.residentFetches, 1)
        XCTAssertNil(model.detail)
        XCTAssertTrue(model.residentAnimals.isEmpty)
        XCTAssertFalse(model.isEditing)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.form.name, "")
    }

    func testReturningToSameHerdCannotReactivatePreviousPresentation() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let revision = selection.selectionRevision
        let pastureID = UUID()
        let repository = PastureDetailReadProbe(pastureID: pastureID)
        let model = PastureDetailViewModel()

        XCTAssertTrue(model.load(
            pastureID: pastureID, using: repository,
            expectedHerdID: herdID, expectedSelectionRevision: revision, selection: selection
        ))
        selection.select(UUID())
        selection.select(herdID)

        XCTAssertFalse(model.load(
            pastureID: pastureID, using: repository,
            expectedHerdID: herdID, expectedSelectionRevision: revision, selection: selection
        ))
        XCTAssertNil(model.detail)
        XCTAssertEqual(repository.detailFetches, 1)

        let newPresentation = PastureDetailViewModel()
        XCTAssertTrue(newPresentation.load(
            pastureID: pastureID, using: repository,
            expectedHerdID: herdID, expectedSelectionRevision: selection.selectionRevision,
            selection: selection
        ))
        XCTAssertEqual(repository.detailFetches, 2)
    }

    func testMissingSelectionDoesNotFetchPasture() {
        let selection = AppCurrentHerdSelection()
        let repository = PastureDetailReadProbe(pastureID: UUID())
        let model = PastureDetailViewModel()

        XCTAssertFalse(model.load(
            pastureID: UUID(), using: repository,
            expectedHerdID: nil, expectedSelectionRevision: selection.selectionRevision,
            selection: selection
        ))
        XCTAssertEqual(repository.detailFetches, 0)
        XCTAssertEqual(repository.residentFetches, 0)
    }

    func testCurrentHerdMutationObserverReloadsItsPasture() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let pastureID = UUID()
        let repository = PastureDetailReadProbe(pastureID: pastureID)
        let mutations = ApplicationMutationCenter()
        let model = PastureDetailViewModel()

        let observer = Task {
            await model.observe(
                pastureID: pastureID,
                using: repository,
                mutationStream: mutations,
                expectedHerdID: herdID,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        }
        defer { observer.cancel() }

        for _ in 0..<100 where repository.detailFetches == 0 {
            await Task.yield()
        }
        XCTAssertEqual(repository.detailFetches, 1)
        mutations.recordSuccessfulMutation(reason: .pasture)

        for _ in 0..<100 where repository.detailFetches < 2 {
            await Task.yield()
        }
        XCTAssertEqual(repository.detailFetches, 2)
        XCTAssertEqual(model.detail?.name, "Original Herd pasture")
    }

    func testObsoleteMutationObserverDoesNotFetchUnderNewHerd() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let revision = selection.selectionRevision
        let pastureID = UUID()
        let repository = PastureDetailReadProbe(pastureID: pastureID)
        let mutations = ApplicationMutationCenter()
        let model = PastureDetailViewModel()

        let observer = Task {
            await model.observe(
                pastureID: pastureID,
                using: repository,
                mutationStream: mutations,
                expectedHerdID: herdID,
                expectedSelectionRevision: revision,
                selection: selection
            )
        }
        defer { observer.cancel() }

        for _ in 0..<100 where repository.detailFetches == 0 {
            await Task.yield()
        }
        XCTAssertEqual(repository.detailFetches, 1)

        selection.select(UUID())
        mutations.recordSuccessfulMutation(reason: .pasture)
        for _ in 0..<100 {
            await Task.yield()
        }
        XCTAssertEqual(repository.detailFetches, 1)
        model.resetForHerdChange()
        XCTAssertNil(model.detail)
    }
}

@MainActor
private final class PastureDetailReadProbe: PastureDetailRepository {
    let pastureID: UUID
    private(set) var detailFetches = 0
    private(set) var residentFetches = 0

    init(pastureID: UUID) {
        self.pastureID = pastureID
    }

    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? {
        detailFetches += 1
        return id == pastureID
            ? PastureTestSupport.makeDetail(id: id, name: "Original Herd pasture")
            : nil
    }

    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] {
        residentFetches += 1
        return [PastureTestSupport.makeAnimalSummary()]
    }
}
