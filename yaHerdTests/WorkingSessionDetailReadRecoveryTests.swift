import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionDetailReadRecoveryTests: XCTestCase {
    func testFailedInitialReadDoesNotClaimSessionWasDeletedAndCanRetry() {
        let repository = WorkingSessionDetailReadProbe()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        XCTAssertFalse(model.load())
        XCTAssertNil(model.session)
        XCTAssertFalse(model.hasLoaded, "A failed read is not a successful not-found lookup.")
        XCTAssertNotNil(model.errorMessage)

        repository.shouldFail = false
        XCTAssertTrue(model.load())
        XCTAssertNil(model.session)
        XCTAssertTrue(model.hasLoaded, "A successful nil lookup is a genuine not-found result.")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testFailedRefreshAfterNotFoundReturnsToRecoverableState() {
        let repository = WorkingSessionDetailReadProbe()
        repository.shouldFail = false
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        XCTAssertTrue(model.load())
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.session)

        repository.shouldFail = true
        XCTAssertFalse(model.load())
        XCTAssertFalse(model.hasLoaded, "A subsequent store error invalidates the prior not-found result.")
        XCTAssertNotNil(model.errorMessage)
    }
}

@MainActor
private final class WorkingSessionDetailReadProbe: WorkingSessionDetailRepository {
    var shouldFail = true
    private(set) var fetchCount = 0

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        fetchCount += 1
        if shouldFail { throw ReadError.unavailable }
        return nil
    }

    func deleteSession(id: UUID) async throws {}

    private enum ReadError: Error {
        case unavailable
    }
}
