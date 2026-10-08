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
    func testRecoveryLeavesDurableNavigationPayloadAndAllStoredIdentitiesUntouched() throws {
        let durableHerdID = UUID()
        let animalID = UUID()
        let pastureID = UUID()
        let fieldCheckID = UUID()
        let workingID = UUID()

        // Both active workflow variants use the same durable scene storage key.
        // Recovery must preserve either payload without resolving records
        // against its temporary Herd or replacing stored IDs after navigation.
        for usesFieldCheck in [true, false] {
            let saved = AppNavigationState()
            saved.selectedHerdID = durableHerdID
            saved.selectedTab = .herd
            saved.herdRouter.path = [.animal(animalID), .pasture(pastureID)]
            saved.herdRouter.searchPath = [.pasture(pastureID)]
            saved.herdRouter.filter.pasture = .pasture(pastureID)
            if usesFieldCheck {
                saved.openFieldCheckArea(
                    .session(FieldCheckSessionLaunchConfiguration(sessionID: fieldCheckID))
                )
            } else {
                saved.openWorkArea(.session(workingID))
            }
            let storedPayload = try XCTUnwrap(saved.restorationPayload())
            let savedSnapshot = saved.snapshot

            let recoveryNavigation = AppNavigationState()
            let initialRecoverySnapshot = recoveryNavigation.snapshot
            let ephemeralHerdID = UUID()
            let validator = PreflightStubNavigationValidator(
                currentHerdResult: .success(ephemeralHerdID),
                animalResult: .success(false),
                pastureResult: .success(false),
                fieldCheckSessionResult: .success(false),
                workingSessionResult: .success(false)
            )

            XCTAssertNil(
                AppNavigationSceneStorageAccess.restore(
                    navigation: recoveryNavigation,
                    from: storedPayload,
                    using: validator,
                    dataAccessMode: .recoveryReadOnly
                )
            )
            XCTAssertEqual(recoveryNavigation.snapshot, initialRecoverySnapshot)
            XCTAssertNil(
                AppNavigationSceneStorageAccess.payload(
                    for: recoveryNavigation,
                    dataAccessMode: .recoveryReadOnly
                )
            )

            // Even when deep links or the temporary UI change navigation,
            // recovery still cannot generate a replacement scene payload.
            recoveryNavigation.herdRouter.path = [.animal(UUID())]
            recoveryNavigation.selectedHerdID = ephemeralHerdID
            XCTAssertNil(
                AppNavigationSceneStorageAccess.payload(
                    for: recoveryNavigation,
                    dataAccessMode: .recoveryReadOnly
                )
            )

            let intact = AppNavigationState()
            let durableValidator = PreflightStubNavigationValidator(
                currentHerdResult: .success(durableHerdID),
                animalResult: .success(true),
                pastureResult: .success(true),
                fieldCheckSessionResult: .success(true),
                workingSessionResult: .success(true)
            )
            intact.restore(from: storedPayload, using: durableValidator)
            XCTAssertEqual(intact.snapshot, savedSnapshot)
            XCTAssertEqual(intact.selectedHerdID, durableHerdID)
            XCTAssertEqual(intact.herdRouter.path, [.animal(animalID), .pasture(pastureID)])
            XCTAssertEqual(intact.herdRouter.searchPath, [.pasture(pastureID)])
            XCTAssertEqual(intact.herdRouter.filter.pasture, .pasture(pastureID))
            if usesFieldCheck {
                guard case .fieldCheckSession(let route) = intact.workflowRouter.route else {
                    return XCTFail("Expected the original Field Check workflow token")
                }
                XCTAssertEqual(route.sessionID, fieldCheckID)
            } else {
                guard case .workingSession(let sessionID) = intact.workflowRouter.route else {
                    return XCTFail("Expected the original Working session token")
                }
                XCTAssertEqual(sessionID, workingID)
            }
        }
    }

    @MainActor
    func testHealthyRuntimeRestoresAndPersistsNavigationAfterRecovery() throws {
        let durableHerdID = UUID()
        let animalID = UUID()
        let workingID = UUID()
        let savedPayload = makePayload(
            herdID: durableHerdID,
            animalID: animalID,
            workingSessionID: workingID
        )

        let recoveryNavigation = AppNavigationState()
        let recoveryValidator = PreflightStubNavigationValidator(
            currentHerdResult: .success(UUID()),
            animalResult: .success(false),
            workingSessionResult: .success(false)
        )
        XCTAssertNil(
            AppNavigationSceneStorageAccess.restore(
                navigation: recoveryNavigation,
                from: savedPayload,
                using: recoveryValidator,
                dataAccessMode: .recoveryReadOnly
            )
        )
        XCTAssertNil(
            AppNavigationSceneStorageAccess.payload(
                for: recoveryNavigation,
                dataAccessMode: .recoveryReadOnly
            )
        )

        let reopened = AppNavigationState()
        let durableValidator = PreflightStubNavigationValidator(
            currentHerdResult: .success(durableHerdID),
            animalResult: .success(true),
            workingSessionResult: .success(true)
        )
        XCTAssertEqual(
            AppNavigationSceneStorageAccess.restore(
                navigation: reopened,
                from: savedPayload,
                using: durableValidator,
                dataAccessMode: .readWrite
            ),
            .applied
        )
        XCTAssertEqual(reopened.selectedHerdID, durableHerdID)
        XCTAssertEqual(reopened.herdRouter.path, [.animal(animalID)])
        guard case .workingSession(let restoredID) = reopened.workflowRouter.route else {
            return XCTFail("Expected restored Working session after durable relaunch")
        }
        XCTAssertEqual(restoredID, workingID)

        XCTAssertNotNil(
            AppNavigationSceneStorageAccess.payload(
                for: reopened,
                dataAccessMode: .readWrite
            )
        )
        reopened.herdRouter.path = [.animal(UUID())]
        let updatedPayload = try XCTUnwrap(
            AppNavigationSceneStorageAccess.payload(
                for: reopened,
                dataAccessMode: .readWrite
            )
        )
        XCTAssertNotEqual(updatedPayload, savedPayload)
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
