import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckOverviewHerdIsolationTests: XCTestCase {
    func testHerdSwitchClearsOldSessionsAndLoadsCurrentHerd() {
        let originalID = UUID()
        let nextID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let oldSession = makeSession()
        let newSession = makeSession()
        let repository = HerdScopedFieldCheckOverviewProbe(
            selection: selection,
            sessionsByHerd: [originalID: [oldSession], nextID: [newSession]]
        )
        let model = FieldChecksViewModel()
        model.configure(selection: selection)

        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.sessions.map(\.id), [oldSession.id])

        selection.select(nextID)
        XCTAssertFalse(model.load(using: repository), "A stale reader must not load records under a new Herd.")
        XCTAssertEqual(repository.fetchCount, 1)

        model.configure(selection: selection)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.openFindings.isEmpty)
        XCTAssertNil(model.errorMessage)

        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.sessions.map(\.id), [newSession.id])
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testSwitchAwayAndBackResetsPreviouslyLoadedSelection() {
        let originalID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalID)
        let originalSession = makeSession()
        let replacementSession = makeSession()
        let repository = HerdScopedFieldCheckOverviewProbe(
            selection: selection,
            sessionsByHerd: [originalID: [originalSession]]
        )
        let model = FieldChecksViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: repository))

        selection.select(UUID())
        selection.select(originalID)
        repository.sessionsByHerd[originalID] = [replacementSession]
        XCTAssertFalse(model.load(using: repository), "An equal UUID after a switch is a new selection incarnation.")

        model.configure(selection: selection)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.sessions.map(\.id), [replacementSession.id])
    }

    func testFailedOpenFindingsImportPreservesCompleteOverviewUntilRetry() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let originalSession = makeSession()
        let importedSession = makeSession()
        let repository = HerdScopedFieldCheckOverviewProbe(
            selection: selection, sessionsByHerd: [herdID: [originalSession]]
        )
        let model = FieldChecksViewModel()
        model.configure(selection: selection)

        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.sessions.map(\.id), [originalSession.id])
        XCTAssertTrue(model.hasLoaded)

        // A partially imported Field Check graph can make the second read
        // fail even after fresh sessions were fetched. Publishing either half
        // would mix two generations of the overview on the active Herd.
        repository.sessionsByHerd[herdID] = [importedSession]
        repository.shouldFailFindings = true

        XCTAssertFalse(model.load(using: repository))
        XCTAssertEqual(model.sessions.map(\.id), [originalSession.id])
        XCTAssertTrue(model.openFindings.isEmpty)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)

        repository.shouldFailFindings = false
        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.sessions.map(\.id), [importedSession.id])
        XCTAssertNil(model.errorMessage)
    }

    func testSwitchClearsPreviousHerdLoadError() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = HerdScopedFieldCheckOverviewProbe(selection: selection)
        repository.shouldFail = true
        let model = FieldChecksViewModel()
        model.configure(selection: selection)

        XCTAssertFalse(model.load(using: repository))
        XCTAssertNotNil(model.errorMessage)

        selection.select(UUID())
        model.configure(selection: selection)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.hasLoaded)
        repository.shouldFail = false
        XCTAssertTrue(model.load(using: repository))
        XCTAssertNil(model.errorMessage)
    }

    func testOldMutationObserverCannotRefreshNewHerd() async {
        let firstID = UUID()
        let secondID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstID)
        let repository = HerdScopedFieldCheckOverviewProbe(selection: selection)
        let stream = ApplicationMutationCenter()
        let model = FieldChecksViewModel()
        model.configure(selection: selection)

        let observer = Task {
            await model.observe(using: repository, mutationStream: stream)
        }
        for _ in 0..<100 where repository.fetchCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(repository.fetchCount, 1)

        selection.select(secondID)
        model.configure(selection: selection)
        stream.recordSuccessfulMutation(reason: .fieldCheck)
        for _ in 0..<30 {
            await Task.yield()
        }
        XCTAssertEqual(repository.fetchCount, 1, "The old observer must not reload using the new selection.")

        observer.cancel()
        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(repository.fetchCount, 2)
    }

    private func makeSession() -> FieldCheckSessionSummary {
        FieldCheckSessionSummary(
            id: UUID(),
            startedAt: .now,
            completedAt: nil,
            pastureID: UUID(),
            pastureName: "Test pasture",
            pastureArchivedAt: nil,
            isPastureArchived: false,
            expectedHeadCountSnapshot: 0,
            quickCowCount: 0,
            quickHeiferCount: 0,
            quickCalfCount: 0,
            quickBullCount: 0,
            quickSteerCount: 0,
            animalChecks: [],
            openFindingsCount: 0
        )
    }
}

@MainActor
private final class HerdScopedFieldCheckOverviewProbe: FieldCheckOverviewReading {
    let selection: AppCurrentHerdSelection
    var sessionsByHerd: [UUID: [FieldCheckSessionSummary]]
    var shouldFail = false
    var shouldFailFindings = false
    private(set) var fetchCount = 0

    init(
        selection: AppCurrentHerdSelection,
        sessionsByHerd: [UUID: [FieldCheckSessionSummary]] = [:]
    ) {
        self.selection = selection
        self.sessionsByHerd = sessionsByHerd
    }

    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        fetchCount += 1
        if shouldFail { throw ProbeError.failed }
        guard let herdID = selection.currentHerdID else { return [] }
        return sessionsByHerd[herdID] ?? []
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        if shouldFail || shouldFailFindings { throw ProbeError.failed }
        return []
    }

    private enum ProbeError: Error {
        case failed
    }
}
