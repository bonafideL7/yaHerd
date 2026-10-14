import XCTest
@testable import yaHerd

@MainActor
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
            treatmentTemplates: [],
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
            treatmentTemplates: [],
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

    func testDashboardAndHomeUseCasesDelegateDerivationThroughActorBoundary() async throws {
        let now = date(year: 2026, month: 1, day: 10)
        let pastureID = UUID()
        let records = DashboardRecords(
            animals: [
                animal(
                    tag: "20",
                    sex: .female,
                    status: .active,
                    isArchived: false,
                    pastureID: pastureID,
                    location: .pasture
                )
            ],
            pastures: [
                pasture(id: pastureID, name: "North", activeAnimalCount: 1)
            ],
            workingSessions: []
        )
        let dashboardReader = DashboardUseCaseReader(records: records)
        let deriver = DashboardHomeDerivationProbe()

        let dashboard = try await LoadDashboardUseCase(
            repository: dashboardReader,
            deriver: deriver
        )
        .execute(configuration: configuration)
        let expectedDashboard = DashboardService().makeSnapshot(
            records: records,
            configuration: configuration
        )
        XCTAssertEqual(dashboard, expectedDashboard)

        let activeAnimals = try await LoadDashboardAnimalListUseCase(
            repository: dashboardReader,
            deriver: deriver
        )
        .execute(kind: .active, configuration: configuration)
        XCTAssertEqual(
            activeAnimals,
            DashboardService().makeAnimalList(
                kind: .active,
                records: records,
                configuration: configuration
            )
        )

        let pastureItems = try await LoadDashboardPastureListUseCase(
            repository: dashboardReader,
            deriver: deriver
        )
        .execute(configuration: configuration)
        XCTAssertEqual(
            pastureItems,
            DashboardService().makeSnapshot(
                records: DashboardRecords(
                    animals: [],
                    pastures: records.pastures,
                    workingSessions: []
                ),
                configuration: configuration
            ).pastures
        )

        let fieldCheckRecords = HomeFieldCheckRecords(
            sessions: [],
            openFindings: [],
            openFindingCount: 0,
            hasHistory: false
        )
        let home = try await LoadHomeUseCase(
            dashboardRepository: dashboardReader,
            fieldCheckRepository: HomeFieldCheckUseCaseReader(records: fieldCheckRecords),
            workingRepository: HomeWorkingUseCaseReader(templates: []),
            deriver: deriver
        )
        .execute(configuration: configuration, now: now)

        let expectedHome = HomeService().makeSnapshot(
            dashboardRecords: records,
            fieldCheckSessions: [],
            openFindings: [],
            treatmentTemplates: [],
            openFindingCount: 0,
            hasFieldCheckHistory: false,
            configuration: configuration,
            now: now
        )
        XCTAssertEqual(home, expectedHome)
        let recordedDerivationCalls = await deriver.recordedCalls()
        XCTAssertEqual(
            recordedDerivationCalls,
            [
                .dashboardSnapshot,
                .dashboardAnimalList(.active),
                .dashboardPastureList,
                .homeSnapshot
            ]
        )
    }


    func testDashboardDerivationKeepsIdenticalTagNameAndSessionDateRecordsStable() {
        let earlier = stableID(1)
        let later = stableID(2)
        let control = stableID(3)
        let timestamp = date(year: 2026, month: 9, day: 20)
        let firstAnimal = animal(
            id: earlier, tag: "", sex: .female, status: .active,
            isArchived: false, pastureID: nil, location: .pasture
        )
        let secondAnimal = animal(
            id: later, tag: "", sex: .female, status: .active,
            isArchived: false, pastureID: nil, location: .pasture
        )
        let taggedControl = animal(
            id: control, tag: "19", sex: .male, status: .active,
            isArchived: false, pastureID: control, location: .pasture
        )
        let firstPasture = pasture(id: earlier, name: "North", activeAnimalCount: 2)
        let secondPasture = pasture(id: later, name: "North", activeAnimalCount: 2)
        let controlPasture = pasture(id: control, name: "South", activeAnimalCount: 1)
        let sessions = [
            workingSession(id: later, date: timestamp, isActive: true),
            workingSession(id: earlier, date: timestamp, isActive: true),
            workingSession(id: control, date: timestamp, isActive: false),
            workingSession(id: stableID(4), date: timestamp.addingTimeInterval(-60), isActive: true)
        ]
        let records = DashboardRecords(
            animals: [secondAnimal, taggedControl, firstAnimal],
            pastures: [secondPasture, controlPasture, firstPasture],
            workingSessions: sessions
        )
        let reversed = DashboardRecords(
            animals: Array(records.animals.reversed()),
            pastures: Array(records.pastures.reversed()),
            workingSessions: Array(sessions.reversed())
        )
        let service = DashboardService()
        let original = service.makeSnapshot(records: records, configuration: configuration)
        let reloaded = service.makeSnapshot(records: reversed, configuration: configuration)

        XCTAssertEqual(original.searchableAnimals.map(\.id), [earlier, later, control])
        XCTAssertEqual(original.pastures.map(\.id), [earlier, later, control])
        XCTAssertEqual(original.activeSession?.id, earlier)
        XCTAssertEqual(original, reloaded)
        XCTAssertEqual(
            service.makeAnimalList(kind: .unassigned, records: records, configuration: configuration).map(\.id),
            [earlier, later]
        )
        XCTAssertEqual(
            service.makeAnimalList(kind: .unassigned, records: reversed, configuration: configuration).map(\.id),
            [earlier, later]
        )
    }

    func testHomeDerivationKeepsEqualKeyFieldChecksCleanupAndPastureRowsStable() {
        let earlier = stableID(11)
        let later = stableID(12)
        let archivedFirst = stableID(13)
        let archivedSecond = stableID(14)
        let timestamp = date(year: 2026, month: 9, day: 20)
        let warning = FieldCheckAnimalCheckSnapshot(
            id: stableID(20), animalID: earlier, displayTagNumber: "",
            displayTagColorID: nil, damDisplayTagNumber: nil, damDisplayTagColorID: nil,
            animalName: "", animalSex: .female, animalType: .cow,
            wasExpectedAtStart: true, wasCounted: false,
            needsAttention: true, isMissing: true
        )
        let checks = [
            fieldCheck(id: later, pastureID: later, startedAt: timestamp, completedAt: nil, animalChecks: [warning]),
            fieldCheck(id: archivedFirst, pastureID: earlier, startedAt: timestamp, completedAt: timestamp, animalChecks: [warning]),
            fieldCheck(id: earlier, pastureID: earlier, startedAt: timestamp, completedAt: nil, animalChecks: [warning])
        ]
        let records = DashboardRecords(
            animals: [
                animal(id: later, tag: "", sex: .female, status: .active, isArchived: false, pastureID: nil, location: .workingPen),
                animal(id: archivedSecond, tag: "X", sex: .female, status: .active, isArchived: true, pastureID: nil, location: .pasture),
                animal(id: earlier, tag: "", sex: .female, status: .active, isArchived: false, pastureID: nil, location: .workingPen),
                animal(id: archivedFirst, tag: "X", sex: .female, status: .active, isArchived: true, pastureID: nil, location: .pasture)
            ],
            pastures: [
                pasture(id: later, name: "Equal", activeAnimalCount: 1, targetAcresPerHead: nil),
                pasture(id: earlier, name: "Equal", activeAnimalCount: 1, targetAcresPerHead: nil),
                pasture(id: stableID(16), name: "Underused", activeAnimalCount: 1),
                pasture(id: stableID(15), name: "Underused", activeAnimalCount: 1)
            ],
            workingSessions: []
        )
        let backwards = DashboardRecords(
            animals: Array(records.animals.reversed()),
            pastures: Array(records.pastures.reversed()),
            workingSessions: []
        )
        let service = HomeService()
        let original = service.makeSnapshot(
            dashboardRecords: records, fieldCheckSessions: checks, openFindings: [],
            treatmentTemplates: [], configuration: configuration, now: timestamp
        )
        let reloaded = service.makeSnapshot(
            dashboardRecords: backwards, fieldCheckSessions: Array(checks.reversed()), openFindings: [],
            treatmentTemplates: [], configuration: configuration, now: timestamp
        )

        XCTAssertEqual(original, reloaded)
        XCTAssertEqual(original.activeAnimalRecords.map(\.id), [earlier, later])
        XCTAssertEqual(original.workingPenAnimalRecords.map(\.id), [earlier, later])
        XCTAssertEqual(original.missingTagAnimals.map(\.id), [earlier, later])
        XCTAssertEqual(original.archivedActiveRecords.map(\.id), [archivedFirst, archivedSecond])
        XCTAssertEqual(original.activeCheckSessions.map(\.id), [earlier, later])
        XCTAssertEqual(original.flaggedCheckSessions.map(\.id), [earlier, later, archivedFirst])
        XCTAssertEqual(original.missingCheckSessions.map(\.id), [earlier, later, archivedFirst])
        XCTAssertEqual(original.pasturesMissingStockingData.map(\.id), [earlier, later])
        XCTAssertEqual(original.underutilizedPastures.map(\.id), [stableID(15), stableID(16)])
        XCTAssertEqual(original.rotationReadyPastures.map(\.id), [stableID(15), stableID(16)])
        XCTAssertEqual(original.pastureCheckStartPastures.map(\.id), [
            earlier, later, stableID(15), stableID(16)
        ])
    }

    func testOffspringAnalyticsKeepsTopEightAndHistoricalDamLabelStable() {
        let damIDs = (101...109).map(stableID)
        var offspring: [DashboardAnimalRecord] = []
        for (index, damID) in damIDs.enumerated() {
            let childNumber = 201 + index
            offspring.append(animal(
                id: stableID(childNumber), tag: String(childNumber), sex: .female,
                status: .active, isArchived: false, pastureID: nil, location: .pasture,
                damID: damID, damDisplayTagNumber: "Dam"
            ))
        }
        // The earliest persisted offspring identity supplies the first nonblank
        // historical dam label even if the input relationship order changes.
        offspring[0] = animal(
            id: stableID(201), tag: "201", sex: .female, status: .active,
            isArchived: false, pastureID: nil, location: .pasture,
            damID: damIDs[0], damDisplayTagNumber: "Alpha"
        )
        offspring.append(animal(
            id: stableID(210), tag: "210", sex: .female, status: .active,
            isArchived: false, pastureID: nil, location: .pasture,
            damID: damIDs[0], damDisplayTagNumber: "Zulu"
        ))
        offspring.append(animal(
            id: stableID(211), tag: "211", sex: .female, status: .active,
            isArchived: true, pastureID: nil, location: .pasture,
            damID: damIDs[8], damDisplayTagNumber: "Archived"
        ))
        let now = date(year: 2026, month: 9, day: 20)
        let service = DashboardService()
        let original = service.makeSnapshot(
            records: DashboardRecords(animals: offspring, pastures: [], workingSessions: []),
            configuration: configuration, now: now
        )
        let reloaded = service.makeSnapshot(
            records: DashboardRecords(animals: Array(offspring.reversed()), pastures: [], workingSessions: []),
            configuration: configuration, now: now
        )
        XCTAssertEqual(original.analytics.offspringByDam, reloaded.analytics.offspringByDam)
        XCTAssertEqual(original.analytics.offspringByDam.map(\.damID), Array(damIDs.prefix(8)))
        XCTAssertEqual(original.analytics.offspringByDam.first?.damDisplayTagNumber, "Alpha")
        XCTAssertEqual(original.analytics.offspringByDam.first?.offspringCount, 2)
    }

    private func stableID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private func workingSession(id: UUID, date: Date, isActive: Bool) -> DashboardWorkingSessionRecord {
        DashboardWorkingSessionRecord(
            id: id, date: date, isActive: isActive, sourcePastureName: "North",
            treatmentTemplateName: "", totalQueueItems: 0, completedQueueItems: 0
        )
    }

    private var configuration: DashboardConfiguration {
        DashboardConfiguration()
    }

    private func pasture(
        id: UUID,
        name: String,
        activeAnimalCount: Int,
        targetAcresPerHead: Double? = 2
    ) -> DashboardPastureRecord {
        DashboardPastureRecord(
            id: id,
            name: name,
            acreage: 10,
            usableAcreage: nil,
            targetAcresPerHead: targetAcresPerHead,
            activeAnimalCount: activeAnimalCount,
            lastGrazedDate: nil,
            restDays: nil
        )
    }

    private func animal(
        id: UUID = UUID(),
        tag: String,
        sex: Sex,
        status: AnimalStatus,
        isArchived: Bool,
        pastureID: UUID?,
        location: AnimalLocation,
        damID: UUID? = nil,
        damDisplayTagNumber: String? = nil
    ) -> DashboardAnimalRecord {
        DashboardAnimalRecord(
            id: id,
            displayTagNumber: tag,
            displayTagColorID: nil,
            damID: damID,
            damDisplayTagNumber: damDisplayTagNumber,
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
        completedAt: Date?,
        animalChecks: [FieldCheckAnimalCheckSnapshot] = []
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
            animalChecks: animalChecks,
            openFindingsCount: 0
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}


private enum DashboardHomeDerivationProbeCall: Hashable, Sendable {
    case dashboardSnapshot
    case dashboardAnimalList(DashboardAnimalListKind)
    case dashboardPastureList
    case homeSnapshot
}

private actor DashboardHomeDerivationProbe: DashboardHomeDeriving {
    private let dashboardService = DashboardService()
    private let homeService = HomeService()
    private var calls: [DashboardHomeDerivationProbeCall] = []

    func recordedCalls() -> [DashboardHomeDerivationProbeCall] {
        calls
    }

    func makeDashboardSnapshot(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> DashboardSnapshot {
        calls.append(.dashboardSnapshot)
        return dashboardService.makeSnapshot(
            records: records,
            configuration: configuration,
            now: now
        )
    }

    func makeDashboardAnimalList(
        kind: DashboardAnimalListKind,
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardAnimalItem] {
        calls.append(.dashboardAnimalList(kind))
        return dashboardService.makeAnimalList(
            kind: kind,
            records: records,
            configuration: configuration,
            now: now
        )
    }

    func makeDashboardPastureList(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardPastureItem] {
        calls.append(.dashboardPastureList)
        return dashboardService.makeSnapshot(
            records: records,
            configuration: configuration,
            now: now
        ).pastures
    }

    func makeHomeSnapshot(
        dashboardRecords: DashboardRecords,
        fieldCheckRecords: HomeFieldCheckRecords,
        treatmentTemplates: [WorkingTreatmentTemplateSummary],
        configuration: DashboardConfiguration,
        now: Date
    ) -> HomeSnapshot {
        calls.append(.homeSnapshot)
        return homeService.makeSnapshot(
            dashboardRecords: dashboardRecords,
            fieldCheckSessions: fieldCheckRecords.sessions,
            openFindings: fieldCheckRecords.openFindings,
            treatmentTemplates: treatmentTemplates,
            openFindingCount: fieldCheckRecords.openFindingCount,
            hasFieldCheckHistory: fieldCheckRecords.hasHistory,
            configuration: configuration,
            now: now
        )
    }
}


private actor DashboardUseCaseReader: DashboardQueryReading {
    let records: DashboardRecords

    init(records: DashboardRecords) {
        self.records = records
    }

    func fetchDashboardRecords() async throws -> DashboardRecords {
        records
    }

    func fetchDashboardAnimalRecords(
        kind _: DashboardAnimalListKind
    ) async throws -> [DashboardAnimalRecord] {
        records.animals
    }

    func fetchDashboardPastureRecords() async throws -> [DashboardPastureRecord] {
        records.pastures
    }
}

private actor HomeFieldCheckUseCaseReader: HomeFieldCheckQueryReading {
    let records: HomeFieldCheckRecords

    init(records: HomeFieldCheckRecords) {
        self.records = records
    }

    func fetchHomeFieldCheckRecords() async throws -> HomeFieldCheckRecords {
        records
    }
}

private actor HomeWorkingUseCaseReader: HomeWorkingQueryReading {
    let templates: [WorkingTreatmentTemplateSummary]

    init(templates: [WorkingTreatmentTemplateSummary]) {
        self.templates = templates
    }

    func fetchHomeTreatmentTemplates(limit _: Int) async throws -> [WorkingTreatmentTemplateSummary] {
        templates
    }
}
