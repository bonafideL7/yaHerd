import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckAllTimelineTests: XCTestCase {
    func testAllShowsCompleteChronologicalTimelineAcrossStatesAndArchivedPastures() {
        let completed = (0..<25).map { makeSession(start: TimeInterval($0), completedAt: TimeInterval($0) + 100) }
        let lateFinish = makeSession(start: -1, completedAt: 1_000)
        let newestOpen = makeSession(start: 200)
        let attentionComplete = makeSession(start: 90, completedAt: 190, openFindings: 2)
        let archivedOpen = makeSession(start: 150, archived: true)
        let olderOpenWithUnfinishedCount = makeSession(start: 80, expectedCount: 5)
        let archivedCompleted = makeSession(start: 20, completedAt: 75, archived: true)
        // The completion date, not original start date or severity, determines All order.
        let records = completed + [archivedCompleted, olderOpenWithUnfinishedCount,
            newestOpen, attentionComplete, archivedOpen, lateFinish]
        let timeline = FieldCheckAllTimeline(sessions: records)
        XCTAssertEqual(timeline.sessions.map(\.id),
            [lateFinish.id, newestOpen.id, attentionComplete.id, archivedOpen.id]
            + completed.reversed().map(\.id)
            + [olderOpenWithUnfinishedCount.id, archivedCompleted.id])
        XCTAssertEqual(timeline.sessions.count, records.count)
        XCTAssertEqual(Set(timeline.sessions.map(\.id)), Set(records.map(\.id)))
    }

    func testSameActivityTimeUsesStartThenStableIdentity() {
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let earlierStarted = makeSession(start: 1, completedAt: 30)
        let sameDateLowID = makeSession(start: 2, completedAt: 30, id: lowID)
        let sameDateHighID = makeSession(start: 2, completedAt: 30, id: highID)
        let timeline = FieldCheckAllTimeline(sessions: [earlierStarted, sameDateHighID, sameDateLowID])
        XCTAssertEqual(timeline.sessions.map(\.id), [lowID, highID, earlierStarted.id])
    }

    func testOverviewTotalsRemainIndependentFromAttentionAndArchivedHistory() {
        let timeline = FieldCheckAllTimeline(sessions: [
            makeSession(start: 1),
            makeSession(start: 2, expectedCount: 2),
            makeSession(start: 3, completedAt: 4),
            makeSession(start: 5, completedAt: 6, openFindings: 1),
            makeSession(start: 7, archived: true, openFindings: 1)
        ])
        XCTAssertEqual(timeline.openCount, 2)
        XCTAssertEqual(timeline.completedCount, 2)
        XCTAssertEqual(timeline.attentionCount, 2)
        XCTAssertEqual(timeline.archivedCount, 1)
        XCTAssertEqual(timeline.sessions.count, 5)
    }

    private func makeSession(
        start: TimeInterval,
        completedAt: TimeInterval? = nil,
        archived: Bool = false,
        openFindings: Int = 0,
        expectedCount: Int = 0,
        id: UUID = UUID()
    ) -> FieldCheckSessionSummary {
        FieldCheckSessionSummary(
            id: id,
            startedAt: Date(timeIntervalSince1970: start),
            completedAt: completedAt.map { Date(timeIntervalSince1970: $0) },
            pastureID: UUID(),
            pastureName: "Test Pasture",
            pastureArchivedAt: archived ? Date(timeIntervalSince1970: start + 10) : nil,
            isPastureArchived: archived,
            expectedHeadCountSnapshot: expectedCount,
            quickCowCount: 0,
            quickHeiferCount: 0,
            quickCalfCount: 0,
            quickBullCount: 0,
            quickSteerCount: 0,
            animalChecks: [],
            openFindingsCount: openFindings
        )
    }
}
