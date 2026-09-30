import Foundation
import XCTest
@testable import yaHerd

/// Permanent persistence-neutral integration coverage for the two non-Dashboard read models used by
/// `LoadHomeUseCase`.
///
/// Field Check and Working contracts remain the owners of mutation validation, rollback, history,
/// and feature-local read semantics. This contract owns only the requirement that committed feature
/// state is projected consistently through the production async Home readers.
@MainActor
struct HomeSupportingReadModelContractFixture {
    let fieldCheckFixture: FieldCheckRepositoryContractFixture
    let workingFixture: WorkingRepositoryContractFixture
    let makeHomeFieldCheckQueryReader: () -> any HomeFieldCheckQueryReading
    let makeHomeWorkingQueryReader: () -> any HomeWorkingQueryReading
}

@MainActor
enum HomeSupportingReadModelContract {
    static func assertFieldCheckStatePropagatesToHomeReadModel(
        using fixture: HomeSupportingReadModelContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fieldCheckFixture = fixture.fieldCheckFixture
        let pasture = try fieldCheckFixture.makePastureRepository().create(
            input: PastureInput(
                name: "Home Field Check Contract Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try fieldCheckFixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Home Field Check Contract Cow",
                tagNumber: "HFC01",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSince1970: 1_640_995_200),
                status: .active,
                pastureID: pasture.id,
                sireID: nil,
                damID: nil,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            )
        )

