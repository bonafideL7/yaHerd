import XCTest
@testable import yaHerd

final class FieldCheckQuickCountRulesTests: XCTestCase {
    func testNormalizedCountsClampToRemainingRosterCapacityByAnimalType() {
        let rosterEntries = [
            makeRosterEntry(type: .cow),
            makeRosterEntry(type: .cow),
            makeRosterEntry(type: .calf),
            makeRosterEntry(type: .bull, isMissing: true)
        ]

        let counts = FieldCheckQuickCountRules.normalizedCounts(
            [.cow: 5, .calf: 1, .bull: 1, .heifer: -2],
            rosterEntries: rosterEntries
        )

        XCTAssertEqual(counts[.cow], 2)
        XCTAssertEqual(counts[.calf], 1)
        XCTAssertEqual(counts[.bull], 0)
        XCTAssertEqual(counts[.heifer], 0)
    }

    func testTotalSeenDoesNotDoubleCountIndividuallyVerifiedAnimals() {
        let rosterEntries = [
            makeRosterEntry(type: .cow, wasCounted: true),
            makeRosterEntry(type: .cow),
            makeRosterEntry(type: .cow)
        ]

        let totalSeen = FieldCheckQuickCountRules.totalSeen(
            quickCounts: [.cow: 3],
            rosterEntries: rosterEntries
        )

        XCTAssertEqual(totalSeen, 3)
    }


    func testTotalSeenIncludesCheckedAnimalsAddedAfterSessionStart() {
        let rosterEntries = [
            makeRosterEntry(type: .cow, wasExpectedAtStart: false, wasCounted: true),
            makeRosterEntry(type: .cow),
            makeRosterEntry(type: .cow)
        ]

        let totalSeen = FieldCheckQuickCountRules.totalSeen(
            quickCounts: [.cow: 2],
            rosterEntries: rosterEntries
        )

        XCTAssertEqual(totalSeen, 3)
        XCTAssertEqual(FieldCheckQuickCountRules.individuallyVerifiedCount(in: rosterEntries), 1)
    }

    func testMarkingAnimalMissingReducesQuickCountCapacity() {
        let rosterEntries = [
            makeRosterEntry(type: .heifer, isMissing: true),
            makeRosterEntry(type: .heifer),
            makeRosterEntry(type: .heifer)
        ]

        let counts = FieldCheckQuickCountRules.normalizedCounts(
            [.heifer: 3],
            rosterEntries: rosterEntries
        )

        XCTAssertEqual(counts[.heifer], 2)
    }

    func testSnapshotQuickCountsAreNormalizedForExistingInvalidSessions() {
        let detail = FieldCheckSessionDetailSnapshot(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: nil,
            notes: "",
            pastureID: UUID(),
            pastureName: "North",
            expectedHeadCountSnapshot: 3,
            quickCowCount: 3,
            quickHeiferCount: 0,
            quickCalfCount: 0,
            quickBullCount: 0,
            quickSteerCount: 0,
            animalChecks: [
                makeAnimalCheckSnapshot(type: .cow, wasCounted: true),
                makeAnimalCheckSnapshot(type: .cow),
                makeAnimalCheckSnapshot(type: .cow)
            ],
            findings: []
        )

        XCTAssertEqual(detail.individuallyVerifiedCount, 1)
        XCTAssertEqual(detail.quickAnimalTypeCounts[.cow], 2)
        XCTAssertEqual(detail.totalSeen, 3)
        XCTAssertEqual(detail.countVariance, 0)
    }

    private func makeRosterEntry(
        type: AnimalType,
        wasExpectedAtStart: Bool = true,
        wasCounted: Bool = false,
        isMissing: Bool = false
    ) -> FieldCheckQuickCountRosterEntry {
        FieldCheckQuickCountRosterEntry(
            animalType: type,
            wasExpectedAtStart: wasExpectedAtStart,
            wasCounted: wasCounted,
            isMissing: isMissing
        )
    }

    private func makeAnimalCheckSnapshot(
        type: AnimalType,
        wasExpectedAtStart: Bool = true,
        wasCounted: Bool = false,
        isMissing: Bool = false
    ) -> FieldCheckAnimalCheckSnapshot {
        FieldCheckAnimalCheckSnapshot(
            id: UUID(),
            animalID: UUID(),
            displayTagNumber: "1",
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            animalName: "",
            animalSex: .unknown,
            animalType: type,
            wasExpectedAtStart: wasExpectedAtStart,
            wasCounted: wasCounted,
            needsAttention: false,
            isMissing: isMissing
        )
    }
}
