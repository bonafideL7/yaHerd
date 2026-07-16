import XCTest
@testable import yaHerd

@MainActor
final class MutationCoordinatingRepositoryTests: XCTestCase {
    func testSuccessfulCommandPublishesAfterPersistence() throws {
        let base = StubDashboardRepository()
        let recorder = RecordingMutationRecorder()
        let repository = SyncRequestingDashboardRepository(
            base: base,
            mutationRecorder: recorder,
            writePolicy: HerdCollaborationWritePolicy()
        )
        let pastureID = UUID()

        try repository.markPastureGrazedToday(id: pastureID, on: .now)

        XCTAssertEqual(base.markedPastureIDs, [pastureID])
        XCTAssertEqual(recorder.reasons, [.dashboard])
    }

    func testFailedCommandDoesNotPublish() {
        let base = StubDashboardRepository(shouldFail: true)
        let recorder = RecordingMutationRecorder()
        let repository = SyncRequestingDashboardRepository(
            base: base,
            mutationRecorder: recorder,
            writePolicy: HerdCollaborationWritePolicy()
        )

        XCTAssertThrowsError(
            try repository.markPastureGrazedToday(id: UUID(), on: .now)
        )
        XCTAssertTrue(recorder.reasons.isEmpty)
    }
}

@MainActor
private final class RecordingMutationRecorder: SuccessfulMutationRecording {
    private(set) var reasons: [SharedDataMutationReason] = []

    func recordSuccessfulMutation(reason: SharedDataMutationReason) {
        reasons.append(reason)
    }
}

@MainActor
private final class StubDashboardRepository: DashboardRepository {
    enum Failure: Error {
        case requested
    }

    private let shouldFail: Bool
    private(set) var markedPastureIDs: [UUID] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func fetchDashboardRecords() throws -> DashboardRecords {
        DashboardRecords(animals: [], pastures: [], workingSessions: [])
    }

    func markPastureGrazedToday(id: UUID, on date: Date) throws {
        if shouldFail {
            throw Failure.requested
        }
        markedPastureIDs.append(id)
    }
}
