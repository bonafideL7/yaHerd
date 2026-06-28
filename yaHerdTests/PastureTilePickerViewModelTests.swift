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
            recentPastureIDsRaw: south.id.uuidString,
            legacyRecentPastureNamesRaw: ""
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
            recentPastureIDsRaw: "",
            legacyRecentPastureNamesRaw: "South|North|Unknown"
        )

        XCTAssertEqual(migrationValue, "\(south.id.uuidString)|\(north.id.uuidString)")
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
        _ = viewModel.load(using: repository, recentPastureIDsRaw: "", legacyRecentPastureNamesRaw: "")

        _ = viewModel.select(first)
        _ = viewModel.select(second)
        _ = viewModel.select(third)
        _ = viewModel.select(fourth)
        let encoded = viewModel.select(fifth)

        XCTAssertEqual(viewModel.recentPastures, [fifth, fourth, third, second])
        XCTAssertEqual(
            encoded,
            [fifth.id, fourth.id, third.id, second.id]
                .map(\.uuidString)
                .joined(separator: "|")
        )
    }

    func testSelectingExistingRecentPastureMovesItToFrontWithoutDuplicating() {
        let north = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let south = PastureTestSupport.makeSummary(id: UUID(), name: "South")
        let repository = PastureListReaderStub(result: .success([north, south]))
        let viewModel = PastureTilePickerViewModel()
        _ = viewModel.load(
            using: repository,
            recentPastureIDsRaw: "\(north.id.uuidString)|\(south.id.uuidString)",
            legacyRecentPastureNamesRaw: ""
        )

        let encoded = viewModel.select(south)

        XCTAssertEqual(viewModel.recentPastures, [south, north])
        XCTAssertEqual(encoded, "\(south.id.uuidString)|\(north.id.uuidString)")
    }

    func testLoadFailureClearsPasturesAndSetsErrorMessage() {
        let repository = PastureListReaderStub(result: .failure(PastureTestError.forced))
        let viewModel = PastureTilePickerViewModel()

        let migrationValue = viewModel.load(
            using: repository,
            recentPastureIDsRaw: UUID().uuidString,
            legacyRecentPastureNamesRaw: "North"
        )

        XCTAssertNil(migrationValue)
        XCTAssertTrue(viewModel.pastures.isEmpty)
        XCTAssertTrue(viewModel.recentPastures.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Forced test error.")
    }
}
