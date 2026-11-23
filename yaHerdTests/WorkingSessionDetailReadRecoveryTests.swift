import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionDetailReadRecoveryTests: XCTestCase {
    func testFailedInitialReadDoesNotClaimSessionWasDeletedAndCanRetry() {
        let sessionID = UUID()
        let repository = WorkingSessionDetailReadProbe()
        let model = WorkingSessionDetailViewModel(sessionID: sessionID, repository: repository)

        XCTAssertFalse(model.load())
        XCTAssertNil(model.session)
        XCTAssertFalse(model.hasLoaded, "A failed read is not a successful not-found lookup.")
        XCTAssertNotNil(model.errorMessage)

        repository.shouldFail = false
        repository.snapshot = makeSession(id: sessionID)
        XCTAssertTrue(model.load())
        XCTAssertEqual(model.session?.id, sessionID)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testSuccessfulMissingSessionRemainsDistinctFromReadError() {
        let repository = WorkingSessionDetailReadProbe()
        repository.shouldFail = false
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        XCTAssertTrue(model.load())
        XCTAssertNil(model.session)
        XCTAssertTrue(model.hasLoaded, "A successful nil lookup is a genuine not-found result.")
        XCTAssertNil(model.errorMessage)

        repository.shouldFail = true
        XCTAssertFalse(model.load())
        XCTAssertFalse(model.hasLoaded, "A subsequent store error invalidates the prior not-found result.")
        XCTAssertNotNil(model.errorMessage)
    }

    func testFailedRefreshRetainsLastCompleteSessionSnapshot() {
        let sessionID = UUID()
        let repository = WorkingSessionDetailReadProbe()
        repository.shouldFail = false
        repository.snapshot = makeSession(id: sessionID)
        let model = WorkingSessionDetailViewModel(sessionID: sessionID, repository: repository)
        XCTAssertTrue(model.load())

        repository.shouldFail = true
        XCTAssertFalse(model.load())
        XCTAssertEqual(model.session?.id, sessionID)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
    }

    private func makeSession(id: UUID) -> WorkingSessionDetailSnapshot {
        WorkingSessionDetailSnapshot(
            id: id,
            date: .now,
            status: .active,
            sourcePastureID: nil,
            sourcePastureName: nil,
            treatmentTemplateName: "",
            plannedTreatments: [],
            queueItems: []
        )
    }
}

@MainActor
private final class WorkingSessionDetailReadProbe: WorkingSessionDetailRepository {
    var shouldFail = true
    var snapshot: WorkingSessionDetailSnapshot?
    private(set) var fetchCount = 0

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        fetchCount += 1
        if shouldFail { throw ReadError.unavailable }
        return snapshot
    }

    func deleteSession(id: UUID) async throws {}

    private enum ReadError: Error {
        case unavailable
    }
}
