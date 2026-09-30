import XCTest
@testable import yaHerd

/// Permanent persistence-neutral integration coverage for Working session state consumed by
/// Dashboard/Home read models.
///
/// Working lifecycle, validation, rollback, historical snapshot, and work-data semantics remain
/// owned by the permanent Working contracts. This contract owns only the cross-feature requirement
/// that committed Working session state is projected consistently through synchronous and
/// production Dashboard/Home readers.
@MainActor
struct WorkingDashboardReadModelContractFixture {
    let workingFixture: WorkingRepositoryContractFixture
    let makeDashboardRepository: () -> any DashboardRepository
    let makeDashboardQueryReader: () -> any DashboardQueryReading
}

@MainActor
enum WorkingDashboardReadModelContract {
    static func assertWorkingLifecyclePropagatesToDashboardAndHome(
        using fixture: WorkingDashboardReadModelContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let controlSource = try WorkingRepositoryContract.makePasture(
            named: "Dashboard Working Control Source",
            using: fixture.workingFixture
        )
        let controlAnimal = try WorkingRepositoryContract.makeAnimal(
            name: "Dashboard Working Control Cow",
            tagNumber: "DWC01",
            sex: .female,
            pastureID: controlSource.id,
            using: fixture.workingFixture
        )
        let controlWorking = fixture.workingFixture.makeWorkingRepository()
        let controlSessionID = try controlWorking.startSession(
            input: WorkingSessionStartInput(
                date: WorkingRepositoryContract.date(year: 2026, month: 9, day: 20, hour: 8),
                sourcePastureID: controlSource.id,
                treatmentTemplateName: "Historical Control Work",
                plannedTreatments: [],
                animalIDs: [controlAnimal.id]
            )
        )
        let controlSummaryBefore = try XCTUnwrap(
            fixture.workingFixture.makeWorkingRepository()
                .fetchSessions()
                .first { $0.id == controlSessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(controlSummaryBefore.status, .active, file: file, line: line)
        let controlDashboardBefore = try await fetchProductionDashboardRecord(
            sessionID: controlSessionID,
            reader: fixture.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        assertDashboardRecord(
            controlDashboardBefore,
            matches: controlSummaryBefore,
            file: file,
            line: line
        )

        let targetSource = try WorkingRepositoryContract.makePasture(
            named: "Dashboard Working Target Source",
            using: fixture.workingFixture
        )
        let first = try WorkingRepositoryContract.makeAnimal(
            name: "Dashboard Working First Cow",
            tagNumber: "DWT01",
            sex: .female,
            pastureID: targetSource.id,
            using: fixture.workingFixture
        )
        let second = try WorkingRepositoryContract.makeAnimal(
            name: "Dashboard Working Second Cow",
            tagNumber: "DWT02",
            sex: .female,
            pastureID: targetSource.id,
            using: fixture.workingFixture
        )

        let targetWorking = fixture.workingFixture.makeWorkingRepository()
        let targetSessionID = try targetWorking.startSession(
            input: WorkingSessionStartInput(
                date: WorkingRepositoryContract.date(year: 2026, month: 9, day: 21, hour: 9),
                sourcePastureID: targetSource.id,
                treatmentTemplateName: "  Dashboard Contract Work  ",
                plannedTreatments: [],
                animalIDs: [first.id]
            )
        )
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 1,
            expectedCompletedQueueItems: 0,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        try targetWorking.collectAnimals(sessionID: targetSessionID, animalIDs: [second.id])
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 0,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        let collected = try XCTUnwrap(
            fixture.workingFixture.makeWorkingRepository().fetchSessionDetail(id: targetSessionID),
            file: file,
            line: line
        )
        let firstQueueItemID = try XCTUnwrap(
            collected.queueItems.first { $0.animalID == first.id }?.id,
            file: file,
            line: line
        )
        let secondQueueItemID = try XCTUnwrap(
            collected.queueItems.first { $0.animalID == second.id }?.id,
            file: file,
            line: line
        )

        try targetWorking.complete(
            queueItemID: firstQueueItemID,
            inSessionID: targetSessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 1,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        try targetWorking.saveEdits(
            forQueueItemID: secondQueueItemID,
            inSessionID: targetSessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: nil,
                destinationPastureID: nil,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: ""
            )
        )
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 2,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        try targetWorking.deleteWorkData(
            forQueueItemID: firstQueueItemID,
            inSessionID: targetSessionID
        )
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 1,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        try targetWorking.saveEdits(
            forQueueItemID: secondQueueItemID,
            inSessionID: targetSessionID,
            input: WorkingSessionAnimalEditInput(
                status: .queued,
                completedAt: nil,
                destinationPastureID: nil,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: ""
            )
        )
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 0,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        for queueItemID in [firstQueueItemID, secondQueueItemID] {
            try targetWorking.complete(
                queueItemID: queueItemID,
                inSessionID: targetSessionID,
                treatmentEntries: [],
                pregnancyCheck: nil,
                markCastrated: false,
                observationNotes: ""
            )
        }
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 2,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        try targetWorking.completeSession(
            id: targetSessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: firstQueueItemID,
                    destinationPastureID: targetSource.id
                ),
                WorkingQueueDestinationAssignment(
                    queueItemID: secondQueueItemID,
                    destinationPastureID: targetSource.id
                )
            ]
        )
        try await assertFinishedSessionExcludedFromDashboard(
            sessionID: targetSessionID,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 2,
            expectedActiveSessionID: controlSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        try targetWorking.reopenSession(id: targetSessionID)
        try await assertSessionProjection(
            sessionID: targetSessionID,
            expectedStatus: .active,
            expectedTotalQueueItems: 2,
            expectedCompletedQueueItems: 2,
            expectedActiveSessionID: targetSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        try targetWorking.deleteSession(id: targetSessionID)
        try await assertSessionAbsent(
            sessionID: targetSessionID,
            expectedActiveSessionID: controlSessionID,
            expectedWorkingHistory: true,
            fixture: fixture,
            file: file,
            line: line
        )

        let controlSummaryAfterTargetLifecycle = try XCTUnwrap(
            fixture.workingFixture.makeWorkingRepository()
                .fetchSessions()
                .first { $0.id == controlSessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlSummaryAfterTargetLifecycle,
            controlSummaryBefore,
            "Target Working lifecycle mutations must not rewrite an unrelated active session summary.",
            file: file,
            line: line
        )
        let controlDashboardAfterTargetLifecycle = try await fetchProductionDashboardRecord(
            sessionID: controlSessionID,
            reader: fixture.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlDashboardAfterTargetLifecycle,
            controlDashboardBefore,
            "Target Working lifecycle mutations must not rewrite an unrelated Dashboard/Home session record.",
            file: file,
            line: line
        )

        try fixture.workingFixture.makeWorkingRepository().deleteSession(id: controlSessionID)
        try await assertSessionAbsent(
            sessionID: controlSessionID,
            expectedActiveSessionID: nil,
            expectedWorkingHistory: false,
            fixture: fixture,
            file: file,
            line: line
        )
    }

    private static func assertSessionProjection(
        sessionID: UUID,
        expectedStatus: WorkingSessionStatus,
        expectedTotalQueueItems: Int,
        expectedCompletedQueueItems: Int,
        expectedActiveSessionID: UUID?,
        expectedWorkingHistory: Bool,
        fixture: WorkingDashboardReadModelContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let freshWorking = fixture.workingFixture.makeWorkingRepository()
        let detail = try XCTUnwrap(
            freshWorking.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let summary = try XCTUnwrap(
            freshWorking.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )

        XCTAssertEqual(detail.id, summary.id, file: file, line: line)
        XCTAssertEqual(detail.date, summary.date, file: file, line: line)
        XCTAssertEqual(detail.status, expectedStatus, file: file, line: line)
        XCTAssertEqual(summary.status, expectedStatus, file: file, line: line)
        XCTAssertEqual(detail.sourcePastureName, summary.sourcePastureName, file: file, line: line)
        XCTAssertEqual(detail.treatmentTemplateName, summary.treatmentTemplateName, file: file, line: line)
        XCTAssertEqual(detail.queueItems.count, expectedTotalQueueItems, file: file, line: line)
        XCTAssertEqual(summary.totalQueueItems, expectedTotalQueueItems, file: file, line: line)
        XCTAssertEqual(
            detail.queueItems.filter { $0.status == .done }.count,
            expectedCompletedQueueItems,
            file: file,
            line: line
        )
        XCTAssertEqual(summary.completedQueueItems, expectedCompletedQueueItems, file: file, line: line)

        let synchronousRecords = try fixture.makeDashboardRepository().fetchDashboardRecords()
        let synchronousRecord = try XCTUnwrap(
            synchronousRecords.workingSessions.first { $0.id == sessionID },
            file: file,
            line: line
        )
        assertDashboardRecord(synchronousRecord, matches: summary, file: file, line: line)

        let productionRecords = try await fixture.makeDashboardQueryReader().fetchDashboardRecords()
        let productionRecord = try XCTUnwrap(
            productionRecords.workingSessions.first { $0.id == sessionID },
            file: file,
            line: line
        )
        assertDashboardRecord(productionRecord, matches: summary, file: file, line: line)
        XCTAssertEqual(productionRecord, synchronousRecord, file: file, line: line)

        assertDashboardAndHomeDerivedState(
            records: productionRecords,
            expectedActiveSessionID: expectedActiveSessionID,
            expectedWorkingHistory: expectedWorkingHistory,
            file: file,
            line: line
        )
    }

    private static func assertFinishedSessionExcludedFromDashboard(
        sessionID: UUID,
        expectedTotalQueueItems: Int,
        expectedCompletedQueueItems: Int,
        expectedActiveSessionID: UUID?,
        expectedWorkingHistory: Bool,
        fixture: WorkingDashboardReadModelContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let freshWorking = fixture.workingFixture.makeWorkingRepository()
        let detail = try XCTUnwrap(
            freshWorking.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let summary = try XCTUnwrap(
            freshWorking.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )

        XCTAssertEqual(detail.id, summary.id, file: file, line: line)
        XCTAssertEqual(detail.status, .finished, file: file, line: line)
        XCTAssertEqual(summary.status, .finished, file: file, line: line)
        XCTAssertEqual(detail.queueItems.count, expectedTotalQueueItems, file: file, line: line)
        XCTAssertEqual(summary.totalQueueItems, expectedTotalQueueItems, file: file, line: line)
        XCTAssertEqual(
            detail.queueItems.filter { $0.status == .done }.count,
            expectedCompletedQueueItems,
            file: file,
            line: line
        )
        XCTAssertEqual(summary.completedQueueItems, expectedCompletedQueueItems, file: file, line: line)

        let synchronousRecords = try fixture.makeDashboardRepository().fetchDashboardRecords()
        XCTAssertFalse(
            synchronousRecords.workingSessions.contains { $0.id == sessionID },
            "Finished Working sessions must be excluded from the synchronous Dashboard projection.",
            file: file,
            line: line
        )

        let productionRecords = try await fixture.makeDashboardQueryReader().fetchDashboardRecords()
        XCTAssertFalse(
            productionRecords.workingSessions.contains { $0.id == sessionID },
            "Finished Working sessions must be excluded from the production Dashboard projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            productionRecords.workingSessions,
            synchronousRecords.workingSessions,
            "Synchronous and production Dashboard readers must agree on the active-only Working-session projection.",
            file: file,
            line: line
        )
        assertDashboardAndHomeDerivedState(
            records: productionRecords,
            expectedActiveSessionID: expectedActiveSessionID,
            expectedWorkingHistory: expectedWorkingHistory,
            file: file,
            line: line
        )
    }

    private static func assertSessionAbsent(
        sessionID: UUID,
        expectedActiveSessionID: UUID?,
        expectedWorkingHistory: Bool,
        fixture: WorkingDashboardReadModelContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let freshWorking = fixture.workingFixture.makeWorkingRepository()
        XCTAssertNil(try freshWorking.fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertFalse(
            try freshWorking.fetchSessions().contains { $0.id == sessionID },
            file: file,
            line: line
        )

        let synchronousRecords = try fixture.makeDashboardRepository().fetchDashboardRecords()
        XCTAssertFalse(
            synchronousRecords.workingSessions.contains { $0.id == sessionID },
            file: file,
            line: line
        )

        let productionRecords = try await fixture.makeDashboardQueryReader().fetchDashboardRecords()
        XCTAssertFalse(
            productionRecords.workingSessions.contains { $0.id == sessionID },
            file: file,
            line: line
        )
        assertDashboardAndHomeDerivedState(
            records: productionRecords,
            expectedActiveSessionID: expectedActiveSessionID,
            expectedWorkingHistory: expectedWorkingHistory,
            file: file,
            line: line
        )
    }

    private static func fetchProductionDashboardRecord(
        sessionID: UUID,
        reader: any DashboardQueryReading,
        file: StaticString,
        line: UInt
    ) async throws -> DashboardWorkingSessionRecord {
        let records = try await reader.fetchDashboardRecords()
        return try XCTUnwrap(
            records.workingSessions.first { $0.id == sessionID },
            file: file,
            line: line
        )
    }

    private static func assertDashboardRecord(
        _ record: DashboardWorkingSessionRecord,
        matches summary: WorkingSessionSummary,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(record.id, summary.id, file: file, line: line)
        XCTAssertEqual(record.date, summary.date, file: file, line: line)
        XCTAssertEqual(record.isActive, summary.status == .active, file: file, line: line)
        XCTAssertEqual(record.sourcePastureName, summary.sourcePastureName, file: file, line: line)
        XCTAssertEqual(record.treatmentTemplateName, summary.treatmentTemplateName, file: file, line: line)
        XCTAssertEqual(record.totalQueueItems, summary.totalQueueItems, file: file, line: line)
        XCTAssertEqual(record.completedQueueItems, summary.completedQueueItems, file: file, line: line)
    }

    private static func assertDashboardAndHomeDerivedState(
        records: DashboardRecords,
        expectedActiveSessionID: UUID?,
        expectedWorkingHistory: Bool,
        file: StaticString,
        line: UInt
    ) {
        let configuration = DashboardConfiguration()
        let dashboard = DashboardService().makeSnapshot(
            records: records,
            configuration: configuration
        )
        XCTAssertTrue(
            records.workingSessions.allSatisfy(\.isActive),
            "Dashboard/Home Working-session records must remain an active-only projection.",
            file: file,
            line: line
        )

        let expectedActiveSession: DashboardWorkingSessionSummary?
        if let expectedActiveSessionID {
            guard let record = records.workingSessions.first(where: { $0.id == expectedActiveSessionID }) else {
                XCTFail(
                    "The expected active Working session must be present in Dashboard/Home records.",
                    file: file,
                    line: line
                )
                return
            }
            XCTAssertTrue(record.isActive, file: file, line: line)
            expectedActiveSession = DashboardWorkingSessionSummary(
                id: record.id,
                date: record.date,
                sourcePastureName: record.sourcePastureName,
                treatmentTemplateName: record.treatmentTemplateName,
                totalQueueItems: record.totalQueueItems,
                completedQueueItems: record.completedQueueItems
            )
        } else {
            expectedActiveSession = nil
        }
        XCTAssertEqual(dashboard.activeSession, expectedActiveSession, file: file, line: line)

        let home = HomeService().makeSnapshot(
            dashboardRecords: records,
            fieldCheckSessions: [],
            openFindings: [],
            treatmentTemplates: [],
            configuration: configuration
        )
        XCTAssertEqual(home.activeSession, dashboard.activeSession, file: file, line: line)
        XCTAssertEqual(home.hasWorkingSessionHistory, expectedWorkingHistory, file: file, line: line)
    }
}
