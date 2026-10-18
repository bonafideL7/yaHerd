import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckAllSessionGroupsTests: XCTestCase {
    func testAllIncludesOlderCompletedAndArchivedChecksExactlyOnce() {
        let completed = (0..<25).map { index in
            makeSession(startedAt: TimeInterval(index), completed: true)
        }
        // Sort completed checks by completion date, not their start date.
        let lateFinished = makeSession(startedAt: -1, completed: true, completionTime: 1_000)
        let olderOpen = makeSession(startedAt: 29, completed: false)
        let plainOpen = makeSession(startedAt: 30, completed: false)
        let unfinishedOpen = makeSession(startedAt: 31, completed: false, expectedCount: 2)
        let completedWithFindings = makeSession(startedAt: 32, completed: true, openFindings: 1)
        let flaggedOpen = makeSession(startedAt: 35, completed: false, flagged: true)
        let olderFlaggedOpen = makeSession(startedAt: 34, completed: false, flagged: true)
        let flaggedCompleted = makeSession(startedAt: 90, completed: true, flagged: true)
        let missingCompleted = makeSession(startedAt: 36, completed: true, flagged: true, missing: true)

        let archivedCompleted = makeSession(startedAt: 33, completed: true, archived: true)
        let archivedOpenWithFindings = makeSession(startedAt: 34, completed: false, archived: true, openFindings: 1)
        let archivedOlderOpen = makeSession(startedAt: 10, completed: false, archived: true)
        let archivedNewerCompleted = makeSession(startedAt: 40, completed: true, archived: true)

        let sessions = completed + [
            lateFinished, olderOpen, plainOpen, unfinishedOpen, completedWithFindings,
            flaggedOpen, olderFlaggedOpen, flaggedCompleted, missingCompleted,
            archivedCompleted, archivedOpenWithFindings, archivedOlderOpen, archivedNewerCompleted
        ]
        let groups = FieldCheckAllSessionGroups(sessions: sessions)
        let displayed = groups.needsAttention + groups.open + groups.completed + groups.archived

        XCTAssertEqual(groups.completed.count, 26, "All must not stop at twelve ordinary completed checks.")
        XCTAssertEqual(groups.completed.map(\\.id), [lateFinished.id] + completed.reversed().map(\\.id))
        XCTAssertEqual(groups.open.map(\\.id), [plainOpen.id, olderOpen.id])
        XCTAssertEqual(groups.needsAttention.map(\\.id), [
            missingCompleted.id, completedWithFindings.id,
            flaggedOpen.id, olderFlaggedOpen.id, flaggedCompleted.id, unfinishedOpen.id
        ], "Attention orders missing before findings, flagged before remaining, and open before completed on ties.")
        XCTAssertEqual(groups.archived.map(\\.id), [
            archivedOpenWithFindings.id, archivedOlderOpen.id,
            archivedNewerCompleted.id, archivedCompleted.id
        ], "Archived pasture checks sort open-first, newest start first within each state.")
        XCTAssertEqual(displayed.count, sessions.count, "Each session must appear in only one section.")
        XCTAssertEqual(Set(displayed.map(\\.id)), Set(sessions.map(\\.id)), "Every session must remain visible.")
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
        expectedCount: Int = 0,
        flagged: Bool = false,
        missing: Bool = false,
        completionTime: TimeInterval? = nil
    ) -> FieldCheckSessionSummary {
        let animalChecks: [FieldCheckAnimalCheckSnapshot] = (flagged || missing) ? [
            FieldCheckAnimalCheckSnapshot(
                id: UUID(),
                animalID: UUID(),
                displayTagNumber: "1",
                displayTagColorID: nil,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "",
                animalSex: .female,
                animalType: .cow,
                wasExpectedAtStart: false,
                wasCounted: false,
                needsAttention: flagged,
                isMissing: missing
            )
        ] : []

        return FieldCheckSessionSummary(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: startedAt),
            completedAt: completed ? Date(timeIntervalSince1970: completionTime ?? (startedAt + 100)) : nil,
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
            animalChecks: animalChecks,
            openFindingsCount: openFindings
        )
    }
}
