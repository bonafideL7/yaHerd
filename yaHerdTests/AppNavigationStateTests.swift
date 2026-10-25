import XCTest
@testable import yaHerd

@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testAnimalListAccessoryOnlyAppearsOnForegroundRootList() {
        let navigation = AppNavigationState()

        XCTAssertFalse(navigation.showsAnimalListAccessory)

        navigation.selectedTab = .herd
        XCTAssertTrue(navigation.showsAnimalListAccessory)

        navigation.herdRouter.openFieldChecks(.all)
        XCTAssertFalse(navigation.showsAnimalListAccessory)

        navigation.herdRouter.path = [.workingSessions]
        XCTAssertFalse(navigation.showsAnimalListAccessory)

        navigation.herdRouter.path = [.animal(UUID())]
        XCTAssertFalse(navigation.showsAnimalListAccessory)

        navigation.herdRouter.path = []
        XCTAssertTrue(navigation.showsAnimalListAccessory)

        navigation.herdRouter.mode = .pastures
        XCTAssertFalse(navigation.showsAnimalListAccessory)

        navigation.selectedTab = .search
        XCTAssertTrue(navigation.showsAnimalListAccessory)

        navigation.herdRouter.searchPath = [.fieldChecks(.openFindings)]
        XCTAssertFalse(navigation.showsAnimalListAccessory)

        navigation.herdRouter.searchPath = []
        XCTAssertTrue(navigation.showsAnimalListAccessory)

        navigation.selectedTab = .herd
        navigation.herdRouter.mode = .animals
        navigation.openFieldCheckArea(.sessions(.all))
        XCTAssertFalse(navigation.showsAnimalListAccessory)

        navigation.closeFullScreenWorkflow()
        XCTAssertTrue(navigation.showsAnimalListAccessory)
    }

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
        restored.restore(from: payload, using: RestorableTestNavigationValidator())

        XCTAssertEqual(restored.snapshot, navigation.snapshot)
        XCTAssertEqual(restored.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(restored.herdRouter.searchPath, [.animal(searchAnimalID)])
        XCTAssertEqual(restored.fullScreenWorkflow, .fieldCheck)
        guard case .fieldCheckSession(let restoredRoute) = restored.workflowRouter.route else {
            return XCTFail("Expected restored field-check session route")
        }
        XCTAssertEqual(restoredRoute.sessionID, sessionID)
        XCTAssertNil(restoredRoute.focusedFindingID, "Finding focus is transient; only the validated session identity is durable.")
    }

    func testAnimalDeepLinkSelectsHerdTabAndTypedAnimalRoute() {
        let animalID = UUID()
        let navigation = AppNavigationState()

        XCTAssertTrue(navigation.handle(url: URL(string: "yaherd://animal/\(animalID.uuidString)")!))
        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(navigation.herdRouter.mode, .animals)
    }

    func testRecordAndSearchDeepLinksDismissConflictingPresentations() {
        let navigation = AppNavigationState()
        let animalID = UUID()
        navigation.openWorkArea(.session(UUID()))
        navigation.handle(.openAnimal(animalID))

        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.workflowRouter.route)
        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])

        navigation.present(.settings)
        navigation.handle(.searchAnimals("W345"))

        XCTAssertNil(navigation.presentedSheet)
        XCTAssertEqual(navigation.selectedTab, .search)
        XCTAssertEqual(navigation.herdRouter.searchText, "W345")
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

    func testSelectingFieldCheckFilterReplacesExistingRouteAndRestoresSelectedMode() throws {
        let navigation = AppNavigationState()
        navigation.openFieldChecks(.inProgress)

        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
        XCTAssertEqual(navigation.workflowRouter.route, .fieldCheckSessions(.inProgress))

        // The Field Checks view binds its filter to the isolated workflow route,
        // not to the Herd tab's navigation stack.
        navigation.workflowRouter.route = .fieldCheckSessions(.openFindings)

        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertEqual(navigation.workflowRouter.route, .fieldCheckSessions(.openFindings))
        XCTAssertEqual(navigation.selectedTab, .home)

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(from: payload, using: RestorableTestNavigationValidator())

        XCTAssertTrue(restored.herdRouter.path.isEmpty)
        XCTAssertEqual(restored.fullScreenWorkflow, .fieldCheck)
        XCTAssertEqual(restored.workflowRouter.route, .fieldCheckSessions(.openFindings))
        XCTAssertEqual(restored.selectedTab, .home)
    }

    func testCheckFilterSelectionKeepsSearchAndHerdStacksIndependent() {
        let navigation = AppNavigationState()
        let animalID = UUID()
        navigation.herdRouter.path = [.fieldChecks(.inProgress)]
        navigation.herdRouter.searchPath = [.fieldChecks(.missingAnimals)]

        navigation.herdRouter.updateFieldCheckMode(.flaggedAnimals, in: .search)

        XCTAssertEqual(navigation.herdRouter.path, [.fieldChecks(.inProgress)])
        XCTAssertEqual(navigation.herdRouter.searchPath, [.fieldChecks(.flaggedAnimals)])

        navigation.herdRouter.searchPath = [.animal(animalID)]
        navigation.herdRouter.updateFieldCheckMode(.all, in: .search)

        XCTAssertEqual(navigation.herdRouter.searchPath, [.animal(animalID)])
        XCTAssertEqual(navigation.herdRouter.path, [.fieldChecks(.inProgress)])
    }

    func testSearchPreservesPastureModeAndIndependentHerdStack() throws {
        let pastureID = UUID()
        let searchAnimalID = UUID()
        let navigation = AppNavigationState()
        navigation.herdRouter.mode = .pastures
        navigation.herdRouter.path = [.pasture(pastureID)]

        navigation.selectSearchTab()
        XCTAssertEqual(navigation.selectedTab, .search)
        XCTAssertEqual(navigation.herdRouter.mode, .pastures)

        navigation.herdRouter.openAnimal(searchAnimalID, in: .search)
        XCTAssertEqual(navigation.herdRouter.mode, .pastures)
        XCTAssertEqual(navigation.herdRouter.path, [.pasture(pastureID)])
        XCTAssertEqual(navigation.herdRouter.searchPath, [.animal(searchAnimalID)])

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(from: payload, using: RestorableTestNavigationValidator())
        XCTAssertEqual(restored.herdRouter.mode, .pastures)
        XCTAssertEqual(restored.herdRouter.searchPath, [.animal(searchAnimalID)])
    }

    func testHomeFieldCheckShortcutRetainsHomeAndReturnsToSelectedFilter() {
        let navigation = AppNavigationState()
        let pastureID = UUID()
        let sessionID = UUID()
        navigation.herdRouter.path = [.pasture(pastureID)]

        navigation.openFieldChecks(.openFindings)
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
        XCTAssertEqual(navigation.workflowRouter.route, .fieldCheckSessions(.openFindings))
        XCTAssertEqual(navigation.herdRouter.path, [.pasture(pastureID)])

        navigation.workflowRouter.openFieldCheckSession(
            FieldCheckSessionLaunchConfiguration(sessionID: sessionID, opensFindings: true)
        )
        XCTAssertTrue(navigation.workflowRouter.canReturnToList)

        navigation.workflowRouter.returnToList()
        XCTAssertEqual(navigation.workflowRouter.route, .fieldCheckSessions(.openFindings))
        XCTAssertFalse(navigation.workflowRouter.canReturnToList)

        navigation.closeFullScreenWorkflow()
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.workflowRouter.route)
        XCTAssertEqual(navigation.herdRouter.path, [.pasture(pastureID)])
    }

    func testWorkingSessionListBackAndClosePreserveOrigin() {
        let navigation = AppNavigationState()
        navigation.selectedTab = .herd
        navigation.openWorkArea(.sessions)
        navigation.workflowRouter.openWorkingSession(UUID())
        XCTAssertTrue(navigation.workflowRouter.canReturnToList)

        navigation.workflowRouter.returnToList()
        XCTAssertEqual(navigation.workflowRouter.route, .workingSessions)
        navigation.closeFullScreenWorkflow()
        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertNil(navigation.fullScreenWorkflow)

        navigation.selectedTab = .home
        navigation.openWorkArea(.session(UUID()))
        XCTAssertFalse(navigation.workflowRouter.canReturnToList)
        navigation.closeFullScreenWorkflow()
        XCTAssertEqual(navigation.selectedTab, .home)
    }

    func testSuccessfulDeletionFromWorkingSessionListReturnsToList() {
        let navigation = AppNavigationState()
        let sessionID = UUID()
        navigation.selectedTab = .herd
        navigation.openWorkArea(.sessions)
        navigation.workflowRouter.openWorkingSession(sessionID)

        navigation.handleDeletedWorkingSession(sessionID)

        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        XCTAssertEqual(navigation.workflowRouter.route, .workingSessions)
        XCTAssertFalse(navigation.workflowRouter.canReturnToList)
    }

    func testSuccessfulDeletionFromDirectWorkingSessionClosesToOrigin() {
        let navigation = AppNavigationState()
        let sessionID = UUID()
        navigation.openWorkArea(.session(sessionID))

        navigation.handleDeletedWorkingSession(sessionID)

        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.workflowRouter.route)
    }

    func testStaleWorkingSessionDeletionCallbackDoesNotOverrideNavigation() {
        let navigation = AppNavigationState()
        let sessionID = UUID()
        navigation.openWorkArea(.sessions)
        navigation.workflowRouter.openWorkingSession(sessionID)

        // A callback for a different session must not dismiss or pop the current detail.
        navigation.handleDeletedWorkingSession(UUID())
        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        XCTAssertTrue(navigation.workflowRouter.canReturnToList)

        // Live deletion revalidation can return to the list before the delete task resumes.
        navigation.workflowRouter.returnToList()
        navigation.handleDeletedWorkingSession(sessionID)
        XCTAssertEqual(navigation.workflowRouter.route, .workingSessions)
        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)

        // Closing for an unrelated navigation action must not be undone by a late callback.
        navigation.closeFullScreenWorkflow()
        navigation.handleDeletedWorkingSession(sessionID)
        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.workflowRouter.route)
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
        restored.restore(from: payload, using: RestorableTestNavigationValidator())

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

@MainActor
private struct RestorableTestNavigationValidator: AppNavigationRestorationValidating {
    func currentHerdID() throws -> UUID? { nil }
    func animalExists(id: UUID) throws -> Bool { true }
    func pastureExists(id: UUID) throws -> Bool { true }
    func isActiveFieldCheckSession(id: UUID) throws -> Bool { true }
    func isActiveWorkingSession(id: UUID) throws -> Bool { true }
    func fieldCheckSessionExists(id: UUID) throws -> Bool { true }
    func workingSessionExists(id: UUID) throws -> Bool { true }
}
