import XCTest
@testable import yaHerd

/// Additional permanent characterization for repository behaviors exercised directly by pasture UI
/// flows. These remain persistence-neutral so the same assertions can run against Core Data.
@MainActor
enum PastureRepositoryEdgeCaseContract {
    static func assertClearingOptionalStockingFieldsPersists(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(
            input: PastureInput(
                name: "Clear Stocking Data",
                acreage: 40,
                usableAcreage: 36,
                targetAcresPerHead: 2
            )
        )

        let updated = try repository.update(
            id: pasture.id,
            input: PastureInput(
                name: "Clear Stocking Data",
                acreage: nil,
                usableAcreage: nil,
                targetAcresPerHead: nil
            )
        )
        XCTAssertNil(updated.acreage, file: file, line: line)
        XCTAssertNil(updated.usableAcreage, file: file, line: line)
        XCTAssertNil(updated.targetAcresPerHead, file: file, line: line)

        let reloadedRepository = fixture.makePastureRepository()
        let detail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertNil(detail.acreage, file: file, line: line)
        XCTAssertNil(detail.usableAcreage, file: file, line: line)
        XCTAssertNil(detail.targetAcresPerHead, file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedRepository.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertNil(summary.acreage, file: file, line: line)
        XCTAssertNil(summary.usableAcreage, file: file, line: line)
        XCTAssertNil(summary.targetAcresPerHead, file: file, line: line)
    }

    static func assertDirectReassignmentBetweenGroupsUpdatesBothInverses(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(
            input: PastureInput(
                name: "Reassignment Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let sourceGroup = try repository.createGroup(
            input: PastureGroupInput(name: "Source Rotation", grazeDays: 5, restDays: 20)
        )
        let destinationGroup = try repository.createGroup(
            input: PastureGroupInput(name: "Destination Rotation", grazeDays: 7, restDays: 28)
        )

        try repository.assignPasture(id: pasture.id, toGroupID: sourceGroup.id)
        try repository.assignPasture(id: pasture.id, toGroupID: destinationGroup.id)

        let reloadedRepository = fixture.makePastureRepository()
        let reloadedPasture = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedPasture.groupID, destinationGroup.id, file: file, line: line)
        XCTAssertEqual(reloadedPasture.groupName, "Destination Rotation", file: file, line: line)

        let sourceDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: sourceGroup.id),
            file: file,
            line: line
        )
        XCTAssertFalse(
            sourceDetail.pastures.contains { $0.id == pasture.id },
            "Direct reassignment must remove the pasture from the previous group's inverse membership.",
            file: file,
            line: line
        )

        let destinationDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: destinationGroup.id),
            file: file,
            line: line
        )
        XCTAssertEqual(destinationDetail.pastures.map(\.id), [pasture.id], file: file, line: line)

        let groups = try reloadedRepository.fetchPastureGroups()
        let sourceSummary = try XCTUnwrap(groups.first { $0.id == sourceGroup.id }, file: file, line: line)
        let destinationSummary = try XCTUnwrap(groups.first { $0.id == destinationGroup.id }, file: file, line: line)
        XCTAssertEqual(sourceSummary.pastureCount, 0, file: file, line: line)
        XCTAssertEqual(destinationSummary.pastureCount, 1, file: file, line: line)
    }
}
