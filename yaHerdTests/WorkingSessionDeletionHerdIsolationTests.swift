import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionDeletionHerdIsolationTests: XCTestCase {
    func testDeletionDoesNotStartAfterTheOriginatingHerdChanges() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = SuspendedWorkingSessionsRepository()
        let model = WorkingSessionsViewModel(repository: repository)

        let completed = try await model.deleteSession(
            id: UUID(),
            originatingHerdID: originatingHerdID,
            currentHerdSelection: selection
        )

        XCTAssertFalse(completed)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)
        XCTAssertEqual(repository.fetchCount, 0)
    }

    func testInFlightDeletionDoesNotReloadTheNewHerd() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingSessionsRepository()
        repository.suspendDeletion = true
        let model = WorkingSessionsViewModel(repository: repository)
        XCTAssertTrue(model.load())

        let sessionID = UUID()
        let deletion = Task {
            try await model.deleteSession(
                id: sessionID,
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection
            )
        }
        await repository.waitForPendingDeletion()
        selection.select(UUID())
        repository.finishDeletion()

        let completed = try await deletion.value
        XCTAssertFalse(completed)
        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testSuccessfulDeletionReloadsOnlyWhenOriginalHerdIsStillSelected() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingSessionsRepository()
        repository.suspendDeletion = true
        let model = WorkingSessionsViewModel(repository: repository)
        XCTAssertTrue(model.load())

        let sessionID = UUID()
        let deletion = Task {
            try await model.deleteSession(
                id: sessionID,
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection
            )
        }
        await repository.waitForPendingDeletion()
        repository.finishDeletion()

        let completed = try await deletion.value
        XCTAssertTrue(completed)
        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testCancelledDeletionDoesNotReloadAfterTheWriteCompletes() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingSessionsRepository()
        repository.suspendDeletion = true
        let model = WorkingSessionsViewModel(repository: repository)
        XCTAssertTrue(model.load())

        let deletion = Task {
            try await model.deleteSession(
                id: UUID(),
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection
            )
        }
        await repository.waitForPendingDeletion()
        deletion.cancel()
        repository.finishDeletion()

        let completed = try await deletion.value
        XCTAssertFalse(completed)
        XCTAssertEqual(repository.deletedSessionIDs.count, 1)
        XCTAssertEqual(repository.fetchCount, 1)
    }
}

@MainActor
private final class SuspendedWorkingSessionsRepository: WorkingSessionsRepository {
    private(set) var fetchCount = 0
    private(set) var deletedSessionIDs: [UUID] = []
    var suspendDeletion = false
    private var pendingDeletion: CheckedContinuation<Void, Error>?

    func fetchSessions() throws -> [WorkingSessionSummary] {
        fetchCount += 1
        return []
    }

    func deleteSession(id: UUID) async throws {
        deletedSessionIDs.append(id)
        guard suspendDeletion else { return }
        try await withCheckedThrowingContinuation { continuation in
            pendingDeletion = continuation
        }
    }

    func waitForPendingDeletion() async {
        while pendingDeletion == nil {
            await Task.yield()
        }
    }

    func finishDeletion() {
        guard let pendingDeletion else {
            preconditionFailure("No pending Working session deletion")
        }
        self.pendingDeletion = nil
        pendingDeletion.resume()
    }
}
