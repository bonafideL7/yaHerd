import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionReopenHerdIsolationTests: XCTestCase {
    func testWorkingSessionObservationRejectsAStaleHerdSelection() async {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        selection.select(UUID())

        await model.observe(
            mutationStream: InactiveApplicationMutationStream(),
            mayContinue: {
                selection.currentHerdID == originalHerdID
                    && selection.selectionRevision == originalRevision
            }
        )

        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertFalse(model.hasLoaded)
    }

    func testWorkingSessionObservationRejectsASelectionRoundTrip() async {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        selection.select(UUID())
        selection.select(originalHerdID)

        await model.observe(
            mutationStream: InactiveApplicationMutationStream(),
            mayContinue: {
                selection.currentHerdID == originalHerdID
                    && selection.selectionRevision == originalRevision
            }
        )

        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertFalse(model.hasLoaded)
    }

    func testWorkingSessionObservationLoadsForItsOriginalSelection() async {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originalRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        await model.observe(
            mutationStream: InactiveApplicationMutationStream(),
            mayContinue: {
                selection.currentHerdID == originalHerdID
                    && selection.selectionRevision == originalRevision
            }
        )

        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertTrue(model.hasLoaded)
    }

    func testWorkingSessionObservationStopsBeforeAQueuedRevisionAfterSwitchingHerds() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let openingRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        await model.observe(
            mutationStream: PreseededWorkingSessionRevisionStream(),
            mayContinue: {
                selection.currentHerdID == herdID
                    && selection.selectionRevision == openingRevision
            },
            didLoad: {
                selection.select(UUID())
            }
        )

        XCTAssertEqual(repository.fetchCount, 1)
    }

    func testWorkingSessionObservationProcessesQueuedRevisionForUnchangedHerd() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let openingRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        await model.observe(
            mutationStream: PreseededWorkingSessionRevisionStream(),
            mayContinue: {
                selection.currentHerdID == herdID
                    && selection.selectionRevision == openingRevision
            }
        )

        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testReopenDoesNotStartAfterSwitchingHerds() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let completed = await model.reopenSession(
            originatingHerdID: originatingHerdID,
            currentHerdSelection: selection,
            selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(repository.reopenCallCount, 0)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }

    func testInFlightReopenDoesNotReloadAfterSwitchingHerds() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
            )
        }
        await repository.waitForReopen()
        selection.select(UUID())
        repository.completeReopen()

        let completed = await reopening.value
        XCTAssertFalse(completed)
        XCTAssertEqual(repository.reopenCallCount, 1)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }

    func testReopenReloadsWhenOriginalHerdIsStillSelected() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
            )
        }
        await repository.waitForReopen()
        repository.completeReopen()

        let completed = await reopening.value
        XCTAssertTrue(completed)
        XCTAssertEqual(repository.reopenCallCount, 1)
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testFailureAfterSwitchingHerdsDoesNotShowObsoleteError() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
            )
        }
        await repository.waitForReopen()
        selection.select(UUID())
        repository.failReopen()

        let completed = await reopening.value
        XCTAssertFalse(completed)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(repository.fetchCount, 0)
    }

    func testFailureInOriginalHerdStillSurfacesError() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
            )
        }
        await repository.waitForReopen()
        repository.failReopen()

        let completed = await reopening.value
        XCTAssertFalse(completed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(repository.fetchCount, 0)
    }

    func testCancelledReopenDoesNotReloadAfterCommit() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
            )
        }
        await repository.waitForReopen()
        reopening.cancel()
        repository.completeReopen()

        let completed = await reopening.value
        XCTAssertFalse(completed)
        XCTAssertEqual(repository.reopenCallCount, 1)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }

    func testReopenDoesNotStartAfterSelectionRoundTrip() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        selection.select(UUID())
        selection.select(originatingHerdID)

        let completed = await model.reopenSession(
            originatingHerdID: originatingHerdID,
            currentHerdSelection: selection,
            selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(repository.reopenCallCount, 0)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }

    func testInFlightReopenDoesNotReloadAfterSelectionRoundTrip() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
            )
        }
        await repository.waitForReopen()
        selection.select(UUID())
        selection.select(originatingHerdID)
        repository.completeReopen()

        let completed = await reopening.value
        XCTAssertFalse(completed)
        XCTAssertEqual(repository.reopenCallCount, 1)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertNil(model.errorMessage)
    }

    func testFailureAfterSelectionRoundTripDoesNotShowObsoleteError() async {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let capturedRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionReopenRepository()
        let model = WorkingSessionDetailViewModel(sessionID: UUID(), repository: repository)

        let reopening = Task {
            await model.reopenSession(
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: { selection.selectionRevision == capturedRevision }
            )
        }
        await repository.waitForReopen()
        selection.select(UUID())
        selection.select(originatingHerdID)
        repository.failReopen()

        let completed = await reopening.value
        XCTAssertFalse(completed)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(repository.fetchCount, 0)
    }
}

@MainActor
private struct PreseededWorkingSessionRevisionStream: ApplicationMutationStreaming {
    var currentSequence: UInt64 { 1 }
    var homeRevision: UInt64 { 0 }
    var animalRevision: UInt64 { 0 }
    var pastureRevision: UInt64 { 0 }
    var fieldCheckRevision: UInt64 { 0 }
    var workingSessionRevision: UInt64 { 0 }

    func revision(for area: ApplicationFeatureArea) -> UInt64 {
        0
    }

    func revisions(for area: ApplicationFeatureArea, after revision: UInt64) -> AsyncStream<UInt64> {
        AsyncStream { continuation in
            if area == .workingSessions && revision < 1 {
                continuation.yield(1)
            }
            continuation.finish()
        }
    }

    func events(after sequence: UInt64) -> AsyncStream<ApplicationMutationEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
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
