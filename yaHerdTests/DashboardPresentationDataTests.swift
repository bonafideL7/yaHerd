import XCTest
@testable import yaHerd

@MainActor
final class DashboardPresentationDataTests: XCTestCase {
    func testPastureUtilizationStatusLabelsIncludeOverCapacityDangerAndWarning() {
        let overCapacityID = UUID()
        let dangerID = UUID()
        let warningID = UUID()
        let normalID = UUID()

        let snapshot = makeSnapshot(
            pastures: [
                makePasture(
                    id: overCapacityID,
                    name: "Over Capacity",
                    activeAnimalCount: 6,
                    acres: 12,
                    usableAcreage: 10,
                    targetAcresPerHead: 2
                ),
                makePasture(
                    id: dangerID,
                    name: "Danger",
                    activeAnimalCount: 9,
                    acres: 10,
                    targetAcresPerHead: 1
                ),
                makePasture(
                    id: warningID,
                    name: "Warning",
                    activeAnimalCount: 76,
                    acres: 100,
                    targetAcresPerHead: 1,
                    lastGrazedDate: Date(),
                    restDays: 30
                ),
                makePasture(
                    id: normalID,
                    name: "Normal",
                    activeAnimalCount: 6,
                    acres: 10,
                    targetAcresPerHead: 1,
                    lastGrazedDate: Date(),
                    restDays: 30
                )
            ]
        )

        let data = DashboardPresentationData(snapshot: snapshot, fieldCheckSessions: [])
        let valuesByID = Dictionary(uniqueKeysWithValues: data.pastureUtilizationValues.map { ($0.id, $0) })

        XCTAssertEqual(valuesByID[overCapacityID]?.statusLabel, "Over Capacity")
        XCTAssertEqual(valuesByID[dangerID]?.statusLabel, "Danger")
        XCTAssertEqual(valuesByID[warningID]?.statusLabel, "Warning")
        XCTAssertEqual(valuesByID[normalID]?.statusLabel, "Normal")
    }

    func testOffspringByDamDisambiguatesDuplicateDisplayTagsWithoutChangingIdentity() {
        let firstDamID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondDamID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let uniqueDamID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let snapshot = makeSnapshot(
            pastures: [],
            offspringByDam: [
                DashboardOffspringDamMetric(
                    damID: secondDamID,
                    damDisplayTagNumber: "UT",
                    offspringCount: 2
                ),
                DashboardOffspringDamMetric(
                    damID: firstDamID,
                    damDisplayTagNumber: "UT",
                    offspringCount: 3
                ),
                DashboardOffspringDamMetric(
                    damID: uniqueDamID,
                    damDisplayTagNumber: "12",
                    offspringCount: 1
                )
            ]
        )

        let data = DashboardPresentationData(snapshot: snapshot, fieldCheckSessions: [])
        let valuesByID = Dictionary(uniqueKeysWithValues: data.offspringByDam.map { ($0.id, $0) })

        XCTAssertEqual(valuesByID[firstDamID]?.label, "UT (1)")
        XCTAssertEqual(valuesByID[secondDamID]?.label, "UT (2)")
        XCTAssertEqual(valuesByID[uniqueDamID]?.label, "12")
        XCTAssertEqual(Set(data.offspringByDam.map(\.id)), Set([firstDamID, secondDamID, uniqueDamID]))
        XCTAssertEqual(Set(data.offspringByDam.map(\.label)).count, 3)
    }

    func testOffspringByDamLabelsStayDistinctWhenTagMatchesGeneratedSuffix() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let suffixTagID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let metrics = [
            DashboardOffspringDamMetric(damID: firstID, damDisplayTagNumber: "12", offspringCount: 2),
            DashboardOffspringDamMetric(damID: secondID, damDisplayTagNumber: "12", offspringCount: 1),
            DashboardOffspringDamMetric(damID: suffixTagID, damDisplayTagNumber: "12 (1)", offspringCount: 3)
        ]

        let original = DashboardPresentationData(
            snapshot: makeSnapshot(pastures: [], offspringByDam: metrics),
            fieldCheckSessions: []
        ).offspringByDam
        let reordered = DashboardPresentationData(
            snapshot: makeSnapshot(pastures: [], offspringByDam: metrics.reversed()),
            fieldCheckSessions: []
        ).offspringByDam

        let labelsByID = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0.label) })
        XCTAssertEqual(labelsByID[firstID], "12 (1) [1]")
        XCTAssertEqual(labelsByID[secondID], "12 (2)")
        XCTAssertEqual(labelsByID[suffixTagID], "12 (1)")
        XCTAssertEqual(Set(original.map(\.label)).count, original.count)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: reordered.map { ($0.id, $0.label) }),
            labelsByID
        )
    }

    private func makeSnapshot(
        pastures: [DashboardPastureItem],
        offspringByDam: [DashboardOffspringDamMetric] = []
    ) -> DashboardSnapshot {
        DashboardSnapshot(
            activeSession: nil,
            alerts: [],
            overview: DashboardOverview(
                activeAnimalCount: 0,
                workingPenCount: 0,
                unassignedAnimalCount: 0,
                pastureCount: pastures.count,
                underutilizedPastureCount: 0,
                rotationReadyPastureCount: 0
            ),
            analytics: DashboardAnalytics(
                lifecycleMetrics: [],
                seasonalCalvingCounts: [],
                offspringByDam: offspringByDam,
                monthlyMedicalRecords: [],
                pinkEyeCasesByYear: [],
                statusOutcomesByYear: []
            ),
            searchableAnimals: [],
            pastures: pastures
        )
    }

    private func makePasture(
        id: UUID,
        name: String,
        activeAnimalCount: Int,
        acres: Double,
        usableAcreage: Double? = nil,
        targetAcresPerHead: Double,
        lastGrazedDate: Date? = nil,
        restDays: Int? = nil
    ) -> DashboardPastureItem {
        DashboardPastureItem(
            id: id,
            name: name,
            activeAnimalCount: activeAnimalCount,
            metrics: PastureMetrics(
                acreage: acres,
                usableAcreage: usableAcreage,
                activeAnimals: activeAnimalCount,
                targetAcresPerHead: targetAcresPerHead
            ),
            lastGrazedDate: lastGrazedDate,
            restDays: restDays
        )
    }
}
