import XCTest
@testable import yaHerd

@MainActor
final class PastureGroupNavigationRouteTests: XCTestCase {
    func testPastureGroupRouteIsPreservedByNavigationRestoration() throws {
        let navigation = AppNavigationState()
        navigation.selectedTab = .herd
        navigation.herdRouter.path = [.pastureGroups]

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restoredNavigation = AppNavigationState()
        restoredNavigation.restore(from: payload)

        XCTAssertEqual(restoredNavigation.selectedTab, .herd)
        XCTAssertEqual(restoredNavigation.herdRouter.path, [.pastureGroups])
    }
}
