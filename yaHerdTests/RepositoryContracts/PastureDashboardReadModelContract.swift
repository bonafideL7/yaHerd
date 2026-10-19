import XCTest
@testable import yaHerd

/// Permanent persistence-neutral integration coverage for live Pasture metadata consumed by
/// Dashboard/Home read models.
///
/// Pasture/group mutation validation and lifecycle semantics remain owned by the existing Pasture
/// contracts. This contract owns only the cross-feature requirement that committed live Pasture
/// metadata is projected consistently through current and production Dashboard readers.
@MainActor
struct PastureDashboardReadModelContractFixture {
    let makePastureRepository: () -> any PastureRepository
    let makeDashboardRepository: () -> any DashboardRepository
    let makeDashboardQueryReader: () -> any DashboardQueryReading
}

@MainActor
enum PastureDashboardReadModelContract {
    static func assertLivePastureMetadataPropagatesToDashboard(
        using fixture: PastureDashboardReadModelContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let pastures = fixture.makePastureRepository()

        let first = try pastures.create(
            input: PastureInput(
                name: "Dashboard Source One",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let second = try pastures.create(
            input: PastureInput(
                name: "Dashboard Source Two",
                acreage: 22,
                usableAcreage: 20,
                targetAcresPerHead: 1.5
            )
        )
        let destination = try pastures.create(
            input: PastureInput(
                name: "Dashboard Destination",
                acreage: 24,
                usableAcreage: 22,
                targetAcresPerHead: 1.4
            )
        )
        let unrelated = try pastures.create(
            input: PastureInput(
                name: "Dashboard Unrelated",
                acreage: 26,
                usableAcreage: 24,
                targetAcresPerHead: 1.3
            )
        )

        let sourceGroup = try pastures.createGroup(
            input: PastureGroupInput(
                name: "Dashboard Source Rotation",
                grazeDays: 5,
                restDays: 20
            )
        )
        let destinationGroup = try pastures.createGroup(
            input: PastureGroupInput(
                name: "Dashboard Destination Rotation",
                grazeDays: 7,
                restDays: 30
            )
        )
        let unrelatedGroup = try pastures.createGroup(
            input: PastureGroupInput(
                name: "Dashboard Unrelated Rotation",
                grazeDays: 4,
                restDays: 40
            )
        )

        try pastures.assignPasture(id: first.id, toGroupID: sourceGroup.id)
        try pastures.assignPasture(id: second.id, toGroupID: sourceGroup.id)
        try pastures.assignPasture(id: destination.id, toGroupID: destinationGroup.id)
        try pastures.assignPasture(id: unrelated.id, toGroupID: unrelatedGroup.id)

        try await assertDashboardPastureMatchesSource(
            pastureID: first.id,
            expectedRestDays: 20,
            fixture: fixture,
            file: file,
            line: line
        )
        try await assertDashboardPastureMatchesSource(
            pastureID: second.id,
            expectedRestDays: 20,
            fixture: fixture,
            file: file,
            line: line
        )
        try await assertDashboardPastureMatchesSource(
            pastureID: destination.id,
            expectedRestDays: 30,
            fixture: fixture,
            file: file,
            line: line
        )
        try await assertDashboardPastureMatchesSource(
            pastureID: unrelated.id,
            expectedRestDays: 40,
            fixture: fixture,
            file: file,
            line: line
        )

        let unrelatedSummaryBefore = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastures().first { $0.id == unrelated.id },
            file: file,
            line: line
        )
        let unrelatedGroupBefore = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastureGroupDetail(id: unrelatedGroup.id),
            file: file,
            line: line
        )
        let unrelatedDashboardBefore = try await fetchProductionDashboardPasture(
            id: unrelated.id,
            reader: fixture.makeDashboardQueryReader(),
            file: file,
            line: line
        )

        let updatedFirst = try pastures.update(
            id: first.id,
            input: PastureInput(
                name: "Dashboard Source One Updated",
                acreage: 31,
                usableAcreage: 29,
                targetAcresPerHead: 1.25
            )
        )
        XCTAssertEqual(updatedFirst.id, first.id, file: file, line: line)
        XCTAssertEqual(updatedFirst.name, "Dashboard Source One Updated", file: file, line: line)
        XCTAssertEqual(updatedFirst.acreage, 31, file: file, line: line)
        XCTAssertEqual(updatedFirst.usableAcreage, 29, file: file, line: line)
        XCTAssertEqual(updatedFirst.targetAcresPerHead, 1.25, file: file, line: line)
        XCTAssertEqual(updatedFirst.groupID, sourceGroup.id, file: file, line: line)
        XCTAssertEqual(updatedFirst.lastGrazedDate, first.lastGrazedDate, file: file, line: line)

        try await assertDashboardPastureMatchesSource(
            pastureID: first.id,
            expectedRestDays: 20,
            fixture: fixture,
            file: file,
            line: line
        )

        let updatedSourceGroup = try pastures.updateGroup(
            id: sourceGroup.id,
            input: PastureGroupInput(
                name: "Dashboard Source Rotation Updated",
                grazeDays: 6,
                restDays: 25
            )
        )
        XCTAssertEqual(updatedSourceGroup.id, sourceGroup.id, file: file, line: line)
        XCTAssertEqual(updatedSourceGroup.restDays, 25, file: file, line: line)
        XCTAssertEqual(
            Set(updatedSourceGroup.pastures.map(\.id)),
            Set([first.id, second.id]),
            "Updating group configuration must preserve both existing members while its derived restDays fans out.",
            file: file,
            line: line
        )

        for pastureID in [first.id, second.id] {
            try await assertDashboardPastureMatchesSource(
                pastureID: pastureID,
                expectedRestDays: 25,
                fixture: fixture,
                file: file,
                line: line
            )
        }
        try await assertDashboardPastureMatchesSource(
            pastureID: destination.id,
            expectedRestDays: 30,
            fixture: fixture,
            file: file,
            line: line
        )

        try pastures.assignPasture(id: first.id, toGroupID: destinationGroup.id)

        let sourceAfterReassignment = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastureGroupDetail(id: sourceGroup.id),
            file: file,
            line: line
        )
        XCTAssertEqual(sourceAfterReassignment.pastures.map(\.id), [second.id], file: file, line: line)

