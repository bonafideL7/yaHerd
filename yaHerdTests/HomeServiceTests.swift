import XCTest
@testable import yaHerd

final class HomeServiceTests: XCTestCase {
    func testPastureCheckStartPasturesComeFromDashboardPastures() {
        let now = date(year: 2026, month: 1, day: 10)
        let alphaID = UUID()
        let betaID = UUID()
        let gammaID = UUID()
        let deltaID = UUID()

        let records = DashboardRecords(
            animals: [],
            pastures: [
                pasture(id: alphaID, name: "Alpha", activeAnimalCount: 12),
                pasture(id: betaID, name: "Beta", activeAnimalCount: 8),
                pasture(id: gammaID, name: "Gamma", activeAnimalCount: 16),
                pasture(id: deltaID, name: "Delta", activeAnimalCount: 5)
            ],
            workingSessions: []
        )
        let sessions = [
            fieldCheck(id: UUID(), pastureID: alphaID, startedAt: date(year: 2026, month: 1, day: 8), completedAt: date(year: 2026, month: 1, day: 8)),
            fieldCheck(id: UUID(), pastureID: betaID, startedAt: date(year: 2025, month: 12, day: 20), completedAt: date(year: 2025, month: 12, day: 20)),
            fieldCheck(id: UUID(), pastureID: gammaID, startedAt: date(year: 2026, month: 1, day: 9), completedAt: nil)
        ]

        let snapshot = HomeService().makeSnapshot(
            dashboardRecords: records,
            fieldCheckSessions: sessions,
            openFindings: [],
            protocolTemplates: [],
            configuration: configuration,
            now: now
        )

        XCTAssertEqual(snapshot.pastureCheckStartPastures.map(\.name), ["Alpha", "Beta", "Delta", "Gamma"])
    }

    func testRecordsCleanupRowsComeFromHomeSnapshot() {
        let animalMissingPasture = animal(tag: "10", sex: .female, status: .active, isArchived: false, pastureID: nil, location: .pasture)
        let animalMissingTag = animal(tag: "   ", sex: .female, status: .active, isArchived: false, pastureID: UUID(), location: .pasture)
        let animalUnknownSex = animal(tag: "12", sex: .unknown, status: .active, isArchived: false, pastureID: UUID(), location: .pasture)
        let archivedActive = animal(tag: "13", sex: .female, status: .active, isArchived: true, pastureID: UUID(), location: .pasture)

        let records = DashboardRecords(
            animals: [animalMissingPasture, animalMissingTag, animalUnknownSex, archivedActive],
            pastures: [pasture(id: UUID(), name: "North", activeAnimalCount: 3)],
            workingSessions: []
        )

        let snapshot = HomeService().makeSnapshot(
            dashboardRecords: records,
            fieldCheckSessions: [],
            openFindings: [],
            protocolTemplates: [],
            configuration: configuration,
            now: date(year: 2026, month: 1, day: 10)
        )

        XCTAssertEqual(snapshot.unassignedAnimalRecords.map(\.id), [animalMissingPasture.id])
        XCTAssertEqual(snapshot.missingTagAnimals.map(\.id), [animalMissingTag.id])
        XCTAssertEqual(snapshot.unknownSexAnimals.map(\.id), [animalUnknownSex.id])
        XCTAssertEqual(snapshot.archivedActiveRecords.map(\.id), [archivedActive.id])
        let cleanupRowCount = [
            snapshot.unassignedAnimalRecords,
            snapshot.missingTagAnimals,
            snapshot.unknownSexAnimals,
            snapshot.archivedActiveRecords
        ].filter { !$0.isEmpty }.count

        XCTAssertEqual(cleanupRowCount, 4)
        XCTAssertTrue(snapshot.hasRecordsCleanupRows)
    }

    private var configuration: DashboardConfiguration {
        DashboardConfiguration()
    }

    private func pasture(id: UUID, name: String, activeAnimalCount: Int) -> DashboardPastureRecord {
        DashboardPastureRecord(
            id: id,
            name: name,
            acreage: 10,
            usableAcreage: nil,
            targetAcresPerHead: 2,
            activeAnimalCount: activeAnimalCount,
            lastGrazedDate: nil,
            restDays: nil
        )
    }

    private func animal(
        tag: String,
        sex: Sex,
        status: AnimalStatus,
        isArchived: Bool,
        pastureID: UUID?,
        location: AnimalLocation
    ) -> DashboardAnimalRecord {
        DashboardAnimalRecord(
            id: UUID(),
            displayTagNumber: tag,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: sex,
            animalType: .cow,
            status: status,
            isArchived: isArchived,
            pastureID: pastureID,
            pastureName: pastureID == nil ? nil : "North",
            location: location,
            lastPregnancyCheckDate: nil,
            lastPregnancyStatus: nil,
            expectedCalvingDate: nil,
            lastTreatmentDate: nil,
            birthDate: date(year: 2024, month: 1, day: 1),
            saleDate: nil,
            deathDate: nil,
            healthRecords: [],
            offspringCount: 0
        )
    }

    private func fieldCheck(
        id: UUID,
        pastureID: UUID,
        startedAt: Date,
        completedAt: Date?
    ) -> FieldCheckSessionSummary {
        FieldCheckSessionSummary(
            id: id,
            startedAt: startedAt,
            completedAt: completedAt,
            pastureID: pastureID,
            pastureName: nil,
            expectedHeadCountSnapshot: 0,
            quickCowCount: 0,
            quickHeiferCount: 0,
            quickCalfCount: 0,
            quickBullCount: 0,
            quickSteerCount: 0,
            animalChecks: [],
            openFindingsCount: 0
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
