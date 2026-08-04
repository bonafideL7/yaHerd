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
}
