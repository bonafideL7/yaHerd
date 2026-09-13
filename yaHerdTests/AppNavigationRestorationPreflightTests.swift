import Foundation
import XCTest
@testable import yaHerd

final class AppNavigationRestorationPreflightTests: XCTestCase {
    @MainActor
    func testCurrentHerdReadFailureDefersWithoutMutatingNavigation() {
        let herdID = UUID()
        let animalID = UUID()
        let payload = makePayload(herdID: herdID, animalID: animalID)
        let navigation = AppNavigationState()
        navigation.selectedTab = .dashboard
        navigation.herdRouter.mode = .pastures
        let before = navigation.snapshot

        let validator = PreflightStubNavigationValidator(
            currentHerdResult: .failure(.readFailed)
        )

        let outcome = navigation.restorePreservingStoredSnapshot(
            from: payload,
            using: validator
        )

        XCTAssertEqual(outcome, .deferredValidation)
        XCTAssertEqual(navigation.snapshot, before)
    }

    @MainActor
    func testEntityReadFailureDefersEntireRestoreWithoutPartialMutation() {
        let herdID = UUID()
        let animalID = UUID()
        let payload = makePayload(herdID: herdID, animalID: animalID)
        let navigation = AppNavigationState()
        navigation.selectedTab = .search
        let before = navigation.snapshot

        let validator = PreflightStubNavigationValidator(
            currentHerdResult: .success(herdID),
            animalResult: .failure(.readFailed)
        )

        let outcome = navigation.restorePreservingStoredSnapshot(
            from: payload,
            using: validator
        )

        XCTAssertEqual(outcome, .deferredValidation)
        XCTAssertEqual(navigation.snapshot, before)
    }

    @MainActor
    func testWorkflowReadFailureDefersEntireRestore() {
        let herdID = UUID()
        let sessionID = UUID()
        let payload = makePayload(herdID: herdID, workingSessionID: sessionID)
        let navigation = AppNavigationState()
        let before = navigation.snapshot

        let validator = PreflightStubNavigationValidator(
            currentHerdResult: .success(herdID),
            workingSessionResult: .failure(.readFailed)
        )

        let outcome = navigation.restorePreservingStoredSnapshot(
            from: payload,
            using: validator
        )

        XCTAssertEqual(outcome, .deferredValidation)
        XCTAssertEqual(navigation.snapshot, before)
        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertNil(navigation.workflowRouter.route)
    }

    @MainActor
    func testConfirmedMissingEntityAppliesSafeFallback() {
        let herdID = UUID()
        let animalID = UUID()
        let payload = makePayload(herdID: herdID, animalID: animalID)
        let navigation = AppNavigationState()
        let validator = PreflightStubNavigationValidator(
            currentHerdResult: .success(herdID),
            animalResult: .success(false)
        )

        let outcome = navigation.restorePreservingStoredSnapshot(
            from: payload,
            using: validator
        )

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(navigation.selectedHerdID, herdID)
        XCTAssertEqual(navigation.selectedTab, .herd)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
    }

    @MainActor
    func testSuccessfulPreflightRestoresDurableRouteAndWorkflow() {
        let herdID = UUID()
        let animalID = UUID()
        let sessionID = UUID()
        let payload = makePayload(
            herdID: herdID,
            animalID: animalID,
            workingSessionID: sessionID
        )
        let navigation = AppNavigationState()
        let validator = PreflightStubNavigationValidator(
            currentHerdResult: .success(herdID),
            animalResult: .success(true),
            workingSessionResult: .success(true)
        )

        let outcome = navigation.restorePreservingStoredSnapshot(
            from: payload,
            using: validator
        )

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(navigation.selectedHerdID, herdID)
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])
        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        guard case .workingSession(let restoredSessionID) = navigation.workflowRouter.route else {
            return XCTFail("Expected working session to be restored")
        }
        XCTAssertEqual(restoredSessionID, sessionID)
    }

    @MainActor
    private func makePayload(
        herdID: UUID,
        animalID: UUID? = nil,
        workingSessionID: UUID? = nil
    ) -> String {
        let source = AppNavigationState()
        source.selectedTab = .herd
        source.selectedHerdID = herdID
        if let animalID {
            source.herdRouter.path = [.animal(animalID)]
        }
        if let workingSessionID {
            source.openWorkArea(.session(workingSessionID))
        }
        return source.restorationPayload()!
    }
}

private enum PreflightStubValidationError: Error {
    case readFailed
}

@MainActor
private final class PreflightStubNavigationValidator: AppNavigationRestorationValidating {
    let currentHerdResult: Result<UUID?, PreflightStubValidationError>
    let animalResult: Result<Bool, PreflightStubValidationError>
    let pastureResult: Result<Bool, PreflightStubValidationError>
    let fieldCheckSessionResult: Result<Bool, PreflightStubValidationError>
    let workingSessionResult: Result<Bool, PreflightStubValidationError>

    init(
        currentHerdResult: Result<UUID?, PreflightStubValidationError>,
        animalResult: Result<Bool, PreflightStubValidationError> = .success(true),
        pastureResult: Result<Bool, PreflightStubValidationError> = .success(true),
        fieldCheckSessionResult: Result<Bool, PreflightStubValidationError> = .success(true),
        workingSessionResult: Result<Bool, PreflightStubValidationError> = .success(true)
    ) {
        self.currentHerdResult = currentHerdResult
        self.animalResult = animalResult
        self.pastureResult = pastureResult
        self.fieldCheckSessionResult = fieldCheckSessionResult
        self.workingSessionResult = workingSessionResult
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
}
