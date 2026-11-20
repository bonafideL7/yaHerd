import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionsListHerdIsolationTests: XCTestCase {
    func testSwitchClearsOldSessionsAndLoadsNewHerdWithoutMutation() {
        let firstID = UUID()
        let secondID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstID)
        let firstSession = makeSession()
        let secondSession = makeSession()
        let repository = HerdScopedWorkingSessionsProbe(
            selection: selection,
            sessionsByHerd: [firstID: [firstSession], secondID: [secondSession]]
        )
        let model = WorkingSessionsViewModel(repository: repository)
        model.configure(selection: selection)

        XCTAssertTrue(model.load())
        XCTAssertEqual(model.sessions.map(\.id), [firstSession.id])

        selection.select(secondID)
        XCTAssertFalse(model.isCurrentHerdSelection)
        XCTAssertFalse(model.load(), "A stale list must not query the newly selected Herd.")
        XCTAssertEqual(repository.fetchCount, 1)

        model.configure(selection: selection)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.load())
        XCTAssertEqual(model.sessions.map(\.id), [secondSession.id])
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testSwitchAwayAndBackCannotReuseOldSessionList() {
        let firstID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstID)
        let previousSession = makeSession()
        let replacementSession = makeSession()
        let repository = HerdScopedWorkingSessionsProbe(
            selection: selection,
            sessionsByHerd: [firstID: [previousSession]]
        )
        let model = WorkingSessionsViewModel(repository: repository)
        model.configure(selection: selection)
        XCTAssertTrue(model.load())

        selection.select(UUID())
        selection.select(firstID)
        repository.sessionsByHerd[firstID] = [replacementSession]
        XCTAssertFalse(model.isCurrentHerdSelection)
        XCTAssertFalse(model.load())

        model.configure(selection: selection)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.load())
        XCTAssertEqual(model.sessions.map(\.id), [replacementSession.id])
    }

    func testSelectionRemovalDiscardsSessionsAndPreventsUnscopedFetch() {
        let firstID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstID)
        let repository = HerdScopedWorkingSessionsProbe(
            selection: selection,
            sessionsByHerd: [firstID: [makeSession()]]
        )
        let model = WorkingSessionsViewModel(repository: repository)
        model.configure(selection: selection)
        XCTAssertTrue(model.load())

        selection.select(nil)
        model.configure(selection: selection)

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertFalse(model.load())
        XCTAssertEqual(repository.fetchCount, 1)
    }

    func testSwitchClearsOldLoadFailure() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = HerdScopedWorkingSessionsProbe(selection: selection)
        repository.shouldFail = true
        let model = WorkingSessionsViewModel(repository: repository)
        model.configure(selection: selection)
        XCTAssertFalse(model.load())
        XCTAssertNotNil(model.errorMessage)

        selection.select(UUID())
        model.configure(selection: selection)
        XCTAssertNil(model.errorMessage)
        repository.shouldFail = false
        XCTAssertTrue(model.load())
        XCTAssertNil(model.errorMessage)
    }

    func testObsoleteMutationObserverCannotReloadNewHerd() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = HerdScopedWorkingSessionsProbe(selection: selection)
        let mutations = ApplicationMutationCenter()
        let model = WorkingSessionsViewModel(repository: repository)
        model.configure(selection: selection)

        let observer = Task {
            await model.observe(mutationStream: mutations)
        }
        for _ in 0..<100 where repository.fetchCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(repository.fetchCount, 1)

        selection.select(UUID())
        model.configure(selection: selection)
        mutations.recordSuccessfulMutation(reason: .working)
        for _ in 0..<30 {
            await Task.yield()
        }
        XCTAssertEqual(repository.fetchCount, 1, "Previous Herd observer must not query the new Herd.")

        observer.cancel()
        XCTAssertTrue(model.load())
        XCTAssertEqual(repository.fetchCount, 2)
    }

    private func makeSession() -> WorkingSessionSummary {
        WorkingSessionSummary(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureName: "North Pasture",
            treatmentTemplateName: "",
            totalQueueItems: 0,
            completedQueueItems: 0
        )
    }
}

@MainActor
private final class HerdScopedWorkingSessionsProbe: WorkingSessionsRepository {
    let selection: AppCurrentHerdSelection
    var sessionsByHerd: [UUID: [WorkingSessionSummary]]
    var shouldFail = false
    private(set) var fetchCount = 0

    init(
        selection: AppCurrentHerdSelection,
        sessionsByHerd: [UUID: [WorkingSessionSummary]] = [:]
    ) {
        self.selection = selection
        self.sessionsByHerd = sessionsByHerd
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        fetchCount += 1
        if shouldFail { throw ProbeError.failed }
        guard let herdID = selection.currentHerdID else { return [] }
        return sessionsByHerd[herdID] ?? []
    }

    func deleteSession(id: UUID) async throws {}

    private enum ProbeError: Error {
        case failed
    }
}
