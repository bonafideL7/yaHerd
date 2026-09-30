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
        XCTAssertEqual(store.formattedTag(tagNumber: "42", colorID: historical.id), "HT42")
        XCTAssertEqual(repository.fetchColorIDs, [historical.id])
    }
}

@MainActor
private final class HistoricalLookupTagColorRepository: TagColorRepository {
    private let visibleColors: [TagColorSnapshot]
    private let historicalColorsByID: [UUID: TagColorSnapshot]
    private(set) var fetchColorIDs: [UUID] = []

    init(
        visibleColors: [TagColorSnapshot],
        historicalColorsByID: [UUID: TagColorSnapshot]
    ) {
        self.visibleColors = visibleColors
        self.historicalColorsByID = historicalColorsByID
    }

    func fetchColors() throws -> [TagColorSnapshot] {
        visibleColors
    }

    func fetchColor(id: UUID) throws -> TagColorSnapshot? {
        fetchColorIDs.append(id)
        return visibleColors.first { $0.id == id } ?? historicalColorsByID[id]
    }

    func upsert(_ color: TagColorSnapshot) throws {}
    func setDefaultColor(id: UUID) throws {}
    func deleteColors(ids: [UUID]) throws {}
    func reorder(colorIDs: [UUID]) throws {}
    func restoreDefaultColors() throws {}
}
