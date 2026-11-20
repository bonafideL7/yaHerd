import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class AppNavigationDeepLinkHerdIsolationTests: XCTestCase {
    func testOtherHerdAnimalLinkPreservesCurrentWorkflow() {
        let herdID = UUID()
        let otherHerdAnimalID = UUID()
        let existingSessionID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.openWorkArea(.session(existingSessionID))

        let handled = navigation.handle(
            url: URL(string: "yaherd://animal/\(otherHerdAnimalID)")!,
            using: DeepLinkTestValidator(herdID: herdID)
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(navigation.fullScreenWorkflow, .workingSession)
        XCTAssertEqual(navigation.workflowRouter.route, .workingSession(existingSessionID))
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
    }

    func testMissingPastureAndSessionsDoNotChangeNavigation() {
        let herdID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.selectedTab = .dashboard
        let validator = DeepLinkTestValidator(herdID: herdID)

        for destination in ["pasture", "field-check", "work-session"] {
            XCTAssertFalse(navigation.handle(
                url: URL(string: "yaherd://\(destination)/\(UUID())")!,
                using: validator
            ))
        }

        XCTAssertEqual(navigation.selectedTab, .dashboard)
        XCTAssertNil(navigation.fullScreenWorkflow)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
    }

    func testFindingMustExistWithinSelectedHerdSession() {
        let herdID = UUID()
        let sessionID = UUID()
        let findingID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        let validator = DeepLinkTestValidator(
            herdID: herdID,
            fieldCheckIDs: [sessionID]
        )

        XCTAssertFalse(navigation.handle(
            url: URL(string: "yaherd://field-check/\(sessionID)?finding=\(findingID)")!,
            using: validator
        ))
        XCTAssertNil(navigation.fullScreenWorkflow)
    }

    func testValidSelectedHerdLinksOpenRecordsAndHistoricalSessions() {
        let herdID = UUID()
        let animalID = UUID()
        let pastureID = UUID()
        let checkID = UUID()
        let findingID = UUID()
        let workingID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        let validator = DeepLinkTestValidator(
            herdID: herdID,
            animalIDs: [animalID],
            pastureIDs: [pastureID],
            fieldCheckIDs: [checkID],
            workingIDs: [workingID],
            findingIDs: [findingID]
        )

        XCTAssertTrue(navigation.handle(
            url: URL(string: "yaherd://animal/\(animalID)")!,
            using: validator
        ))
        XCTAssertEqual(navigation.herdRouter.path, [.animal(animalID)])

        XCTAssertTrue(navigation.handle(
            url: URL(string: "yaherd://pasture/\(pastureID)")!,
            using: validator
        ))
        XCTAssertEqual(navigation.herdRouter.path, [.pasture(pastureID)])

        XCTAssertTrue(navigation.handle(
            url: URL(string: "yaherd://field-check/\(checkID)?finding=\(findingID)")!,
            using: validator
        ))
        guard case .fieldCheckSession(let configuration) = navigation.workflowRouter.route else {
            return XCTFail("Expected validated finding navigation")
        }
        XCTAssertEqual(configuration.focusedFindingID, findingID)

        XCTAssertTrue(navigation.handle(
            url: URL(string: "yaherd://work-session/\(workingID)")!,
            using: validator
        ))
        XCTAssertEqual(navigation.workflowRouter.route, .workingSession(workingID))
    }

    func testNoSelectedHerdOrChangedHerdRejectsSearchAndRecordLinks() {
        let herdID = UUID()
        let navigation = AppNavigationState()
        let searchURL = URL(string: "yaherd://search?q=white")!
        let validator = DeepLinkTestValidator(herdID: herdID)

        XCTAssertFalse(navigation.handle(url: searchURL, using: validator))

        navigation.selectedHerdID = UUID()
        XCTAssertFalse(navigation.handle(url: searchURL, using: validator))
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertEqual(navigation.herdRouter.searchText, "")
    }

    func testRepositoryReadFailureDoesNotChangeNavigation() {
        let herdID = UUID()
        let animalID = UUID()
        let navigation = AppNavigationState()
        navigation.selectedHerdID = herdID
        navigation.selectedTab = .dashboard

        XCTAssertFalse(navigation.handle(
            url: URL(string: "yaherd://animal/\(animalID)")!,
            using: DeepLinkTestValidator(
                herdID: herdID,
                animalIDs: [animalID],
                failRecordReads: true
            )
        ))
        XCTAssertEqual(navigation.selectedTab, .dashboard)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
    }
}

private enum DeepLinkReadError: Error {
    case unavailable
}

@MainActor
private struct DeepLinkTestValidator: AppNavigationRestorationValidating, FocusedFieldCheckFindingValidating {
    let herdID: UUID?
    var animalIDs: Set<UUID> = []
    var pastureIDs: Set<UUID> = []
    var fieldCheckIDs: Set<UUID> = []
    var workingIDs: Set<UUID> = []
    var findingIDs: Set<UUID> = []
    var failRecordReads = false

    func currentHerdID() throws -> UUID? { herdID }

    func animalExists(id: UUID) throws -> Bool {
        try checkRead()
        return animalIDs.contains(id)
    }

    func pastureExists(id: UUID) throws -> Bool {
        try checkRead()
        return pastureIDs.contains(id)
    }

    func isActiveFieldCheckSession(id: UUID) throws -> Bool {
        try fieldCheckSessionExists(id: id)
    }

    func isActiveWorkingSession(id: UUID) throws -> Bool {
        try workingSessionExists(id: id)
    }

    func fieldCheckSessionExists(id: UUID) throws -> Bool {
        try checkRead()
        return fieldCheckIDs.contains(id)
    }

    func workingSessionExists(id: UUID) throws -> Bool {
        try checkRead()
        return workingIDs.contains(id)
    }

    func fieldCheckFindingExists(sessionID: UUID, findingID: UUID) throws -> Bool {
        try checkRead()
        return fieldCheckIDs.contains(sessionID) && findingIDs.contains(findingID)
    }

    private func checkRead() throws {
        if failRecordReads { throw DeepLinkReadError.unavailable }
    }
}
