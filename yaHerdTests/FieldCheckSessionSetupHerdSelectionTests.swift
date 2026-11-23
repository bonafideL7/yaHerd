import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckSessionSetupHerdSelectionTests: XCTestCase {
    func testStartIsNotSubmittedAfterHerdChanges() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedFieldCheckSessionCreator()
        let model = FieldCheckSessionSetupViewModel()

        selection.select(UUID())
        let result = try await model.createSession(
            pastureID: UUID(),
            startedAt: .now,
            notes: "",
            originatingHerdID: originalHerdID,
            currentHerdSelection: selection,
            selectionIsUnchanged: {
                selection.selectionRevision == originatingSelectionRevision
            },
            using: repository
        )

        XCTAssertNil(result)
        XCTAssertEqual(repository.createCallCount, 0)
    }

    func testStartIsNotSubmittedAfterHerdSelectionRoundTrip() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedFieldCheckSessionCreator()
        let model = FieldCheckSessionSetupViewModel()

        selection.select(UUID())
        selection.select(originalHerdID)

        let result = try await model.createSession(
            pastureID: UUID(),
            startedAt: .now,
            notes: "",
            originatingHerdID: originalHerdID,
            currentHerdSelection: selection,
            selectionIsUnchanged: {
                selection.selectionRevision == originatingSelectionRevision
            },
            using: repository
        )

        XCTAssertNil(result)
        XCTAssertEqual(repository.createCallCount, 0, "An obsolete queued submit must not create a session.")
    }

    func testCompletedSaveDoesNotNavigateIntoAnotherHerd() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedFieldCheckSessionCreator()
        let model = FieldCheckSessionSetupViewModel()
        let savedID = UUID()

        let start = Task {
            try await model.createSession(
                pastureID: UUID(),
                startedAt: .now,
                notes: "",
                originatingHerdID: originalHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: {
                    selection.selectionRevision == originatingSelectionRevision
                },
                using: repository
            )
        }
        await repository.waitUntilStarted()
        selection.select(UUID())
        repository.complete(with: savedID)

        let result = try await start.value
        XCTAssertNil(result)
        XCTAssertEqual(repository.createCallCount, 1)
    }

    func testCompletedSaveDoesNotNavigateAfterHerdSelectionRoundTrip() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedFieldCheckSessionCreator()
        let model = FieldCheckSessionSetupViewModel()
        let savedID = UUID()

        let start = Task {
            try await model.createSession(
                pastureID: UUID(),
                startedAt: .now,
                notes: "",
                originatingHerdID: originalHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: {
                    selection.selectionRevision == originatingSelectionRevision
                },
                using: repository
            )
        }
        await repository.waitUntilStarted()
        selection.select(UUID())
        selection.select(originalHerdID)
        repository.complete(with: savedID)

        let result = try await start.value
        XCTAssertNil(result, "An obsolete setup must not open a session after switching away and back.")
        XCTAssertEqual(repository.createCallCount, 1, "The existing save must not be repeated.")
    }

    func testCancelledSaveDoesNotPublishNavigation() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedFieldCheckSessionCreator()
        let model = FieldCheckSessionSetupViewModel()

        let start = Task {
            try await model.createSession(
                pastureID: UUID(),
                startedAt: .now,
                notes: "",
                originatingHerdID: originalHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: {
                    selection.selectionRevision == originatingSelectionRevision
                },
                using: repository
            )
        }
        await repository.waitUntilStarted()
        start.cancel()
        repository.complete(with: UUID())

        let result = try await start.value
        XCTAssertNil(result)
        XCTAssertEqual(repository.createCallCount, 1)
    }

    func testSuccessfulSaveReturnsItsSessionInUnchangedHerd() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedFieldCheckSessionCreator()
        let model = FieldCheckSessionSetupViewModel()
        let savedID = UUID()

        let start = Task {
            try await model.createSession(
                pastureID: UUID(),
                startedAt: .now,
                notes: "Note",
                originatingHerdID: originalHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: {
                    selection.selectionRevision == originatingSelectionRevision
                },
                using: repository
            )
        }
        await repository.waitUntilStarted()
        repository.complete(with: savedID)

        let result = try await start.value
        XCTAssertEqual(result, savedID)
        XCTAssertEqual(repository.createCallCount, 1)
    }

    func testPastureSetupRejectsStaleReadAndReloadsOnlySelectedHerd() {
        let firstHerdID = UUID()
        let secondHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstHerdID)
        let firstPasture = PastureOption(id: UUID(), name: "First")
        let secondPasture = PastureOption(id: UUID(), name: "Second")
        let repository = HerdScopedSetupPastureProbe(
            selection: selection,
            pasturesByHerd: [firstHerdID: [firstPasture], secondHerdID: [secondPasture]]
        )
        let model = FieldCheckSessionSetupViewModel()

        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: repository))
        XCTAssertTrue(model.hasCurrentHerdData)
        XCTAssertEqual(model.pastures, [firstPasture])

        selection.select(secondHerdID)
        XCTAssertFalse(model.hasCurrentHerdData)
        XCTAssertFalse(model.load(using: repository), "Obsolete setup must not read a newly selected Herd.")
        XCTAssertEqual(repository.fetchCount, 1)

        model.configure(selection: selection)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.pastures.isEmpty)
        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.pastures, [secondPasture])
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testPastureSetupRoundTripDoesNotReuseOldPastureSelection() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let before = PastureOption(id: UUID(), name: "Before")
        let after = PastureOption(id: UUID(), name: "After")
        let repository = HerdScopedSetupPastureProbe(
            selection: selection,
            pasturesByHerd: [herdID: [before]]
        )
        let model = FieldCheckSessionSetupViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: repository))

        selection.select(UUID())
        selection.select(herdID)
        repository.pasturesByHerd[herdID] = [after]

        XCTAssertFalse(model.hasCurrentHerdData)
        XCTAssertFalse(model.load(using: repository))
        model.configure(selection: selection)
        XCTAssertTrue(model.pastures.isEmpty)
        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.pastures, [after])
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testFailedPastureReadIsNotMistakenForAnEmptyHerdAndCanRetry() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let expectedPasture = PastureOption(id: UUID(), name: "North")
        let repository = HerdScopedSetupPastureProbe(
            selection: selection,
            pasturesByHerd: [herdID: [expectedPasture]]
        )
        let model = FieldCheckSessionSetupViewModel()
        model.configure(selection: selection)

        repository.shouldFail = true
        XCTAssertFalse(model.load(using: repository))
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.hasCurrentHerdData)
        XCTAssertTrue(model.pastures.isEmpty)
        XCTAssertNotNil(model.pastureLoadErrorMessage)

        repository.shouldFail = false
        XCTAssertTrue(model.load(using: repository))
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.hasCurrentHerdData)
        XCTAssertEqual(model.pastures, [expectedPasture])
        XCTAssertNil(model.pastureLoadErrorMessage)
        XCTAssertEqual(repository.fetchCount, 2)
    }

    func testFailedRefreshHidesPreviouslyLoadedPasturesUntilSuccessfulRetry() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let priorPasture = PastureOption(id: UUID(), name: "Old")
        let replacementPasture = PastureOption(id: UUID(), name: "New")
        let repository = HerdScopedSetupPastureProbe(
            selection: selection,
            pasturesByHerd: [herdID: [priorPasture]]
        )
        let model = FieldCheckSessionSetupViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.pastures, [priorPasture])

        repository.shouldFail = true
        repository.pasturesByHerd[herdID] = [replacementPasture]
        XCTAssertFalse(model.load(using: repository))
        XCTAssertFalse(model.hasCurrentHerdData)
        XCTAssertTrue(model.pastures.isEmpty)
        XCTAssertNotNil(model.pastureLoadErrorMessage)

        repository.shouldFail = false
        XCTAssertTrue(model.load(using: repository))
        XCTAssertEqual(model.pastures, [replacementPasture])
        XCTAssertNil(model.pastureLoadErrorMessage)
    }

    func testSuccessfulEmptyPastureReadRemainsDistinctFromFailedImport() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = HerdScopedSetupPastureProbe(selection: selection)
        let model = FieldCheckSessionSetupViewModel()
        model.configure(selection: selection)

        XCTAssertTrue(model.load(using: repository))
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.hasCurrentHerdData)
        XCTAssertTrue(model.pastures.isEmpty)
        XCTAssertNil(model.pastureLoadErrorMessage)
    }

    func testPastureSetupRequiresAccessibleSelectionAndClearsOldError() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let repository = HerdScopedSetupPastureProbe(selection: selection)
        let model = FieldCheckSessionSetupViewModel()
        model.configure(selection: selection)
        repository.shouldFail = true
        XCTAssertFalse(model.load(using: repository))
        XCTAssertNotNil(model.pastureLoadErrorMessage)
        XCTAssertFalse(model.hasLoaded)

        selection.select(nil)
        model.configure(selection: selection)
        XCTAssertTrue(model.pastures.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.pastureLoadErrorMessage)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.load(using: repository))
        XCTAssertEqual(repository.fetchCount, 1, "No Herd must not trigger an unscoped pasture read.")

        selection.select(UUID())
        repository.shouldFail = false
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: repository))
        XCTAssertTrue(model.hasCurrentHerdData)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.pastureLoadErrorMessage)
    }
}

