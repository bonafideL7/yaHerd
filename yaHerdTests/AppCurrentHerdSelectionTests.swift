import CoreData
import XCTest
@testable import yaHerd

@MainActor
final class AppCurrentHerdSelectionTests: XCTestCase {
    func testValidatedSwitchChangesRepositoryScopeAndClearsOtherHerdNavigation() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let first = try await repository.createOwnedHerd(named: "North")
        let second = try await repository.createOwnedHerd(named: "South")
        selection.select(first.id)

        let navigation = AppNavigationState()
        navigation.selectedHerdID = first.id
        navigation.herdRouter.path = [.animal(UUID())]
        navigation.herdRouter.searchText = "North"
        navigation.openWorkArea(.session(UUID()))
        navigation.present(.settings)

        let chosen = try selection.selectAccessibleHerd(
            second.id, using: repository, navigation: navigation
        )

        XCTAssertEqual(chosen, second)
        XCTAssertEqual(selection.currentHerdID, second.id)
        XCTAssertEqual(try repository.fetchCurrentHerd().id, second.id)
        XCTAssertEqual(navigation.selectedHerdID, second.id)
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertEqual(navigation.herdRouter.searchText, "")
        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.presentedSheet)
    }

    func testMissingHerdDoesNotChangeSelectionOrNavigation() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let existing = try await repository.createOwnedHerd(named: "Original")
        selection.select(existing.id)
        let navigation = AppNavigationState()
        navigation.selectedHerdID = existing.id
        navigation.herdRouter.path = [.animal(UUID())]
        let priorSnapshot = navigation.snapshot

        XCTAssertThrowsError(
            try selection.selectAccessibleHerd(
                UUID(), using: repository, navigation: navigation
            )
        ) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .missingHerd)
        }

        XCTAssertEqual(selection.currentHerdID, existing.id)
        XCTAssertEqual(navigation.snapshot, priorSnapshot)
        XCTAssertEqual(try repository.fetchCurrentHerd(), existing)
    }

    func testDiscoveryFailureRetainsCurrentHerdAndNavigation() {
        let current = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: current)
        let repository = FailingSelectionHerdRepository()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = current
        navigation.herdRouter.searchText = "current"
        let priorSnapshot = navigation.snapshot

        XCTAssertThrowsError(
            try selection.selectAccessibleHerd(
                UUID(), using: repository, navigation: navigation
            )
        ) { error in
            XCTAssertTrue(error is FailingSelectionHerdRepository.ReadError)
        }

        XCTAssertEqual(selection.currentHerdID, current)
        XCTAssertEqual(navigation.snapshot, priorSnapshot)
    }
}

@MainActor
private final class FailingSelectionHerdRepository: HerdRepository {
    enum ReadError: Error { case temporarilyUnavailable }

    func fetchCurrentHerd() throws -> HerdSummary {
        throw ReadError.temporarilyUnavailable
    }

    func fetchAccessibleHerds() throws -> [AccessibleHerd] {
        throw ReadError.temporarilyUnavailable
    }

    func createOwnedHerd(named name: String) async throws -> HerdSummary {
        throw ReadError.temporarilyUnavailable
    }

    func renameCurrentHerd(to name: String) async throws -> HerdSummary {
        throw ReadError.temporarilyUnavailable
    }
}
