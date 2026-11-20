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