        let destinationAfterReassignment = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastureGroupDetail(id: destinationGroup.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(destinationAfterReassignment.pastures.map(\.id)),
            Set([first.id, destination.id]),
            "Reassignment must preserve the destination group's existing member while adding the moved Pasture.",
            file: file,
            line: line
        )
        try await assertDashboardPastureMatchesSource(
            pastureID: first.id,
            expectedRestDays: 30,
            fixture: fixture,
            file: file,
            line: line
        )
        try await assertDashboardPastureMatchesSource(
            pastureID: second.id,
            expectedRestDays: 25,
            fixture: fixture,
            file: file,
            line: line
        )
        try await assertDashboardPastureMatchesSource(
            pastureID: destination.id,
            expectedRestDays: 30,
            fixture: fixture,
            file: file,
            line: line
        )

        try pastures.assignPasture(id: first.id, toGroupID: nil)
        let unassignedFirst = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastures().first { $0.id == first.id },
            file: file,
            line: line
        )
        XCTAssertNil(unassignedFirst.groupID, file: file, line: line)
        XCTAssertNil(unassignedFirst.groupName, file: file, line: line)
        XCTAssertNil(unassignedFirst.restDays, file: file, line: line)
        try await assertDashboardPastureMatchesSource(
            pastureID: first.id,
            expectedRestDays: nil,
            fixture: fixture,
            file: file,
            line: line
        )

        try pastures.deleteGroups(ids: [sourceGroup.id])
        XCTAssertNil(
            try fixture.makePastureRepository().fetchPastureGroupDetail(id: sourceGroup.id),
            file: file,
            line: line
        )
        let secondAfterGroupDelete = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastures().first { $0.id == second.id },
            file: file,
            line: line
        )
        XCTAssertNil(secondAfterGroupDelete.groupID, file: file, line: line)
        XCTAssertNil(secondAfterGroupDelete.groupName, file: file, line: line)
        XCTAssertNil(secondAfterGroupDelete.restDays, file: file, line: line)
        try await assertDashboardPastureMatchesSource(
            pastureID: second.id,
            expectedRestDays: nil,
            fixture: fixture,
            file: file,
            line: line
        )

        let grazedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try fixture.makeDashboardRepository().markPastureGrazedToday(
            id: first.id,
            on: grazedAt
        )
        let firstAfterGrazing = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastures().first { $0.id == first.id },
            file: file,
            line: line
        )
        XCTAssertEqual(firstAfterGrazing.lastGrazedDate, grazedAt, file: file, line: line)
        try await assertDashboardPastureMatchesSource(
            pastureID: first.id,
            expectedRestDays: nil,
            fixture: fixture,
            file: file,
            line: line
        )

        let unrelatedSummaryAfter = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastures().first { $0.id == unrelated.id },
            file: file,
            line: line
        )
        XCTAssertEqual(
            unrelatedSummaryAfter,
            unrelatedSummaryBefore,
            "Target Pasture/group/grazing mutations must leave the unrelated Pasture projection unchanged.",
            file: file,
            line: line
        )
        let unrelatedGroupAfter = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastureGroupDetail(id: unrelatedGroup.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            unrelatedGroupAfter,
            unrelatedGroupBefore,
            "Target Pasture/group/grazing mutations must leave the unrelated group and membership unchanged.",
            file: file,
            line: line
        )
        let unrelatedDashboardAfter = try await fetchProductionDashboardPasture(
            id: unrelated.id,
            reader: fixture.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            unrelatedDashboardAfter,
            unrelatedDashboardBefore,
            "Production Dashboard/Home pasture projection must leave the unrelated control unchanged.",
            file: file,
            line: line
        )
    }

    private static func assertDashboardPastureMatchesSource(
        pastureID: UUID,
        expectedRestDays: Int?,
        fixture: PastureDashboardReadModelContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let pastureRepository = fixture.makePastureRepository()
        let summary = try XCTUnwrap(
            pastureRepository.fetchPastures().first { $0.id == pastureID },
            file: file,
            line: line
        )
        let detail = try XCTUnwrap(
            pastureRepository.fetchPastureDetail(id: pastureID),
            file: file,
            line: line
        )
        XCTAssertEqual(summary.id, detail.id, file: file, line: line)
        XCTAssertEqual(summary.name, detail.name, file: file, line: line)
        XCTAssertEqual(summary.acreage, detail.acreage, file: file, line: line)
        XCTAssertEqual(summary.usableAcreage, detail.usableAcreage, file: file, line: line)
        XCTAssertEqual(summary.targetAcresPerHead, detail.targetAcresPerHead, file: file, line: line)
        XCTAssertEqual(summary.activeAnimalCount, detail.activeAnimalCount, file: file, line: line)
        XCTAssertEqual(summary.lastGrazedDate, detail.lastGrazedDate, file: file, line: line)
        XCTAssertEqual(summary.groupID, detail.groupID, file: file, line: line)
        XCTAssertEqual(summary.groupName, detail.groupName, file: file, line: line)
        XCTAssertEqual(summary.restDays, expectedRestDays, file: file, line: line)

        let synchronous = fixture.makeDashboardRepository()
        let synchronousRecords = try synchronous.fetchDashboardRecords()
        let synchronousFromAll = try XCTUnwrap(
            synchronousRecords.pastures.first { $0.id == pastureID },
            file: file,
            line: line
        )
        let synchronousFromPastureList = try XCTUnwrap(
            synchronous.fetchDashboardPastureRecords().first { $0.id == pastureID },
            file: file,
            line: line
        )
        assertDashboardRecord(
            synchronousFromAll,
            matches: summary,
            file: file,
            line: line
        )
        XCTAssertEqual(synchronousFromPastureList, synchronousFromAll, file: file, line: line)

        let productionReader = fixture.makeDashboardQueryReader()
        let productionRecords = try await productionReader.fetchDashboardRecords()
        let productionFromAll = try XCTUnwrap(
            productionRecords.pastures.first { $0.id == pastureID },
            file: file,
            line: line
        )
        let productionPastureRecords = try await productionReader.fetchDashboardPastureRecords()
        let productionFromPastureList = try XCTUnwrap(
            productionPastureRecords.first { $0.id == pastureID },
            file: file,
            line: line
        )
        assertDashboardRecord(
            productionFromAll,
            matches: summary,
            file: file,
            line: line
        )
        XCTAssertEqual(productionFromPastureList, productionFromAll, file: file, line: line)
        XCTAssertEqual(productionFromAll, synchronousFromAll, file: file, line: line)
    }

    private static func fetchProductionDashboardPasture(
        id: UUID,
        reader: any DashboardQueryReading,
        file: StaticString,
        line: UInt
    ) async throws -> DashboardPastureRecord {
        let records = try await reader.fetchDashboardPastureRecords()
        return try XCTUnwrap(
            records.first { $0.id == id },
            file: file,
            line: line
        )
    }

    private static func assertDashboardRecord(
        _ record: DashboardPastureRecord,
        matches summary: PastureSummary,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(record.id, summary.id, file: file, line: line)
        XCTAssertEqual(record.name, summary.name, file: file, line: line)
        XCTAssertEqual(record.acreage, summary.acreage, file: file, line: line)
        XCTAssertEqual(record.usableAcreage, summary.usableAcreage, file: file, line: line)
        XCTAssertEqual(record.targetAcresPerHead, summary.targetAcresPerHead, file: file, line: line)
        XCTAssertEqual(record.activeAnimalCount, summary.activeAnimalCount, file: file, line: line)
        XCTAssertEqual(record.lastGrazedDate, summary.lastGrazedDate, file: file, line: line)
        XCTAssertEqual(record.restDays, summary.restDays, file: file, line: line)
    }
}
