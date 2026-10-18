import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckAllSessionGroupsTests: XCTestCase {
    func testAllIncludesOlderCompletedAndArchivedChecksExactlyOnce() {
        let completed = (0..<25).map { index in
            makeSession(startedAt: TimeInterval(index), completed: true)
        }
        let plainOpen = makeSession(startedAt: 30, completed: false)
        let unfinishedOpen = makeSession(startedAt: 31, completed: false, expectedCount: 2)
        let completedWithFindings = makeSession(startedAt: 32, completed: true, openFindings: 1)
        let archivedCompleted = makeSession(startedAt: 33, completed: true, archived: true)
        let archivedOpenWithFindings = makeSession(startedAt: 34, completed: false, archived: true, openFindings: 1)

        let sessions = completed + [
            plainOpen, unfinishedOpen, completedWithFindings, archivedCompleted, archivedOpenWithFindings
        ]
        let groups = FieldCheckAllSessionGroups(sessions: sessions)
        let displayed = groups.needsAttention + groups.open + groups.completed + groups.archived

        XCTAssertEqual(groups.completed.count, 25, "All must not stop at twelve ordinary completed checks.")
        XCTAssertEqual(groups.open.map(\.id), [plainOpen.id])
        XCTAssertEqual(Set(groups.needsAttention.map(\.id)), Set([unfinishedOpen.id, completedWithFindings.id]))
        XCTAssertEqual(Set(groups.archived.map(\.id)), Set([archivedCompleted.id, archivedOpenWithFindings.id]))
        XCTAssertEqual(displayed.count, sessions.count, "Each session must appear in only one section.")
        XCTAssertEqual(Set(displayed.map(\.id)), Set(sessions.map(\.id)), "Every session must remain visible.")
    }

    func testSummaryCountsIncludeAttentionSessionsWithoutIncludingArchivedPastures() {
        let groups = FieldCheckAllSessionGroups(sessions: [
            makeSession(startedAt: 1, completed: false),
            makeSession(startedAt: 2, completed: false, expectedCount: 1),
            makeSession(startedAt: 3, completed: true),
            makeSession(startedAt: 4, completed: true, openFindings: 1),
            makeSession(startedAt: 5, completed: true, archived: true)
        ])

        XCTAssertEqual(groups.openCount, 2)
        XCTAssertEqual(groups.completedCount, 2)
        XCTAssertEqual(groups.needsAttention.count, 2)
        XCTAssertEqual(groups.archived.count, 1)
    }

    private func makeSession(
        startedAt: TimeInterval,
        completed: Bool,
        archived: Bool = false,
        openFindings: Int = 0,
        expectedCount: Int = 0
    ) -> FieldCheckSessionSummary {
        FieldCheckSessionSummary(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: startedAt),
            completedAt: completed ? Date(timeIntervalSince1970: startedAt + 100) : nil,
            pastureID: UUID(),
            pastureName: "Test Pasture",
            pastureArchivedAt: archived ? Date(timeIntervalSince1970: startedAt + 200) : nil,
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
