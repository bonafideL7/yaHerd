import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckAnimalDetailHerdSelectionTests: XCTestCase {
    func testQueuedAnimalMutationDoesNotRunAfterHerdSelectionChanges() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let model = FieldCheckAnimalDetailViewModel()
        model.bindHerdSelection(selection)
        let repository = SuspendedAnimalDetailFieldCheckRepository()
        let firstAnimalID = UUID()

        let first = Task {
            try await model.addTrackedAnimalToSession(
                animalID: firstAnimalID,
                sessionID: UUID(),
                fieldCheckRepository: repository
            )
        }
        await repository.waitForFirstAdd()

        let queued = Task {
            try await model.addTrackedAnimalToSession(
                animalID: UUID(),
                sessionID: UUID(),
                fieldCheckRepository: repository
            )
        }
        await Task.yield()
        selection.select(UUID())
        repository.releaseFirstAdd()

        await assertCancelled(first)
        await assertCancelled(queued)
        XCTAssertEqual(repository.addedAnimalIDs, [firstAnimalID])
    }

    func testSwitchingAwayAndBackStillInvalidatesQueuedAnimalMutation() async throws {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let model = FieldCheckAnimalDetailViewModel()
        model.bindHerdSelection(selection)
        let repository = SuspendedAnimalDetailFieldCheckRepository()

        let first = Task {
            try await model.addTrackedAnimalToSession(
                animalID: UUID(),
                sessionID: UUID(),
                fieldCheckRepository: repository
            )
        }
        await repository.waitForFirstAdd()

        let queued = Task {
            try await model.addTrackedAnimalToSession(
                animalID: UUID(),
                sessionID: UUID(),
                fieldCheckRepository: repository
            )
        }
        await Task.yield()
        selection.select(UUID())
        selection.select(originalHerdID)
        repository.releaseFirstAdd()

        await assertCancelled(first)
        await assertCancelled(queued)
        XCTAssertEqual(repository.addedAnimalIDs.count, 1)
    }

    func testQueuedAnimalMutationsCompleteWhenHerdDoesNotChange() async throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = FieldCheckAnimalDetailViewModel()
        model.bindHerdSelection(selection)
        let repository = SuspendedAnimalDetailFieldCheckRepository()

        let first = Task {
            try await model.addTrackedAnimalToSession(
                animalID: UUID(),
                sessionID: UUID(),
                fieldCheckRepository: repository
            )
        }
        await repository.waitForFirstAdd()
        let queued = Task {
            try await model.addTrackedAnimalToSession(
                animalID: UUID(),
                sessionID: UUID(),
                fieldCheckRepository: repository
            )
        }
        await Task.yield()
        repository.releaseFirstAdd()

        try await first.value
        try await queued.value
        XCTAssertEqual(repository.addedAnimalIDs.count, 2)
    }

    private func assertCancelled(_ task: Task<Void, Error>) async {
        do {
            try await task.value
            XCTFail("An obsolete animal action must not report success.")
        } catch is CancellationError {
            // A previously committed write is retained; obsolete follow-up work is discarded.
        } catch {
            XCTFail("Expected cancellation, received \(error)")
        }
    }
}

@MainActor
private final class SuspendedAnimalDetailFieldCheckRepository: FieldCheckAnimalDetailRepository {
    private(set) var addedAnimalIDs: [UUID] = []
    private var firstAddStarted: CheckedContinuation<Void, Never>?
    private var firstAddCompletion: CheckedContinuation<Void, Never>?

    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? { nil }

    func setAnimalCheckCounted(
        sessionID: UUID, animalCheckID: UUID, isCounted: Bool
    ) async throws {}

    func setAnimalCheckMissing(
        sessionID: UUID, animalCheckID: UUID, isMissing: Bool
    ) async throws {}

    func addTrackedAnimalToSession(
        sessionID: UUID, animalID: UUID, checkedAt: Date
    ) async throws {
        addedAnimalIDs.append(animalID)
        if addedAnimalIDs.count == 1 {
            await withCheckedContinuation { continuation in
                firstAddCompletion = continuation
                firstAddStarted?.resume()
                firstAddStarted = nil
            }
        }
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput) async throws {}

    func updateFinding(
        sessionID: UUID, findingID: UUID, input: FieldCheckFindingInput
    ) async throws {}

    func updateFindingStatus(
        sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus
    ) async throws {}

    func deleteFinding(sessionID: UUID, findingID: UUID) async throws {}

    func waitForFirstAdd() async {
        guard addedAnimalIDs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            firstAddStarted = continuation
        }
    }

    func releaseFirstAdd() {
        firstAddCompletion?.resume()
        firstAddCompletion = nil
    }
}
