import XCTest
@testable import yaHerd

@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testRestorationRoundTripPreservesValidatedDurableRoutesAndActiveSession() throws {
        let herdID = UUID()
        let animalID = UUID()
        let searchAnimalID = UUID()
        let sessionID = UUID()
        let findingID = UUID()
        let navigation = AppNavigationState()

        navigation.selectedHerdID = herdID
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
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(
                currentHerdID: herdID,
                animalIDs: [animalID, searchAnimalID],
                activeFieldCheckSessionIDs: [sessionID]
            )
        )

        XCTAssertEqual(restored.selectedHerdID, herdID)
        XCTAssertEqual(restored.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(restored.herdRouter.searchPath, [.animal(searchAnimalID)])
        XCTAssertEqual(restored.fullScreenWorkflow, .fieldCheck)
        guard case .fieldCheckSession(let restoredRoute) = restored.workflowRouter.route else {
            return XCTFail("Expected restored field-check session route")
        }
        XCTAssertEqual(restoredRoute.sessionID, sessionID)
        XCTAssertFalse(restoredRoute.opensFindings)
        XCTAssertNil(restoredRoute.focusedFindingID)
    }

    func testRestorationDoesNotPreserveTransientSheet() throws {
        let herdID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.present(.addAnimal)

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.present(.settings)
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(currentHerdID: herdID)
        )

        XCTAssertNil(restored.presentedSheet)
        XCTAssertNil(restored.fullScreenWorkflow)
        XCTAssertNil(restored.workflowRouter.route)
    }

    func testGenericWorkflowPresentationIsNotRestored() throws {
        let herdID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.openWorkArea(.sessions)

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(currentHerdID: herdID)
        )

        XCTAssertNil(restored.fullScreenWorkflow)
        XCTAssertNil(restored.workflowRouter.route)
    }

    func testMissingAnimalAndPastureRoutesFallBackToTheirLists() throws {
        let herdID = UUID()
        let validAnimalID = UUID()
        let missingPastureID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.selectedTab = .herd
        navigation.herdRouter.mode = .animals
        navigation.herdRouter.path = [.animal(validAnimalID), .pasture(missingPastureID)]
        navigation.herdRouter.searchPath = [.pasture(missingPastureID)]

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(
                currentHerdID: herdID,
                animalIDs: [validAnimalID]
            )
        )

        XCTAssertEqual(restored.herdRouter.path, [.animal(validAnimalID)])
        XCTAssertTrue(restored.herdRouter.searchPath.isEmpty)
    }

    func testDeletedOrCompletedWorkingSessionFallsBackToWorkingSessionList() throws {
        let herdID = UUID()
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.openWorkArea(.session(sessionID))

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(currentHerdID: herdID)
        )

        XCTAssertEqual(restored.selectedTab, .herd)
        XCTAssertEqual(restored.herdRouter.path, [.workingSessions])
        XCTAssertNil(restored.fullScreenWorkflow)
        XCTAssertNil(restored.workflowRouter.route)
    }

    func testDeletedOrCompletedFieldCheckFallsBackToFieldCheckList() throws {
        let herdID = UUID()
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.openFieldCheckArea(
            .session(FieldCheckSessionLaunchConfiguration(sessionID: sessionID))
        )

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(currentHerdID: herdID)
        )

        XCTAssertEqual(restored.selectedTab, .herd)
        XCTAssertEqual(restored.herdRouter.path, [.fieldChecks(.all)])
        XCTAssertNil(restored.fullScreenWorkflow)
        XCTAssertNil(restored.workflowRouter.route)
    }

    func testSnapshotFromDifferentHerdDoesNotRestoreRecordTargets() throws {
        let previousHerdID = UUID()
        let currentHerdID = UUID()
        let animalID = UUID()
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = previousHerdID
        navigation.herdRouter.path = [.animal(animalID)]
        navigation.openWorkArea(.session(sessionID))

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(
                currentHerdID: currentHerdID,
                animalIDs: [animalID],
                activeWorkingSessionIDs: [sessionID]
            )
        )

        XCTAssertEqual(restored.selectedHerdID, currentHerdID)
        XCTAssertTrue(restored.herdRouter.path.isEmpty)
        XCTAssertTrue(restored.herdRouter.searchPath.isEmpty)
        XCTAssertNil(restored.fullScreenWorkflow)
        XCTAssertNil(restored.workflowRouter.route)
    }

    func testVersionOnePayloadDropsSheetAndValidatesPersistedSession() throws {
        let herdID = UUID()
        let sessionID = UUID()
        let legacySnapshot = LegacyAppNavigationSnapshot(
            selectedTab: .home,
            herdRouter: AppNavigationState().herdRouter.snapshot,
            workflowRouter: LegacyWorkflowRouterSnapshot(
                route: .workingSession(sessionID)
            ),
            presentedSheet: .settings,
            fullScreenWorkflow: .workingSession
        )
        let data = try JSONEncoder().encode(legacySnapshot)
        let payload = data.base64EncodedString()
        let restored = AppNavigationState()

        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(
                currentHerdID: herdID,
                activeWorkingSessionIDs: [sessionID]
            )
        )

        XCTAssertNil(restored.presentedSheet)
        XCTAssertEqual(restored.fullScreenWorkflow, .workingSession)
        XCTAssertEqual(restored.workflowRouter.route, .workingSession(sessionID))
    }

    func testAnimalDeepLinkSelectsHerdTabAndTypedAnimalRoute() {
        let animalID = UUID()
        let navigation = AppNavigationState()

        XCTAssertTrue(navigation.handle(url: URL(string: "yaherd://animal/\(animalID.uuidString)")!))
        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(navigation.herdRouter.mode, .animals)
    }

    func testFindingDeepLinkPreservesSpecificFindingEditorIntentForCurrentLaunch() {
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

    func testSearchTabRestorationPreservesValidatedSearchStateAndPath() throws {
        let herdID = UUID()
        let animalID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.openSearch(query: "green 14")
        navigation.herdRouter.searchPath = [.animal(animalID)]

        let payload = try XCTUnwrap(navigation.restorationPayload())
        let restored = AppNavigationState()
        restored.restore(
            from: payload,
            using: TestNavigationRestorationValidator(
                currentHerdID: herdID,
                animalIDs: [animalID]
            )
        )

        XCTAssertEqual(restored.selectedTab, .search)
        XCTAssertEqual(restored.herdRouter.mode, .animals)
        XCTAssertEqual(restored.herdRouter.searchText, "green 14")
        XCTAssertTrue(restored.herdRouter.isSearchPresented)
        XCTAssertEqual(restored.herdRouter.searchPath, [.animal(animalID)])
    }

    func testInvalidRestorationPayloadLeavesDefaultStateAndClearsTransientPresentation() {
        let navigation = AppNavigationState()
        navigation.present(.settings)
        navigation.openWorkArea(.sessions)

        navigation.restore(
            from: "not-base64",
            using: TestNavigationRestorationValidator(currentHerdID: UUID())
        )

        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertTrue(navigation.herdRouter.searchPath.isEmpty)
        XCTAssertNil(navigation.presentedSheet)
        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.workflowRouter.route)
    }
}