@MainActor
private final class SuspendedFieldCheckSessionCreator: FieldCheckSessionCreating {
    private(set) var createCallCount = 0
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var pendingCompletion: CheckedContinuation<UUID, Never>?

    func createSession(input: FieldCheckSessionStartInput) async throws -> UUID {
        createCallCount += 1
        return await withCheckedContinuation { continuation in
            pendingCompletion = continuation
            startedWaiter?.resume()
            startedWaiter = nil
        }
    }

    func waitUntilStarted() async {
        guard createCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startedWaiter = continuation
        }
    }

    func complete(with id: UUID) {
        pendingCompletion?.resume(returning: id)
        pendingCompletion = nil
    }
}

@MainActor
private final class HerdScopedSetupPastureProbe: PastureReferenceDataReader {
    let selection: AppCurrentHerdSelection
    var pasturesByHerd: [UUID: [PastureOption]]
    var shouldFail = false
    private(set) var fetchCount = 0

    init(
        selection: AppCurrentHerdSelection,
        pasturesByHerd: [UUID: [PastureOption]] = [:]
    ) {
        self.selection = selection
        self.pasturesByHerd = pasturesByHerd
    }

    func fetchPastureOptions() throws -> [PastureOption] {
        fetchCount += 1
        if shouldFail {
            throw NSError(domain: "HerdScopedSetupPastureProbe", code: 1)
        }
        guard let herdID = selection.currentHerdID else { return [] }
        return pasturesByHerd[herdID] ?? []
    }
}
