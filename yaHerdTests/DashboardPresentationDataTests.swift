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

    private func makeSnapshot(pastures: [DashboardPastureItem]) -> DashboardSnapshot {
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
                offspringByDam: [],
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
