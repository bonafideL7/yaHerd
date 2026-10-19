import Foundation
import XCTest
@testable import yaHerd

final class AppNavigationIdentityRevalidationTests: XCTestCase {
    @MainActor
    func testCurrentHerdReadFailurePreservesIdentityBoundState() {
        let herdID = UUID()
        let animalID = UUID()
        let pastureID = UUID()
        let workingSessionID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.herdRouter.path = [.animal(animalID)]
        navigation.herdRouter.searchPath = [.pasture(pastureID)]
        navigation.herdRouter.filter.pasture = .pasture(pastureID)
        navigation.openWorkArea(.session(workingSessionID))

        let validator = StubNavigationValidator(currentHerdResult: .failure(.readFailed))

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.selectedHerdID, herdID)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(navigation.herdRouter.searchPath, [.pasture(pastureID)])
        XCTAssertEqual(navigation.herdRouter.filter.pasture, .pasture(pastureID))
        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        guard case .workingSession(let restoredSessionID) = navigation.workflowRouter.route else {
            return XCTFail("Expected working session presentation to be preserved")
        }
        XCTAssertEqual(restoredSessionID, workingSessionID)
    }

    @MainActor
    func testConfirmedMissingHerdClearsIdentityBoundState() {
        let animalID = UUID()
        let pastureID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = UUID()
        navigation.herdRouter.path = [.animal(animalID)]
        navigation.herdRouter.searchPath = [.pasture(pastureID)]
        navigation.herdRouter.filter.pasture = .pasture(pastureID)

        let validator = StubNavigationValidator(currentHerdResult: .success(nil))

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertNil(navigation.selectedHerdID)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertTrue(navigation.herdRouter.searchPath.isEmpty)
        XCTAssertEqual(navigation.herdRouter.filter.pasture, .any)
    }

    @MainActor
    func testEntityReadFailuresPreserveRoutesPastureFilterAndPriorHerdIdentity() {
        let selectedHerdID = UUID()
        let refreshedHerdID = UUID()
        let animalID = UUID()
        let pastureID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = selectedHerdID
        navigation.herdRouter.path = [.animal(animalID)]
        navigation.herdRouter.searchPath = [.pasture(pastureID)]
        navigation.herdRouter.filter.pasture = .pasture(pastureID)

        let validator = StubNavigationValidator(
            currentHerdResult: .success(refreshedHerdID),
            animalResult: .failure(.readFailed),
            pastureResult: .failure(.readFailed)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.selectedHerdID, selectedHerdID)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(navigation.herdRouter.searchPath, [.pasture(pastureID)])
        XCTAssertEqual(navigation.herdRouter.filter.pasture, .pasture(pastureID))
    }

    @MainActor
    func testLaterReadFailurePreservesEarlierConfirmedMissingRoute() {
        let selectedHerdID = UUID()
        let refreshedHerdID = UUID()
        let animalID = UUID()
        let pastureID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = selectedHerdID
        navigation.herdRouter.path = [.animal(animalID)]
        navigation.herdRouter.searchPath = [.pasture(pastureID)]

        let validator = StubNavigationValidator(
            currentHerdResult: .success(refreshedHerdID),
            animalResult: .success(false),
            pastureResult: .failure(.readFailed)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.selectedHerdID, selectedHerdID)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(navigation.herdRouter.searchPath, [.pasture(pastureID)])
    }

    @MainActor
    func testConfirmedMissingEntitiesRemoveRoutesAndPastureFilter() {
        let herdID = UUID()
        let animalID = UUID()
        let pastureID = UUID()
        let navigation = AppNavigationState()
        navigation.herdRouter.path = [.animal(animalID)]
        navigation.herdRouter.searchPath = [.pasture(pastureID)]
        navigation.herdRouter.filter.pasture = .pasture(pastureID)

        let validator = StubNavigationValidator(
            currentHerdResult: .success(herdID),
            animalResult: .success(false),
            pastureResult: .success(false)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.selectedHerdID, herdID)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertTrue(navigation.herdRouter.searchPath.isEmpty)
        XCTAssertEqual(navigation.herdRouter.filter.pasture, .any)
    }

    @MainActor
    func testWorkflowReadFailurePreservesPresentedSession() {
        let herdID = UUID()
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.openWorkArea(.session(sessionID))

        let validator = StubNavigationValidator(
            currentHerdResult: .success(herdID),
            workingSessionResult: .failure(.readFailed)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        guard case .workingSession(let restoredSessionID) = navigation.workflowRouter.route else {
            return XCTFail("Expected working session presentation to be preserved")
        }
        XCTAssertEqual(restoredSessionID, sessionID)
    }

    @MainActor
    func testFieldCheckSessionReadFailurePreservesPresentedSession() {
        let herdID = UUID()
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.openFieldCheckArea(
            .session(FieldCheckSessionLaunchConfiguration(sessionID: sessionID))
        )

        let validator = StubNavigationValidator(
            currentHerdResult: .success(herdID),
            fieldCheckSessionResult: .failure(.readFailed)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
        guard case .fieldCheckSession(let configuration) = navigation.workflowRouter.route else {
            return XCTFail("Expected field-check presentation to be preserved")
        }
        XCTAssertEqual(configuration.sessionID, sessionID)
    }

    @MainActor
    func testConfirmedMissingDirectWorkflowClosesToOrigin() {
        let herdID = UUID()
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.openWorkArea(.session(sessionID))

        let validator = StubNavigationValidator(
            currentHerdResult: .success(herdID),
            workingSessionResult: .success(false)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.workflowRouter.route)
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
    }

    @MainActor
    func testConfirmedMissingSessionOpenedFromWorkflowListReturnsToList() {
        let herdID = UUID()
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.openFieldCheckArea(.sessions(.flaggedAnimals))
        navigation.workflowRouter.openFieldCheckSession(
            FieldCheckSessionLaunchConfiguration(sessionID: sessionID)
        )

        let validator = StubNavigationValidator(
            currentHerdResult: .success(herdID),
            fieldCheckSessionResult: .success(false)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
        XCTAssertEqual(navigation.workflowRouter.route, .fieldCheckSessions(.flaggedAnimals))
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertFalse(navigation.workflowRouter.canReturnToList)
    }

    @MainActor
    func testCompletedWorkingSessionRemainsVisibleWhenStillPresent() {
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.openWorkArea(.session(sessionID))

        let validator = StubNavigationValidator(
            currentHerdResult: .success(UUID()),
            workingSessionResult: .success(false),
            workingSessionExistsResult: .success(true)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        XCTAssertEqual(navigation.workflowRouter.route, .workingSession(sessionID))
    }

    @MainActor
    func testCompletedFieldCheckWithFindingsRemainsVisibleWhenStillPresent() {
        let sessionID = UUID()
        let findingID = UUID()
        let navigation = AppNavigationState()
        navigation.openFieldCheckArea(
            .session(FieldCheckSessionLaunchConfiguration(
                sessionID: sessionID,
                opensFindings: true,
                focusedFindingID: findingID
            ))
        )

        let validator = StubNavigationValidator(
            currentHerdResult: .success(UUID()),
            fieldCheckSessionResult: .success(false),
            fieldCheckSessionExistsResult: .success(true),
            focusedFindingResult: .success(true)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
        XCTAssertEqual(navigation.selectedTab, .home)
        guard case .fieldCheckSession(let activeConfiguration) = navigation.workflowRouter.route else {
            return XCTFail("Existing completed check must remain in its workflow")
        }
        XCTAssertEqual(activeConfiguration.sessionID, sessionID)
        XCTAssertEqual(activeConfiguration.focusedFindingID, findingID)
    }

    @MainActor
    func testHistoricalSessionExistenceReadFailurePreservesCurrentWorkflow() {
        let sessionID = UUID()
        let navigation = AppNavigationState()
        navigation.openWorkArea(.session(sessionID))

        let validator = StubNavigationValidator(
            currentHerdResult: .success(UUID()),
            workingSessionResult: .success(false),
            workingSessionExistsResult: .failure(.readFailed)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        XCTAssertEqual(navigation.workflowRouter.route, .workingSession(sessionID))
        XCTAssertEqual(navigation.selectedTab, .home)
    }

    @MainActor
    func testFocusedFindingReadFailurePreservesFocusedFinding() {
        let herdID = UUID()
        let sessionID = UUID()
        let findingID = UUID()
        let navigation = AppNavigationState()
        navigation.openFieldCheckArea(
            .session(
                FieldCheckSessionLaunchConfiguration(
                    sessionID: sessionID,
                    opensFindings: true,
                    focusedFindingID: findingID
                )
            )
        )

        let validator = StubNavigationValidator(
            currentHerdResult: .success(herdID),
            fieldCheckSessionResult: .success(true),
            focusedFindingResult: .failure(.readFailed)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
        guard case .fieldCheckSession(let configuration) = navigation.workflowRouter.route else {
            return XCTFail("Expected field-check presentation to be preserved")
        }
        XCTAssertEqual(configuration.focusedFindingID, findingID)
    }

    @MainActor
    func testConfirmedMissingFocusedFindingClearsOnlyFocusedIdentity() {
        let herdID = UUID()
        let sessionID = UUID()
        let findingID = UUID()
        let navigation = AppNavigationState()
        navigation.openFieldCheckArea(
            .session(
                FieldCheckSessionLaunchConfiguration(
                    sessionID: sessionID,
                    opensFindings: true,
                    focusedFindingID: findingID
                )
            )
        )

        let validator = StubNavigationValidator(
            currentHerdResult: .success(herdID),
            fieldCheckSessionResult: .success(true),
            focusedFindingResult: .success(false)
        )

        navigation.revalidateIdentityBoundState(using: validator)

        XCTAssertEqual(navigation.fullScreenWorkflow, .fieldCheck)
        guard case .fieldCheckSession(let configuration) = navigation.workflowRouter.route else {
            return XCTFail("Expected field-check session to remain presented")
        }
        XCTAssertNil(configuration.focusedFindingID)
        XCTAssertTrue(configuration.opensFindings)
    }
}

private enum StubNavigationValidationError: Error {
    case readFailed
}

@MainActor
private final class StubNavigationValidator:
    AppNavigationRestorationValidating,
    FocusedFieldCheckFindingValidating
{
    var currentHerdResult: Result<UUID?, StubNavigationValidationError>
    var animalResult: Result<Bool, StubNavigationValidationError>
    var pastureResult: Result<Bool, StubNavigationValidationError>
    var fieldCheckSessionResult: Result<Bool, StubNavigationValidationError>
    var workingSessionResult: Result<Bool, StubNavigationValidationError>
    var fieldCheckSessionExistsResult: Result<Bool, StubNavigationValidationError>?
    var workingSessionExistsResult: Result<Bool, StubNavigationValidationError>?
    var focusedFindingResult: Result<Bool, StubNavigationValidationError>

    init(
        currentHerdResult: Result<UUID?, StubNavigationValidationError>,
        animalResult: Result<Bool, StubNavigationValidationError> = .success(true),
        pastureResult: Result<Bool, StubNavigationValidationError> = .success(true),
        fieldCheckSessionResult: Result<Bool, StubNavigationValidationError> = .success(true),
        workingSessionResult: Result<Bool, StubNavigationValidationError> = .success(true),
        fieldCheckSessionExistsResult: Result<Bool, StubNavigationValidationError>? = nil,
        workingSessionExistsResult: Result<Bool, StubNavigationValidationError>? = nil,
        focusedFindingResult: Result<Bool, StubNavigationValidationError> = .success(true)
    ) {
        self.currentHerdResult = currentHerdResult
        self.animalResult = animalResult
        self.pastureResult = pastureResult
        self.fieldCheckSessionResult = fieldCheckSessionResult
        self.workingSessionResult = workingSessionResult
        self.fieldCheckSessionExistsResult = fieldCheckSessionExistsResult
        self.workingSessionExistsResult = workingSessionExistsResult
        self.focusedFindingResult = focusedFindingResult
    }

    func currentHerdID() throws -> UUID? {
        try currentHerdResult.get()
    }

    func animalExists(id: UUID) throws -> Bool {
        try animalResult.get()
    }

    func pastureExists(id: UUID) throws -> Bool {
        try pastureResult.get()
    }

    func isActiveFieldCheckSession(id: UUID) throws -> Bool {
        try fieldCheckSessionResult.get()
    }

    func isActiveWorkingSession(id: UUID) throws -> Bool {
        try workingSessionResult.get()
    }

    func fieldCheckSessionExists(id: UUID) throws -> Bool {
        try (fieldCheckSessionExistsResult ?? fieldCheckSessionResult).get()
    }

    func workingSessionExists(id: UUID) throws -> Bool {
        try (workingSessionExistsResult ?? workingSessionResult).get()
    }

    func fieldCheckFindingExists(sessionID: UUID, findingID: UUID) throws -> Bool {
        try focusedFindingResult.get()
    }
}