@MainActor
private struct TestNavigationRestorationValidator: AppNavigationRestorationValidating {
    var herdID: UUID?
    var animalIDs: Set<UUID>
    var pastureIDs: Set<UUID>
    var activeFieldCheckSessionIDs: Set<UUID>
    var activeWorkingSessionIDs: Set<UUID>

    init(
        currentHerdID: UUID?,
        animalIDs: Set<UUID> = [],
        pastureIDs: Set<UUID> = [],
        activeFieldCheckSessionIDs: Set<UUID> = [],
        activeWorkingSessionIDs: Set<UUID> = []
    ) {
        self.herdID = currentHerdID
        self.animalIDs = animalIDs
        self.pastureIDs = pastureIDs
        self.activeFieldCheckSessionIDs = activeFieldCheckSessionIDs
        self.activeWorkingSessionIDs = activeWorkingSessionIDs
    }

    func currentHerdID() throws -> UUID? {
        herdID
    }

    func animalExists(id: UUID) throws -> Bool {
        animalIDs.contains(id)
    }

    func pastureExists(id: UUID) throws -> Bool {
        pastureIDs.contains(id)
    }

    func isActiveFieldCheckSession(id: UUID) throws -> Bool {
        activeFieldCheckSessionIDs.contains(id)
    }

    func isActiveWorkingSession(id: UUID) throws -> Bool {
        activeWorkingSessionIDs.contains(id)
    }
}

private struct LegacyAppNavigationSnapshot: Codable {
    var version = 1
    var selectedTab: AppTab
    var herdRouter: HerdRouterSnapshot
    var workflowRouter: LegacyWorkflowRouterSnapshot
    var presentedSheet: AppPresentedSheet?
    var fullScreenWorkflow: AppFullScreenWorkflow?
}

private struct LegacyWorkflowRouterSnapshot: Codable {
    var route: WorkflowRoute?
}
