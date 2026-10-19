import XCTest
@testable import yaHerd

@MainActor
final class PastureTilePickerViewModelTests: XCTestCase {
    func testLoadPopulatesPasturesAndRecentPasturesFromStoredIDs() {
        let north = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let south = PastureTestSupport.makeSummary(id: UUID(), name: "South")
        let repository = PastureListReaderStub(result: .success([north, south]))
        let viewModel = PastureTilePickerViewModel()

        let migrationValue = viewModel.load(
            using: repository,
            recentPastureIDs: [south.id],
            legacyRecentPastureNames: []
        )

        XCTAssertNil(migrationValue)
        XCTAssertEqual(viewModel.pastures, [north, south])
        XCTAssertEqual(viewModel.recentPastures, [south])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadMigratesLegacyRecentNamesToIDs() {
        let north = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let south = PastureTestSupport.makeSummary(id: UUID(), name: "South")
        let repository = PastureListReaderStub(result: .success([north, south]))
        let viewModel = PastureTilePickerViewModel()

        let migrationValue = viewModel.load(
            using: repository,
            recentPastureIDs: [],
            legacyRecentPastureNames: ["South", "North", "Unknown"]
        )

        XCTAssertEqual(migrationValue, [south.id, north.id])
        XCTAssertEqual(viewModel.recentPastures, [south, north])
    }

    func testSelectStoresMostRecentFirstAndLimitsToFour() {
        let first = PastureTestSupport.makeSummary(id: UUID(), name: "First")
        let second = PastureTestSupport.makeSummary(id: UUID(), name: "Second")
        let third = PastureTestSupport.makeSummary(id: UUID(), name: "Third")
        let fourth = PastureTestSupport.makeSummary(id: UUID(), name: "Fourth")
        let fifth = PastureTestSupport.makeSummary(id: UUID(), name: "Fifth")
        let repository = PastureListReaderStub(result: .success([first, second, third, fourth, fifth]))
        let viewModel = PastureTilePickerViewModel()
        _ = viewModel.load(using: repository, recentPastureIDs: [], legacyRecentPastureNames: [])

        _ = viewModel.select(first)
        _ = viewModel.select(second)
        _ = viewModel.select(third)
        _ = viewModel.select(fourth)
        let encoded = viewModel.select(fifth)

        XCTAssertEqual(viewModel.recentPastures, [fifth, fourth, third, second])
        XCTAssertEqual(encoded, [fifth.id, fourth.id, third.id, second.id])
    }

    func testSelectingExistingRecentPastureMovesItToFrontWithoutDuplicating() {
        let north = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let south = PastureTestSupport.makeSummary(id: UUID(), name: "South")
        let repository = PastureListReaderStub(result: .success([north, south]))
        let viewModel = PastureTilePickerViewModel()
        _ = viewModel.load(
            using: repository,
            recentPastureIDs: [north.id, south.id],
            legacyRecentPastureNames: []
        )

        let encoded = viewModel.select(south)

        XCTAssertEqual(viewModel.recentPastures, [south, north])
        XCTAssertEqual(encoded, [south.id, north.id])
    }

    func testLoadFailureClearsPasturesAndSetsErrorMessage() {
        let repository = PastureListReaderStub(result: .failure(PastureTestError.forced))
        let viewModel = PastureTilePickerViewModel()

        let migrationValue = viewModel.load(
            using: repository,
            recentPastureIDs: [UUID()],
            legacyRecentPastureNames: ["North"]
        )

        XCTAssertNil(migrationValue)
        XCTAssertTrue(viewModel.pastures.isEmpty)
        XCTAssertTrue(viewModel.recentPastures.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Forced test error.")
    }
}
