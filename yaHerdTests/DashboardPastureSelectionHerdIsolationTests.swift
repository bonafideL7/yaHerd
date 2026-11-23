import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class DashboardPastureSelectionHerdIsolationTests: XCTestCase {
    func testPastureChartSelectionDoesNotCarryIntoAnotherHerd() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = DashboardViewModel()
        let reader = EmptyDashboardSelectionReader()

        let initialLoad = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )
        XCTAssertTrue(initialLoad)
        model.selectedPastureName = "North Pasture"

        selection.select(UUID())

        let nextLoad = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )
        XCTAssertTrue(nextLoad)
        XCTAssertNil(model.selectedPastureName,
                     "A new Herd must not inherit another Herd's selected chart row.")
    }

    func testReturningToSameHerdDoesNotReviveObsoleteChartSelection() async {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let model = DashboardViewModel()
        let reader = EmptyDashboardSelectionReader()

        _ = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )
        model.selectedPastureName = "North Pasture"

        selection.select(UUID())
        selection.select(originalHerdID)
        _ = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )

        XCTAssertNil(model.selectedPastureName,
                     "A new selection revision must invalidate an old chart interaction.")
    }

    func testRevokedSelectionClearsChartSelectionWithoutLoading() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = DashboardViewModel()
        let reader = EmptyDashboardSelectionReader()

        _ = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )
        model.selectedPastureName = "North Pasture"

        selection.select(nil)
        let loaded = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )

        XCTAssertFalse(loaded)
        XCTAssertNil(model.selectedPastureName)
    }

    func testReloadingSameHerdPreservesActiveChartInteraction() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = DashboardViewModel()
        let reader = EmptyDashboardSelectionReader()

        _ = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )
        model.selectedPastureName = "North Pasture"

        let reloaded = await model.load(
            configuration: DashboardConfiguration(),
            using: reader,
            selection: selection
        )

        XCTAssertTrue(reloaded)
        XCTAssertEqual(model.selectedPastureName, "North Pasture")
    }
}

private actor EmptyDashboardSelectionReader: DashboardQueryReading {
    func fetchDashboardRecords() async throws -> DashboardRecords {
        DashboardRecords(animals: [], pastures: [], workingSessions: [])
    }

    func fetchDashboardAnimalRecords(
        kind: DashboardAnimalListKind
    ) async throws -> [DashboardAnimalRecord] {
        []
    }

    func fetchDashboardPastureRecords() async throws -> [DashboardPastureRecord] {
        []
    }
}
