import XCTest
@testable import yaHerd

@MainActor
final class AnimalQueryNavigationTests: XCTestCase {
    func testSelectingSearchTabPreservesPastureScope() {
        let navigation = AppNavigationState()
        navigation.herdRouter.mode = .pastures

        navigation.selectSearchTab()

        XCTAssertEqual(navigation.selectedTab, .search)
        XCTAssertEqual(navigation.herdRouter.mode, .pastures)
        XCTAssertTrue(navigation.herdRouter.isSearchPresented)
    }

    func testPastureListLaunchClearsStaleAnimalCriteria() {
        let navigation = AppNavigationState()
        navigation.animalQuery.searchText = "W345"
        navigation.animalQuery.filter = AnimalFilter(sex: .female)
        navigation.animalQuery.sortOrder = .sex
        navigation.animalQuery.showRemovedStatuses = true
        navigation.animalQuery.showArchivedRecords = true
        navigation.animalQuery.showingFilters = true
        navigation.herdRouter.isSearchPresented = true

        navigation.openPastureList(.rotationReady)

        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.mode, .pastures)
        XCTAssertEqual(navigation.herdRouter.pastureFilter, .rotationReady)
        XCTAssertEqual(navigation.animalQuery.searchText, "")
        XCTAssertNil(navigation.animalQuery.filter.sex)
        XCTAssertFalse(navigation.animalQuery.showRemovedStatuses)
        XCTAssertFalse(navigation.animalQuery.showArchivedRecords)
        XCTAssertFalse(navigation.animalQuery.showingFilters)
        XCTAssertFalse(navigation.herdRouter.isSearchPresented)
        XCTAssertEqual(navigation.animalQuery.sortOrder, .sex)
    }
}
