import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionCompletionUseCaseTests: XCTestCase {
    func testCompletesSessionAfterValidatingAssignments() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [firstID, secondID])
        )
        let assignments = [
            WorkingQueueDestinationAssignment(queueItemID: firstID, destinationPastureID: UUID()),
            WorkingQueueDestinationAssignment(queueItemID: secondID, destinationPastureID: nil)
        ]

        try await CompleteWorkingSessionUseCase(repository: repository).execute(
            sessionID: sessionID,
            assignments: assignments
        )

        XCTAssertEqual(repository.completionCalls.count, 1)
        XCTAssertEqual(repository.completionCalls.first?.sessionID, sessionID)
        XCTAssertEqual(repository.completionCalls.first?.assignments, assignments)
    }

    func testRejectsDuplicateAssignmentsBeforeMutation() async {
        let queueItemID = UUID()
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [queueItemID])
        )
        let assignments = [
            WorkingQueueDestinationAssignment(queueItemID: queueItemID, destinationPastureID: UUID()),
            WorkingQueueDestinationAssignment(queueItemID: queueItemID, destinationPastureID: nil)
        ]

        do {
            try await CompleteWorkingSessionUseCase(repository: repository).execute(
                sessionID: sessionID,
                assignments: assignments
            )
            XCTFail("Expected duplicate assignment validation failure")
        } catch {
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateQueueItemAssignments)
        }
        XCTAssertTrue(repository.completionCalls.isEmpty)
    }

    func testRejectsIncompleteAssignmentSetBeforeMutation() async {
        let firstID = UUID()
        let secondID = UUID()
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [firstID, secondID])
        )

        do {
            try await CompleteWorkingSessionUseCase(repository: repository).execute(
                sessionID: sessionID,
                assignments: [
                    WorkingQueueDestinationAssignment(queueItemID: firstID, destinationPastureID: nil)
                ]
            )
            XCTFail("Expected incomplete assignment validation failure")
        } catch {
            XCTAssertEqual(error as? WorkingRepositoryError, .assignmentSetDoesNotMatchSession)
        }
        XCTAssertTrue(repository.completionCalls.isEmpty)
    }

    func testFinishViewModelPreservesSessionAndRecoversFromTransientPastureReadFailure() {
        let sessionID = UUID()
        let pasture = PastureOption(id: UUID(), name: "Recovery Pasture")
        let workingRepository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [UUID()])
        )
        let pastureRepository = FlakyPastureReferenceDataReader(options: [pasture])
        let viewModel = WorkingFinishSessionViewModel(
            sessionID: sessionID,
            workingRepository: workingRepository,
            pastureRepository: pastureRepository
        )

        viewModel.load()

        XCTAssertEqual(viewModel.session?.id, sessionID)
        XCTAssertFalse(viewModel.hasLoadedPastureOptions)
        XCTAssertTrue(viewModel.needsPastureOptionsRetry)
        XCTAssertTrue(viewModel.pastures.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.retryPastureOptions()

        XCTAssertEqual(viewModel.pastures, [pasture])
        XCTAssertTrue(viewModel.hasLoadedPastureOptions)
        XCTAssertFalse(viewModel.needsPastureOptionsRetry)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRejectsFinishedSessionBeforeMutation() async {
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [], status: .finished)
        )

        do {
            try await CompleteWorkingSessionUseCase(repository: repository).execute(
                sessionID: sessionID,
                assignments: []
            )
            XCTFail("Expected finished-session validation failure")
        } catch {
            XCTAssertEqual(error as? WorkingRepositoryError, .sessionAlreadyFinished)
        }
        XCTAssertTrue(repository.completionCalls.isEmpty)
    }

    func testFinishViewModelDoesNotStartWhenOriginatingHerdIsNoLongerSelected() async throws {
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [])
        )
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = WorkingFinishSessionViewModel(
            sessionID: sessionID,
            workingRepository: repository,
            pastureRepository: EmptyPastureRepository()
        )

        let completed = try await model.finishSession(
            assignments: [],
            originatingHerdID: UUID(),
            currentHerdSelection: selection,
            repository: repository
        )

        XCTAssertFalse(completed)
        XCTAssertTrue(repository.completionCalls.isEmpty)
    }

    func testFinishViewModelDoesNotCompleteNavigationAfterHerdSwitch() async throws {
        let sessionID = UUID()
        let originatingHerdID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [])
        )
        repository.suspendCompletion = true
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let model = WorkingFinishSessionViewModel(
            sessionID: sessionID,
            workingRepository: repository,
            pastureRepository: EmptyPastureRepository()
        )

        let finishing = Task {
            try await model.finishSession(
                assignments: [],
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                repository: repository
            )
        }
        await repository.waitForPendingCompletion()
        selection.select(UUID())
        repository.finishPendingCompletion()

        let completed = try await finishing.value
        XCTAssertFalse(completed)
        XCTAssertEqual(repository.completionCalls.count, 1)
    }

    func testFinishViewModelDoesNotAcknowledgeCompletionAfterHerdSelectionRoundTrip() async throws {
        let sessionID = UUID()
        let originatingHerdID = UUID()
        let otherHerdID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [])
        )
        repository.suspendCompletion = true
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let model = WorkingFinishSessionViewModel(
            sessionID: sessionID,
            workingRepository: repository,
            pastureRepository: EmptyPastureRepository()
        )

        let finishing = Task {
            try await model.finishSession(
                assignments: [],
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                repository: repository
            )
        }
        await repository.waitForPendingCompletion()
        selection.select(otherHerdID)
        selection.select(originatingHerdID)
        repository.finishPendingCompletion()

        let completed = try await finishing.value
        XCTAssertFalse(completed, "An obsolete finish must not dismiss a newly opened Herd view.")
        XCTAssertEqual(repository.completionCalls.count, 1)
    }

    func testFinishViewModelAcknowledgesCompletionWhenHerdIsUnchanged() async throws {
        let sessionID = UUID()
        let herdID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [])
        )
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let model = WorkingFinishSessionViewModel(
            sessionID: sessionID,
            workingRepository: repository,
            pastureRepository: EmptyPastureRepository()
        )

        let completed = try await model.finishSession(
            assignments: [],
            originatingHerdID: herdID,
            currentHerdSelection: selection,
            repository: repository
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(repository.completionCalls.count, 1)
    }

    private func makeSession(
        id: UUID,
        queueItemIDs: [UUID],
        status: WorkingSessionStatus = .active
    ) -> WorkingSessionDetailSnapshot {
        WorkingSessionDetailSnapshot(
            id: id,
            date: .now,
            status: status,
            sourcePastureID: nil,
            sourcePastureName: nil,
            isSourcePastureAvailable: false,
            treatmentTemplateName: "Annual work",
            plannedTreatments: [],
            queueItems: queueItemIDs.enumerated().map { index, queueItemID in
                WorkingQueueItemSnapshot(
                    id: queueItemID,
                    status: .done,
                    completedAt: .now,
                    animalID: UUID(),
                    animalName: "Animal \(index + 1)",
                    animalDisplayTagNumber: "\(index + 1)",
                    animalDisplayTagColorID: nil,
                    animalDamDisplayTagNumber: nil,
                    animalDamDisplayTagColorID: nil,
                    animalSex: .female,
                    collectedFromPastureID: nil,
                    collectedFromPastureName: nil,
                    destinationPastureID: nil,
                    destinationPastureName: nil
                )
            }
        )
    }
}

