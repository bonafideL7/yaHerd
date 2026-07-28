import XCTest
@testable import yaHerd

@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testRestorationRoundTripPreservesTypedRoutesAndWorkflow() throws {
        let animalID = UUID()
        let searchAnimalID = UUID()
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
        navigation.herdRouter.searchPath = [.animal(searchAnimalID)]
        navigation.handle(.openFinding(sessionID: sessionID, findingID: findingID))

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(from: payload)

        XCTAssertEqual(restored.snapshot, navigation.snapshot)
        XCTAssertEqual(restored.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(restored.herdRouter.searchPath, [.animal(searchAnimalID)])
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

    func testSearchSelectsSearchTabWithoutChangingHerdNavigationStack() {
        let pastureID = UUID()
        let navigation = AppNavigationState()
        navigation.herdRouter.path = [.pasture(pastureID)]

        navigation.handle(.searchAnimals("blue 01"))

        XCTAssertEqual(navigation.selectedTab, .search)
        XCTAssertEqual(navigation.herdRouter.mode, .animals)
        XCTAssertEqual(navigation.herdRouter.searchText, "blue 01")
        XCTAssertTrue(navigation.herdRouter.isSearchPresented)
        XCTAssertEqual(navigation.herdRouter.path, [.pasture(pastureID)])
        XCTAssertTrue(navigation.herdRouter.searchPath.isEmpty)
    }

    func testOpeningSearchResultStaysInSearchTabAndUsesSeparateStack() {
        let herdAnimalID = UUID()
        let searchAnimalID = UUID()
        let navigation = AppNavigationState()
        navigation.herdRouter.path = [.animal(herdAnimalID)]
        navigation.selectSearchTab()

        navigation.herdRouter.openAnimal(searchAnimalID, in: .search)

        XCTAssertEqual(navigation.selectedTab, .search)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(herdAnimalID)])
        XCTAssertEqual(navigation.herdRouter.searchPath, [.animal(searchAnimalID)])
        XCTAssertTrue(navigation.herdRouter.isSearchPresented)
    }

    func testDismissingSearchClearsCriteriaAndReturnsToHerdTab() {
        let navigation = AppNavigationState()
        navigation.openSearch(query: "green 14")
        navigation.herdRouter.filter = AnimalFilter(recordIssue: .missingTag)
        navigation.herdRouter.showRemovedStatuses = true
        navigation.herdRouter.showArchivedRecords = true

        navigation.dismissSearch(clearCriteria: true)

        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.searchText, "")
        XCTAssertEqual(navigation.herdRouter.filter, AnimalFilter())
        XCTAssertFalse(navigation.herdRouter.showRemovedStatuses)
        XCTAssertFalse(navigation.herdRouter.showArchivedRecords)
        XCTAssertFalse(navigation.herdRouter.isSearchPresented)
    }

    func testSearchTabRestorationPreservesSearchStateAndPath() throws {
        let animalID = UUID()
        let navigation = AppNavigationState()
        navigation.openSearch(query: "green 14")
        navigation.herdRouter.searchPath = [.animal(animalID)]

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(from: payload)

        XCTAssertEqual(restored.selectedTab, .search)
        XCTAssertEqual(restored.herdRouter.mode, .animals)
        XCTAssertEqual(restored.herdRouter.searchText, "green 14")
        XCTAssertTrue(restored.herdRouter.isSearchPresented)
        XCTAssertEqual(restored.herdRouter.searchPath, [.animal(animalID)])
    }

    func testInvalidRestorationPayloadLeavesDefaultStateUnchanged() {
        let navigation = AppNavigationState()
        navigation.restore(from: "not-base64")

        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertTrue(navigation.herdRouter.searchPath.isEmpty)
        XCTAssertNil(navigation.presentedSheet)
        XCTAssertNil(navigation.fullScreenWorkflow)
    }
}
