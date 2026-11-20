import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionReopenHerdIsolationTests: XCTestCase {
    func testReopenDoesNotStartAfterSwitchingHerds() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let completed = await model.reopenSession(
            originatingHerdID: originatingHerdID,
            currentHerdSelection: selection
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(repository.reopenCallCount, 0)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }

    func testInFlightReopenDoesNotReloadAfterSwitchingHerds() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection
            )
        }
        await repository.waitForReopen()
        selection.select(UUID())
        repository.completeReopen()

        XCTAssertFalse(await reopening.value)
        XCTAssertEqual(repository.reopenCallCount, 1)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }

    func testReopenReloadsWhenOriginalHerdIsStillSelected() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection
            )
        }
        await repository.waitForReopen()
        repository.completeReopen()

        XCTAssertTrue(await reopening.value)
        XCTAssertEqual(repository.reopenCallCount, 1)
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testFailureAfterSwitchingHerdsDoesNotShowObsoleteError() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection
            )
        }
        await repository.waitForReopen()
        selection.select(UUID())
        repository.failReopen()

        XCTAssertFalse(await reopening.value)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(repository.fetchCount, 0)
    }

    func testCancelledReopenDoesNotReloadAfterCommit() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection
            )
        }
        await repository.waitForReopen()
        reopening.cancel()
        repository.completeReopen()

        XCTAssertFalse(await reopening.value)
        XCTAssertEqual(repository.reopenCallCount, 1)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }
}

@MainActor
private final class SuspendedWorkingSessionReopenRepository: WorkingSessionDetailRepository {
    private(set) var reopenCallCount = 0
    private(set) var fetchCount = 0
    private var pendingReopen: CheckedContinuation<Void, Error>?

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        fetchCount += 1
        return nil
    }

    func deleteSession(id: UUID) async throws {}

    func reopenSession(id: UUID) async throws {
        reopenCallCount += 1
        try await withCheckedThrowingContinuation { continuation in
            pendingReopen = continuation
        }
    }

    func waitForReopen() async {
        while pendingReopen == nil {
            await Task.yield()
        }
    }

    func completeReopen() {
        let pending = pendingReopen
        pendingReopen = nil
        pending?.resume()
    }

    func failReopen() {
        let pending = pendingReopen
        pendingReopen = nil
        pending?.resume(throwing: ReopenTestError.failed)
    }

    private enum ReopenTestError: Error {
        case failed
    }
}
