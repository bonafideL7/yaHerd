import XCTest
@testable import yaHerd

@MainActor
final class TagColorLibraryHistoricalLookupTests: XCTestCase {
    func testHistoricalDefinitionResolvesOutsideVisibleLibrary() {
        let visible = TagColorSnapshot(
            id: TagColorDefaults.whiteID,
            name: "White",
            prefix: "W",
            rgba: RGBAColor(r: 1, g: 1, b: 1),
            isDefault: true
        )
        let historical = TagColorSnapshot(
            id: UUID(),
            name: "Historical Teal",
            prefix: "HT",
            rgba: RGBAColor(r: 0.1, g: 0.6, b: 0.65)
        )
        let repository = HistoricalLookupTagColorRepository(
            visibleColors: [visible],
            historicalColorsByID: [historical.id: historical]
        )

        let store = TagColorLibraryStore(repository: repository)

        XCTAssertFalse(store.colors.contains { $0.id == historical.id })
        XCTAssertEqual(store.definition(for: historical.id), historical)
        XCTAssertEqual(store.resolvedDefinition(tagColorID: historical.id), historical)
        XCTAssertEqual(store.resolvedColorID(historical.id), historical.id)
        XCTAssertEqual(store.editableColorID(historical.id), historical.id)
        XCTAssertEqual(store.formattedTag(tagNumber: "42", colorID: historical.id), "HT42")
        XCTAssertEqual(repository.fetchColorIDs, [historical.id])
    }

    func testEditableColorIDPreservesExistingIdentityWhenHiddenLookupFails() throws {
        let white = TagColorSnapshot(
            id: TagColorDefaults.whiteID,
            name: "White",
            prefix: "W",
            rgba: RGBAColor(r: 1, g: 1, b: 1),
            isDefault: true
        )
        let explicitMissingColorID = UUID()
        let repository = HistoricalLookupTagColorRepository(
            visibleColors: [white],
            historicalColorsByID: [:],
            failingColorIDs: [explicitMissingColorID]
        )
        let store = TagColorLibraryStore(repository: repository)

        // Display fallback is still White when the physical color cannot be read.
        XCTAssertEqual(store.resolvedColorID(explicitMissingColorID), white.id)
        XCTAssertEqual(repository.fetchColorIDs, [explicitMissingColorID])

        // Editing and promoting an existing tag must not persist that fallback ID.
        XCTAssertEqual(store.editableColorID(explicitMissingColorID), explicitMissingColorID)
        XCTAssertEqual(repository.fetchColorIDs, [explicitMissingColorID],
                       "Selecting an existing edit UUID must not repeat a failing lookup.")

        XCTAssertEqual(store.editableColorID(nil), white.id,
                       "New tags with no selected color still inherit the default.")
        XCTAssertEqual(store.editableColorID(white.id), white.id,
                       "Explicitly choosing a visible color retains the selected UUID.")
        XCTAssertEqual(repository.fetchColorIDs, [explicitMissingColorID])
    }

    func testEditableColorIDPreservesUnknownIDWhenLookupReturnsNil() {
        let white = TagColorSnapshot(
            id: TagColorDefaults.whiteID,
            name: "White",
            prefix: "W",
            rgba: RGBAColor(r: 1, g: 1, b: 1),
            isDefault: true
        )
        let missingID = UUID()
        let repository = HistoricalLookupTagColorRepository(
            visibleColors: [white],
            historicalColorsByID: [:]
        )
        let store = TagColorLibraryStore(repository: repository)

        XCTAssertEqual(store.resolvedColorID(missingID), white.id)
        XCTAssertEqual(store.editableColorID(missingID), missingID)
        XCTAssertEqual(store.editableColorID(nil), white.id)
        XCTAssertEqual(repository.fetchColorIDs, [missingID],
                       "Editing a missing ID must preserve identity without another lookup.")
    }
}

@MainActor
private final class HistoricalLookupTagColorRepository: TagColorRepository {
    private let visibleColors: [TagColorSnapshot]
    private let historicalColorsByID: [UUID: TagColorSnapshot]
    private let failingColorIDs: Set<UUID>
    private(set) var fetchColorIDs: [UUID] = []

    init(
        visibleColors: [TagColorSnapshot],
        historicalColorsByID: [UUID: TagColorSnapshot],
        failingColorIDs: Set<UUID> = []
    ) {
        self.visibleColors = visibleColors
        self.historicalColorsByID = historicalColorsByID
        self.failingColorIDs = failingColorIDs
    }

    func fetchColors() throws -> [TagColorSnapshot] {
        visibleColors
    }

    func fetchColor(id: UUID) throws -> TagColorSnapshot? {
        fetchColorIDs.append(id)
        if failingColorIDs.contains(id) {
            throw HistoricalLookupFailure.unavailable
        }
        return visibleColors.first { $0.id == id } ?? historicalColorsByID[id]
    }

    func upsert(_ color: TagColorSnapshot) throws {}
    func setDefaultColor(id: UUID) throws {}
    func deleteColors(ids: [UUID]) throws {}
    func reorder(colorIDs: [UUID]) throws {}
    func restoreDefaultColors() throws {}
}

private enum HistoricalLookupFailure: Error {
    case unavailable
}