@MainActor
private final class WorkingSessionCompletionRepositorySpy: WorkingFinishSessionRepository {
    struct CompletionCall: Equatable {
        let sessionID: UUID
        let assignments: [WorkingQueueDestinationAssignment]
    }

    let session: WorkingSessionDetailSnapshot?
    private(set) var completionCalls: [CompletionCall] = []
    var suspendCompletion = false
    private var pendingCompletion: CheckedContinuation<Void, Never>?

    init(session: WorkingSessionDetailSnapshot?) {
        self.session = session
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        session?.id == id ? session : nil
    }

    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) async throws {
        completionCalls.append(CompletionCall(sessionID: id, assignments: assignments))
        if suspendCompletion {
            await withCheckedContinuation { continuation in
                pendingCompletion = continuation
            }
        }
    }

    func waitForPendingCompletion() async {
        while pendingCompletion == nil {
            await Task.yield()
        }
    }

    func finishPendingCompletion() {
        guard let pendingCompletion else {
            preconditionFailure("No pending Working session completion")
        }
        self.pendingCompletion = nil
        pendingCompletion.resume()
    }
}

@MainActor
private final class FlakyPastureReferenceDataReader: PastureReferenceDataReader {
    private let options: [PastureOption]
    private var shouldFail = true

    init(options: [PastureOption]) {
        self.options = options
    }

    func fetchPastureOptions() throws -> [PastureOption] {
        if shouldFail {
            shouldFail = false
            throw WorkingSessionCompletionTestError.pastureReadFailed
        }

        return options
    }
}

private enum WorkingSessionCompletionTestError: Error {
    case pastureReadFailed
}
