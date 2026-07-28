import XCTest
@testable import yaHerd

@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testRestorationRoundTripPreservesTypedRoutesAndWorkflow() throws {
        let animalID = UUID()
        let sessionID = UUID()
        let findingID = UUID()
        let navigation = AppNavigationState()

        navigation.selectedTab = .herd
        navigation.herdRouter.showAnimals(
            AnimalListLaunchConfiguration(
                searchText: "W345",
                sortOrder: .pasture,
                filter: AnimalFilter(recordIssue: .missingTag),
                showRemovedStatuses: true,
                showArchivedRecords: false
            )
        )
        navigation.herdRouter.path = [.animal(animalID)]
        navigation.handle(.openFinding(sessionID: sessionID, findingID: findingID))

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(from: payload)

        XCTAssertEqual(restored.snapshot, navigation.snapshot)
        XCTAssertEqual(restored.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(restored.fullScreenWorkflow, .fieldCheck)
        guard case .fieldCheckSession(let restoredRoute) = restored.workflowRouter.route else {
            return XCTFail("Expected restored field-check session route")
        }
        XCTAssertEqual(restoredRoute.sessionID, sessionID)
        XCTAssertEqual(restoredRoute.focusedFindingID, findingID)
    }

    func testAnimalDeepLinkSelectsHerdTabAndTypedAnimalRoute() {
        let animalID = UUID()
        let navigation = AppNavigationState()

        XCTAssertTrue(navigation.handle(url: URL(string: "yaherd://animal/\(animalID.uuidString)")!))
        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(navigation.herdRouter.mode, .animals)
    }

    func testFindingDeepLinkRestoresSpecificFindingEditorIntent() {
        let sessionID = UUID()
        let findingID = UUID()
        let navigation = AppNavigationState()

        XCTAssertTrue(
            navigation.handle(
                url: URL(
                    string: "yaherd://field-check/\(sessionID.uuidString)?finding=\(findingID.uuidString)"
                )!
            )
        )

        guard case .fieldCheckSession(let route) = navigation.workflowRouter.route else {
            return XCTFail("Expected a field-check session route")
        }
        XCTAssertEqual(route.sessionID, sessionID)
        XCTAssertEqual(route.focusedFindingID, findingID)
        XCTAssertTrue(route.opensFindings)
        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
    }

    func testSearchSelectsSearchTabAndUsesHerdHierarchy() {
        let navigation = AppNavigationState()
        navigation.herdRouter.path = [.pasture(UUID())]

        navigation.handle(.searchAnimals("blue 01"))

        XCTAssertEqual(navigation.selectedTab, .search)
        XCTAssertEqual(navigation.herdRouter.mode, .animals)
        XCTAssertEqual(navigation.herdRouter.searchText, "blue 01")
        XCTAssertTrue(navigation.herdRouter.isSearchPresented)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
    }

    func testSearchTabRestorationPreservesSearchState() throws {
        let navigation = AppNavigationState()
        navigation.openSearch(query: "green 14")

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(from: payload)

        XCTAssertEqual(restored.selectedTab, .search)
        XCTAssertEqual(restored.herdRouter.mode, .animals)
        XCTAssertEqual(restored.herdRouter.searchText, "green 14")
        XCTAssertTrue(restored.herdRouter.isSearchPresented)
    }

    func testInvalidRestorationPayloadLeavesDefaultStateUnchanged() {
        let navigation = AppNavigationState()
        navigation.restore(from: "not-base64")

        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertNil(navigation.presentedSheet)
        XCTAssertNil(navigation.fullScreenWorkflow)
    }
}