        let writer = fieldCheckFixture.makeFieldCheckRepository()
        let controlSessionID = try writer.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_790_000_000),
                notes: "Home history control"
            )
        )
        try writer.completeSession(id: controlSessionID)

        let controlBefore = try XCTUnwrap(
            fieldCheckFixture.makeFieldCheckRepository()
                .fetchSessions()
                .first { $0.id == controlSessionID },
            file: file,
            line: line
        )
        XCTAssertTrue(controlBefore.isCompleted, file: file, line: line)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [],
            expectedOpenFindingCount: 0,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        let unfinishedSessionID = try writer.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_790_000_100),
                notes: "Home unfinished warning"
            )
        )
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [unfinishedSessionID],
            expectedOpenFindingCount: 0,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        let missingSessionID = try writer.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_790_000_200),
                notes: "Home missing warning"
            )
        )
        let missingCheckID = try XCTUnwrap(
            writer.fetchSessionDetail(id: missingSessionID)?.animalChecks.first?.id,
            file: file,
            line: line
        )
        try writer.setAnimalCheckMissing(
            sessionID: missingSessionID,
            animalCheckID: missingCheckID,
            isMissing: true
        )
        try writer.completeSession(id: missingSessionID)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [missingSessionID, unfinishedSessionID],
            expectedOpenFindingCount: 0,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        let firstFindingSessionID = try writer.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_790_000_300),
                notes: "Home first finding warning"
            )
        )
        try writer.addFinding(
            sessionID: firstFindingSessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_790_000_310),
                type: .fenceIssue,
                severity: .warning,
                status: .open,
                note: "First Home open finding",
                animalID: nil
            )
        )
        let firstFindingID = try XCTUnwrap(
            writer.fetchSessionDetail(id: firstFindingSessionID)?
                .findings
                .first { $0.note == "First Home open finding" }?
                .id,
            file: file,
            line: line
        )
        try writer.completeSession(id: firstFindingSessionID)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [
                firstFindingSessionID,
                missingSessionID,
                unfinishedSessionID
            ],
            expectedOpenFindingCount: 1,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        let secondFindingSessionID = try writer.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_790_000_400),
                notes: "Home second finding warning"
            )
        )
        try writer.addFinding(
            sessionID: secondFindingSessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 1_790_000_410),
                type: .waterIssue,
                severity: .critical,
                status: .monitoring,
                note: "Second Home open finding",
                animalID: nil
            )
        )
        let secondFindingID = try XCTUnwrap(
            writer.fetchSessionDetail(id: secondFindingSessionID)?
                .findings
                .first { $0.note == "Second Home open finding" }?
                .id,
            file: file,
            line: line
        )
        try writer.completeSession(id: secondFindingSessionID)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [
                secondFindingSessionID,
                firstFindingSessionID,
                missingSessionID,
                unfinishedSessionID
            ],
            expectedOpenFindingCount: 2,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        try writer.reopenSession(id: firstFindingSessionID)
        try writer.updateFindingStatus(
            sessionID: firstFindingSessionID,
            findingID: firstFindingID,
            status: .resolved
        )
        try writer.completeSession(id: firstFindingSessionID)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [
                secondFindingSessionID,
                missingSessionID,
                unfinishedSessionID
            ],
            expectedOpenFindingCount: 1,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        try writer.reopenSession(id: secondFindingSessionID)
        try writer.updateFindingStatus(
            sessionID: secondFindingSessionID,
            findingID: secondFindingID,
            status: .resolved
        )
        try writer.completeSession(id: secondFindingSessionID)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [
                missingSessionID,
                unfinishedSessionID
            ],
            expectedOpenFindingCount: 0,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        try writer.reopenSession(id: missingSessionID)
        try writer.setAnimalCheckMissing(
            sessionID: missingSessionID,
            animalCheckID: missingCheckID,
            isMissing: false
        )
        try writer.completeSession(id: missingSessionID)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [unfinishedSessionID],
            expectedOpenFindingCount: 0,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        try writer.completeSession(id: unfinishedSessionID)
        try await assertFieldCheckHomeState(
            expectedWarningSessionIDs: [],
            expectedOpenFindingCount: 0,
            immediateRepository: writer,
            fixture: fixture,
            file: file,
            line: line
        )

        let controlAfter = try XCTUnwrap(
            fieldCheckFixture.makeFieldCheckRepository()
                .fetchSessions()
                .first { $0.id == controlSessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlAfter,
            controlBefore,
            "Target Field Check warning transitions must not rewrite the completed historical control.",
            file: file,
            line: line
        )
    }

    static func assertTreatmentTemplatesPropagateToHomeReadModel(
        using fixture: HomeSupportingReadModelContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let working = fixture.workingFixture.makeWorkingRepository()

        let controlID = try working.createTemplate(
            name: "Zulu Home Control",
            items: [
                WorkingTreatmentPlanItem(id: UUID(), name: "Control Vaccine"),
                WorkingTreatmentPlanItem(id: UUID(), name: "Control Mineral")
            ]
        )
        let targetID = try working.createTemplate(
            name: "Bravo Home Target",
            items: [
                WorkingTreatmentPlanItem(id: UUID(), name: "Target Vaccine")
            ]
        )

        try await assertTreatmentTemplateHomeState(
            expectedTemplateIDs: [targetID, controlID],
            immediateRepository: working,
            fixture: fixture,
            file: file,
            line: line
        )

        let controlBefore = try XCTUnwrap(
            fixture.workingFixture.makeWorkingRepository()
                .fetchTemplates()
                .first { $0.id == controlID },
            file: file,
            line: line
        )

        try working.updateTemplate(
            id: targetID,
            name: "Alpha Home Target Updated",
            items: [
                WorkingTreatmentPlanItem(id: UUID(), name: "Updated Vaccine"),
                WorkingTreatmentPlanItem(id: UUID(), name: "Updated Dewormer"),
                WorkingTreatmentPlanItem(id: UUID(), name: "Updated Mineral")
            ]
        )
        try await assertTreatmentTemplateHomeState(
            expectedTemplateIDs: [targetID, controlID],
            immediateRepository: working,
            fixture: fixture,
            file: file,
            line: line
        )

        let updatedTarget = try XCTUnwrap(
            fixture.workingFixture.makeWorkingRepository()
                .fetchTemplates()
                .first { $0.id == targetID },
            file: file,
            line: line
        )
        XCTAssertEqual(updatedTarget.name, "Alpha Home Target Updated", file: file, line: line)
        XCTAssertEqual(updatedTarget.treatmentCount, 3, file: file, line: line)

        let firstOnly = try await fixture.makeHomeWorkingQueryReader()
            .fetchHomeTreatmentTemplates(limit: 1)
        XCTAssertEqual(firstOnly, [updatedTarget], file: file, line: line)

        try working.deleteTemplates(ids: [targetID])
        try await assertTreatmentTemplateHomeState(
            expectedTemplateIDs: [controlID],
            immediateRepository: working,
            fixture: fixture,
            file: file,
            line: line
        )

        let controlAfterTargetDeletion = try XCTUnwrap(
            fixture.workingFixture.makeWorkingRepository()
                .fetchTemplates()
                .first { $0.id == controlID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlAfterTargetDeletion,
            controlBefore,
            "Updating and deleting the target template must not rewrite the unrelated control template.",
            file: file,
            line: line
        )

        try working.deleteTemplates(ids: [controlID])
        try await assertTreatmentTemplateHomeState(
            expectedTemplateIDs: [],
            immediateRepository: working,
            fixture: fixture,
            file: file,
            line: line
        )
    }

    private static func assertFieldCheckHomeState(
        expectedWarningSessionIDs: [UUID],
        expectedOpenFindingCount: Int,
        immediateRepository: any FieldCheckRepository,
        fixture: HomeSupportingReadModelContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let immediateSessions = try immediateRepository.fetchSessions()
        let immediateOpenFindings = try immediateRepository.fetchOpenFindings(limit: 250)
        XCTAssertEqual(
            immediateOpenFindings.count,
            expectedOpenFindingCount,
            file: file,
            line: line
        )

        let freshRepository = fixture.fieldCheckFixture.makeFieldCheckRepository()
        let allSessions = try freshRepository.fetchSessions()
        let openFindings = try freshRepository.fetchOpenFindings(limit: 250)
        XCTAssertEqual(immediateSessions, allSessions, file: file, line: line)
        XCTAssertEqual(immediateOpenFindings, openFindings, file: file, line: line)

        let records = try await fixture.makeHomeFieldCheckQueryReader()
            .fetchHomeFieldCheckRecords()
        XCTAssertEqual(records.sessions.map(\.id), expectedWarningSessionIDs, file: file, line: line)
        XCTAssertEqual(records.openFindingCount, expectedOpenFindingCount, file: file, line: line)
        XCTAssertEqual(records.hasHistory, !allSessions.isEmpty, file: file, line: line)

        for summary in records.sessions {
            let authoritativeSummary = try XCTUnwrap(
                allSessions.first { $0.id == summary.id },
                file: file,
                line: line
            )
            XCTAssertEqual(summary, authoritativeSummary, file: file, line: line)
        }

        if expectedOpenFindingCount == 1 {
            XCTAssertEqual(records.openFindings, openFindings, file: file, line: line)
        } else {
            XCTAssertTrue(
                records.openFindings.isEmpty,
                "Home only materializes the finding snapshot when exactly one unresolved finding exists.",
                file: file,
                line: line
            )
        }

        let home = HomeService().makeSnapshot(
            dashboardRecords: DashboardRecords(
                animals: [],
                pastures: [],
                workingSessions: []
            ),
            fieldCheckSessions: records.sessions,
            openFindings: records.openFindings,
            treatmentTemplates: [],
            openFindingCount: records.openFindingCount,
            hasFieldCheckHistory: records.hasHistory,
            configuration: DashboardConfiguration()
        )
        XCTAssertEqual(
            home.activeCheckSessions.map(\.id),
            records.sessions.filter { !$0.isCompleted }.map(\.id),
            file: file,
            line: line
        )
        XCTAssertEqual(home.openFindings, records.openFindings, file: file, line: line)
        XCTAssertEqual(home.openFindingCount, records.openFindingCount, file: file, line: line)
        XCTAssertEqual(
            Set(home.missingCheckSessions.map(\.id)),
            Set(records.sessions.filter { $0.missingAnimalCount > 0 }.map(\.id)),
            file: file,
            line: line
        )
        XCTAssertEqual(home.hasFieldCheckHistory, records.hasHistory, file: file, line: line)
    }

    private static func assertTreatmentTemplateHomeState(
        expectedTemplateIDs: [UUID],
        immediateRepository: any WorkingRepository,
        fixture: HomeSupportingReadModelContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let immediate = try immediateRepository.fetchTemplates()
        let authoritative = try fixture.workingFixture.makeWorkingRepository().fetchTemplates()
        XCTAssertEqual(immediate, authoritative, file: file, line: line)
        XCTAssertEqual(authoritative.map(\.id), expectedTemplateIDs, file: file, line: line)

        let production = try await fixture.makeHomeWorkingQueryReader()
            .fetchHomeTreatmentTemplates(limit: 250)
        XCTAssertEqual(production, authoritative, file: file, line: line)

        let home = HomeService().makeSnapshot(
            dashboardRecords: DashboardRecords(
                animals: [],
                pastures: [],
                workingSessions: []
            ),
            fieldCheckSessions: [],
            openFindings: [],
            treatmentTemplates: production,
            configuration: DashboardConfiguration()
        )
        XCTAssertEqual(
            home.hasWorkingTreatmentTemplates,
            !authoritative.isEmpty,
            file: file,
            line: line
        )
    }
}
