import XCTest
@testable import yaHerd

@MainActor
final class AnimalEditorDraftTests: XCTestCase {
    func testHasChangesIsFalseForUnchangedActiveAnimalWithoutStatusDates() {
        let detail = makeDetailSnapshot(status: .active, saleDate: nil, deathDate: nil)

        let draft = AnimalEditorDraft(detail: detail)
        XCTAssertFalse(draft.hasChanges(comparedTo: detail))
    }

    func testHasChangesDetectsSaleDateOnlyWhenSold() {
        let soldDetail = makeDetailSnapshot(status: .sold, saleDate: Date(timeIntervalSince1970: 1_000), deathDate: nil)

        var draft = AnimalEditorDraft(detail: soldDetail)
        XCTAssertFalse(draft.hasChanges(comparedTo: soldDetail))

        draft.saleDate = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(draft.hasChanges(comparedTo: soldDetail))

        let activeDetail = makeDetailSnapshot(status: .active, saleDate: nil, deathDate: nil)
        draft = AnimalEditorDraft(detail: activeDetail)
        draft.saleDate = Date(timeIntervalSince1970: 5_000)
        XCTAssertFalse(draft.hasChanges(comparedTo: activeDetail))
    }

    private func makeDetailSnapshot(status: AnimalStatus, saleDate: Date?, deathDate: Date?) -> AnimalDetailSnapshot {
        AnimalDetailSnapshot(
            id: UUID(),
            name: "Bessie",
            displayTagNumber: "12",
            displayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            birthDate: .distantPast,
            status: status,
            pastureID: nil,
            pastureName: nil,
            sireID: nil,
            sire: nil,
            damID: nil,
            dam: nil,
            distinguishingFeatures: [],
            saleDate: saleDate,
            salePrice: nil,
            reasonSold: nil,
            deathDate: deathDate,
            causeOfDeath: nil,
            statusReferenceID: nil,
            statusReferenceName: nil,
            isArchived: false,
            archivedAt: nil,
            archiveReason: nil,
            activeTags: [],
            inactiveTags: [],
            location: .pasture,
            maternalOffspring: []
        )
    }
}


@MainActor
final class AnimalParentPickerViewModelTests: XCTestCase {
    func testParentChoicesPreserveSuggestedSexFallbackAndFormattedTagSearch() async {
        let bull = parentOption(tag: "B10", sex: .male)
        let cow = parentOption(tag: "C20", sex: .female)
        let reader = ParentOptionQueryProbe(items: [bull, cow])
        let model = AnimalParentPickerViewModel()

        await model.load(excluding: cow.id, using: reader)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.items.map(\.id), [bull.id, cow.id])
        XCTAssertEqual(
            model.filtered(suggestedSexes: [.male], formattedTag: { "#\($0.displayTagNumber)" }).map(\.id),
            [bull.id]
        )

        model.showAllSexes = true
        XCTAssertEqual(
            model.filtered(suggestedSexes: [.male], formattedTag: { "#\($0.displayTagNumber)" }).map(\.id),
            [bull.id, cow.id]
        )
        model.searchText = "#C20"
        XCTAssertEqual(
            model.filtered(suggestedSexes: [.male], formattedTag: { "#\($0.displayTagNumber)" }).map(\.id),
            [cow.id]
        )

        model.showAllSexes = false
        model.searchText = ""
        XCTAssertEqual(
            model.filtered(suggestedSexes: [.unknown], formattedTag: { $0.displayTagNumber }).count,
            2,
            "When no suggested-sex options exist, preserve the original Show All fallback."
        )
        let excluded = await reader.lastExcludedID()
        XCTAssertEqual(excluded, cow.id)
    }

    func testParentChoicesFailedRefreshNeverExposesStaleOptionsAndCanRetry() async {
        let option = parentOption(tag: "P01", sex: .male)
        let reader = ParentOptionQueryProbe(items: [option])
        let model = AnimalParentPickerViewModel()

        await model.load(excluding: nil, using: reader)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.items.map(\.id), [option.id])

        await reader.setFailure(true)
        await model.load(excluding: nil, using: reader)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(
            model.filtered(suggestedSexes: [.male], formattedTag: { $0.displayTagNumber }).isEmpty
        )

        await reader.setFailure(false)
        await model.load(excluding: nil, using: reader)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.items.map(\.id), [option.id])
    }

    func testOutdatedParentOptionRequestCannotOverwriteNewerRefresh() async {
        let oldOption = parentOption(tag: "OLD", sex: .male)
        let newOption = parentOption(tag: "NEW", sex: .female)
        let reader = ParentOptionQueryProbe(items: [newOption], initialPausedResult: [oldOption])
        let model = AnimalParentPickerViewModel()

        let older = Task { @MainActor in
            await model.load(excluding: nil, using: reader)
        }
        await reader.waitForFirstRequest()
        await model.load(excluding: nil, using: reader)
        XCTAssertEqual(model.items.map(\.id), [newOption.id])

        await reader.releaseFirstRequest()
        await older.value
        XCTAssertEqual(model.items.map(\.id), [newOption.id])
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
    }

    private func parentOption(tag: String, sex: Sex) -> AnimalParentOption {
        AnimalParentOption(
            id: UUID(),
            name: "Parent \(tag)",
            displayTagNumber: tag,
            displayTagColorID: nil,
            sex: sex,
            isArchived: false
        )
    }
}

private enum ParentOptionQueryProbeError: Error {
    case unavailable
}

private actor ParentOptionQueryProbe: AnimalParentOptionQueryReading {
    private let items: [AnimalParentOption]
    private let initialPausedResult: [AnimalParentOption]?
    private var shouldFail = false
    private var lastExcluded: UUID?
    private var requestCount = 0
    private var firstEntered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var firstContinuation: CheckedContinuation<Void, Never>?

    init(items: [AnimalParentOption], initialPausedResult: [AnimalParentOption]? = nil) {
        self.items = items
        self.initialPausedResult = initialPausedResult
    }

    func setFailure(_ value: Bool) { shouldFail = value }
    func lastExcludedID() -> UUID? { lastExcluded }

    func waitForFirstRequest() async {
        if firstEntered { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func releaseFirstRequest() {
        firstContinuation?.resume()
        firstContinuation = nil
    }

    func fetchParentOptions(excluding excludedAnimalID: UUID?) async throws -> [AnimalParentOption] {
        lastExcluded = excludedAnimalID
        requestCount += 1
        if requestCount == 1, let initialPausedResult {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
                firstEntered = true
                enteredContinuation?.resume()
                enteredContinuation = nil
            }
            return initialPausedResult
        }
        if shouldFail { throw ParentOptionQueryProbeError.unavailable }
        return items
    }
}
