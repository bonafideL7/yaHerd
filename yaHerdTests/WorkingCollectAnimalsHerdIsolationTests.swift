import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class WorkingCollectAnimalsHerdIsolationTests: XCTestCase {
    func testMoveDoesNotReadOrWriteWhenOriginatingHerdIsNoLongerSelected() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let sourcePastureID = UUID()
        let repository = SuspendedWorkingCollectRepository(
            session: makeSession(sourcePastureID: sourcePastureID)
        )

        let completed = try await WorkingCollectAnimalsMoveAction.execute(
            sessionID: repository.session.id,
            animalIDs: [UUID()],
            sourcePastureID: sourcePastureID,
            originatingHerdID: originatingHerdID,
            currentHerdSelection: selection,
            repository: repository
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertTrue(repository.collectedAnimalIDs.isEmpty)
    }

    func testMoveDoesNotPublishSuccessWhenHerdChangesDuringWrite() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let sourcePastureID = UUID()
        let animalID = UUID()
        let repository = SuspendedWorkingCollectRepository(
            session: makeSession(sourcePastureID: sourcePastureID),
            suspendCollection: true
        )

        let task = Task {
            try await WorkingCollectAnimalsMoveAction.execute(
                sessionID: repository.session.id,
                animalIDs: [animalID],
                sourcePastureID: sourcePastureID,
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                repository: repository
            )
        }
        await repository.waitForPendingCollection()
        selection.select(UUID())
        repository.completeCollection()

        XCTAssertFalse(try await task.value)
        XCTAssertEqual(repository.collectedAnimalIDs, [[animalID]])
        XCTAssertEqual(repository.fetchCount, 1)
    }

    func testCancelledMoveDoesNotPublishSuccessAfterWrite() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let sourcePastureID = UUID()
        let repository = SuspendedWorkingCollectRepository(
            session: makeSession(sourcePastureID: sourcePastureID),
            suspendCollection: true
        )

        let task = Task {
            try await WorkingCollectAnimalsMoveAction.execute(
                sessionID: repository.session.id,
                animalIDs: [UUID()],
                sourcePastureID: sourcePastureID,
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                repository: repository
            )
        }
        await repository.waitForPendingCollection()
        task.cancel()
        repository.completeCollection()

        XCTAssertFalse(try await task.value)
        XCTAssertEqual(repository.collectedAnimalIDs.count, 1)
    }

    func testMoveSucceedsForUnchangedHerdAndEligibleSession() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let sourcePastureID = UUID()
        let animalID = UUID()
        let repository = SuspendedWorkingCollectRepository(
            session: makeSession(sourcePastureID: sourcePastureID)
        )

        let completed = try await WorkingCollectAnimalsMoveAction.execute(
            sessionID: repository.session.id,
            animalIDs: [animalID],
            sourcePastureID: sourcePastureID,
            originatingHerdID: originatingHerdID,
            currentHerdSelection: selection,
            repository: repository
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertEqual(repository.collectedAnimalIDs, [[animalID]])
    }

    func testStaleSourceDoesNotCollectAfterSessionChanges() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let repository = SuspendedWorkingCollectRepository(
            session: makeSession(sourcePastureID: UUID())
        )

        do {
            _ = try await WorkingCollectAnimalsMoveAction.execute(
                sessionID: repository.session.id,
                animalIDs: [UUID()],
                sourcePastureID: UUID(),
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                repository: repository
            )
            XCTFail("A changed source pasture must reject collection.")
        } catch {
            XCTAssertTrue(repository.collectedAnimalIDs.isEmpty)
        }
    }

    private func makeSession(sourcePastureID: UUID) -> WorkingSessionDetailSnapshot {
        WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourcePastureID,
            sourcePastureName: "North",
            treatmentTemplateName: "",
            plannedTreatments: [],
            queueItems: []
        )
    }
}

@MainActor
private final class SuspendedWorkingCollectRepository: WorkingCollectAnimalsRepository {
    let session: WorkingSessionDetailSnapshot
    var suspendCollection: Bool
    private(set) var fetchCount = 0
    private(set) var collectedAnimalIDs: [[UUID]] = []
    private var pendingCompletion: CheckedContinuation<Void, Never>?

    init(session: WorkingSessionDetailSnapshot, suspendCollection: Bool = false) {
        self.session = session
        self.suspendCollection = suspendCollection
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        fetchCount += 1
        return id == session.id ? session : nil
    }

    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) async throws {
        collectedAnimalIDs.append(animalIDs)
        guard suspendCollection else { return }
        await withCheckedContinuation { continuation in
            pendingCompletion = continuation
        }
    }

    func waitForPendingCollection() async {
        while pendingCompletion == nil {
            await Task.yield()
        }
    }

    func completeCollection() {
        pendingCompletion?.resume()
        pendingCompletion = nil
    }
}
