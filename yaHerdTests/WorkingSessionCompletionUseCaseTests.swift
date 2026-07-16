import XCTest
@testable import yaHerd

@MainActor
final class WorkingSessionCompletionUseCaseTests: XCTestCase {
    func testCompletesSessionAfterValidatingAssignments() throws {
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

        try CompleteWorkingSessionUseCase(repository: repository).execute(
            sessionID: sessionID,
            assignments: assignments
        )

        XCTAssertEqual(repository.completionCalls.count, 1)
        XCTAssertEqual(repository.completionCalls.first?.sessionID, sessionID)
        XCTAssertEqual(repository.completionCalls.first?.assignments, assignments)
    }

    func testRejectsDuplicateAssignmentsBeforeMutation() {
        let queueItemID = UUID()
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [queueItemID])
        )
        let assignments = [
            WorkingQueueDestinationAssignment(queueItemID: queueItemID, destinationPastureID: UUID()),
            WorkingQueueDestinationAssignment(queueItemID: queueItemID, destinationPastureID: nil)
        ]

        XCTAssertThrowsError(
            try CompleteWorkingSessionUseCase(repository: repository).execute(
                sessionID: sessionID,
                assignments: assignments
            )
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateQueueItemAssignments)
        }
        XCTAssertTrue(repository.completionCalls.isEmpty)
    }

    func testRejectsIncompleteAssignmentSetBeforeMutation() {
        let firstID = UUID()
        let secondID = UUID()
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [firstID, secondID])
        )

        XCTAssertThrowsError(
            try CompleteWorkingSessionUseCase(repository: repository).execute(
                sessionID: sessionID,
                assignments: [
                    WorkingQueueDestinationAssignment(queueItemID: firstID, destinationPastureID: nil)
                ]
            )
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .assignmentSetDoesNotMatchSession)
        }
        XCTAssertTrue(repository.completionCalls.isEmpty)
    }

    func testRejectsFinishedSessionBeforeMutation() {
        let sessionID = UUID()
        let repository = WorkingSessionCompletionRepositorySpy(
            session: makeSession(id: sessionID, queueItemIDs: [], status: .finished)
        )

        XCTAssertThrowsError(
            try CompleteWorkingSessionUseCase(repository: repository).execute(
                sessionID: sessionID,
                assignments: []
            )
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .sessionAlreadyFinished)
        }
        XCTAssertTrue(repository.completionCalls.isEmpty)
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
            protocolName: "Annual work",
            protocolItems: [],
            queueItems: queueItemIDs.enumerated().map { index, queueItemID in
                WorkingQueueItemSnapshot(
                    id: queueItemID,
                    queueOrder: index,
                    status: .done,
                    completedAt: .now,
                    animalID: UUID(),
                    animalDisplayTagNumber: "\(index + 1)",
                    animalDisplayTagColorID: nil,
                    animalDamDisplayTagNumber: nil,
                    animalDamDisplayTagColorID: nil,
                    animalSex: .female,
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

    init(session: WorkingSessionDetailSnapshot?) {
        self.session = session
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        session?.id == id ? session : nil
    }

    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) throws {
        completionCalls.append(CompletionCall(sessionID: id, assignments: assignments))
    }
}
