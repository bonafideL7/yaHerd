import XCTest
@testable import yaHerd

@MainActor
final class AnimalQueryNavigationTests: XCTestCase {
    func testOpeningSearchPreservesCurrentAnimalListScreen() {
        let navigation = AppNavigationState()
        let pastureID = UUID()
        navigation.herdRouter.mode = .pastures
        navigation.herdRouter.path = [.pasture(pastureID)]

        navigation.openSearch(query: "W345")

        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.mode, .pastures)
        XCTAssertEqual(navigation.herdRouter.path, [.pasture(pastureID)])
        XCTAssertEqual(navigation.animalQuery.searchText, "W345")
        XCTAssertTrue(navigation.herdRouter.isSearchPresented)
    }

    func testPastureListLaunchPreservesAnimalCriteria() {
        let navigation = AppNavigationState()
        navigation.animalQuery.searchText = "W345"
        navigation.animalQuery.filter = AnimalFilter(sex: .female)
        navigation.animalQuery.sortOrder = .sex
        navigation.animalQuery.showRemovedStatuses = true
        navigation.animalQuery.showArchivedRecords = true

        navigation.openPastureList(.rotationReady)

        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.mode, .pastures)
        XCTAssertEqual(navigation.herdRouter.pastureFilter, .rotationReady)
        XCTAssertEqual(navigation.animalQuery.searchText, "W345")
        XCTAssertEqual(navigation.animalQuery.filter.sex, .female)
        XCTAssertTrue(navigation.animalQuery.showRemovedStatuses)
        XCTAssertTrue(navigation.animalQuery.showArchivedRecords)
        XCTAssertEqual(navigation.animalQuery.sortOrder, .sex)
    }

    func testDirectPastureLaunchPreservesAnimalCriteria() {
        let navigation = AppNavigationState()
        let pastureID = UUID()
        navigation.animalQuery.searchText = "W345"
        navigation.animalQuery.filter = AnimalFilter(sex: .female)
        navigation.animalQuery.sortOrder = .sex
        navigation.animalQuery.showRemovedStatuses = true
        navigation.animalQuery.showArchivedRecords = true

        navigation.openPasture(pastureID)

        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.mode, .pastures)
        XCTAssertEqual(navigation.herdRouter.path, [.pasture(pastureID)])
        XCTAssertEqual(navigation.animalQuery.searchText, "W345")
        XCTAssertEqual(navigation.animalQuery.filter.sex, .female)
        XCTAssertTrue(navigation.animalQuery.showRemovedStatuses)
        XCTAssertTrue(navigation.animalQuery.showArchivedRecords)
        XCTAssertEqual(navigation.animalQuery.sortOrder, .sex)
    }

    func testRestorationPreservesAnimalQueryCriteria() throws {
        let navigation = AppNavigationState()
        let pastureID = UUID()
        navigation.selectedTab = .herd
        navigation.herdRouter.mode = .pastures
        navigation.herdRouter.path = [.pasture(pastureID)]
        navigation.animalQuery.searchText = "white blaze"
        navigation.animalQuery.filter = AnimalFilter(
            sex: .female,
            animalType: .cow,
            status: .active,
            pasture: .pasture(pastureID),
            location: .pasture,
            recordIssue: .any
        )
        navigation.animalQuery.sortOrder = .birthDateOldest
        navigation.animalQuery.showRemovedStatuses = true
        navigation.animalQuery.showArchivedRecords = true

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(from: payload)

        XCTAssertEqual(restored.selectedTab, .herd)
        XCTAssertEqual(restored.herdRouter.mode, .pastures)
        XCTAssertEqual(restored.herdRouter.path, [.pasture(pastureID)])
        XCTAssertEqual(restored.animalQuery.searchText, "white blaze")
        XCTAssertEqual(restored.animalQuery.filter, navigation.animalQuery.filter)
        XCTAssertEqual(restored.animalQuery.sortOrder, .birthDateOldest)
        XCTAssertTrue(restored.animalQuery.showRemovedStatuses)
        XCTAssertTrue(restored.animalQuery.showArchivedRecords)
    }
}
