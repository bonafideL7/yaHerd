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

    static func assertPersistedGrazingDate(
        using fixture: PastureRepositoryContractFixture,
        markPastureGrazed: (UUID, Date) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(
            input: PastureInput(
                name: "Grazing Date Pasture",
                acreage: 32,
                usableAcreage: 28,
                targetAcresPerHead: 1.75
            )
        )
        let grazedAt = Date(timeIntervalSince1970: 1_780_172_800)

        try markPastureGrazed(pasture.id, grazedAt)

        let reloadedRepository = fixture.makePastureRepository()
        let detail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(detail.lastGrazedDate, grazedAt, file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedRepository.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.lastGrazedDate, grazedAt, file: file, line: line)
    }

    static func assertUpdatingPasturePreservesNonFormState(
        using fixture: PastureRepositoryContractFixture,
        markPastureGrazed: (UUID, Date) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(
            input: PastureInput(
                name: "Preserve State Pasture",
                acreage: 24,
                usableAcreage: 21,
                targetAcresPerHead: 1.5
            )
        )
        let orderAnchor = try repository.create(
            input: PastureInput(
                name: "Order Anchor",
                acreage: 18,
                usableAcreage: 16,
                targetAcresPerHead: 1.25
            )
        )
        let group = try repository.createGroup(
            input: PastureGroupInput(name: "Preserve State Rotation", grazeDays: 6, restDays: 24)
        )
        let grazedAt = Date(timeIntervalSince1970: 1_780_259_200)

        try repository.assignPasture(id: pasture.id, toGroupID: group.id)
        try repository.reorder(ids: [orderAnchor.id, pasture.id])
        try markPastureGrazed(pasture.id, grazedAt)

        let updateRepository = fixture.makePastureRepository()
        let updated = try updateRepository.update(
            id: pasture.id,
            input: PastureInput(
                name: "Updated Preserve State Pasture",
                acreage: 30,
                usableAcreage: 27,
                targetAcresPerHead: 1.75
            )
        )
        XCTAssertEqual(updated.groupID, group.id, file: file, line: line)
        XCTAssertEqual(updated.groupName, "Preserve State Rotation", file: file, line: line)
        XCTAssertEqual(updated.lastGrazedDate, grazedAt, file: file, line: line)

        let reloadedRepository = fixture.makePastureRepository()
        let detail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(detail.name, "Updated Preserve State Pasture", file: file, line: line)
        XCTAssertEqual(detail.acreage, 30, file: file, line: line)
        XCTAssertEqual(detail.usableAcreage, 27, file: file, line: line)
        XCTAssertEqual(detail.targetAcresPerHead, 1.75, file: file, line: line)
        XCTAssertEqual(detail.groupID, group.id, file: file, line: line)
        XCTAssertEqual(detail.groupName, "Preserve State Rotation", file: file, line: line)
        XCTAssertEqual(detail.lastGrazedDate, grazedAt, file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedRepository.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.sortOrder, 1, file: file, line: line)
        XCTAssertEqual(summary.groupID, group.id, file: file, line: line)
        XCTAssertEqual(summary.groupName, "Preserve State Rotation", file: file, line: line)
        XCTAssertEqual(summary.restDays, 24, file: file, line: line)
        XCTAssertEqual(summary.lastGrazedDate, grazedAt, file: file, line: line)

        let groupDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: group.id),
            file: file,
            line: line
        )
        XCTAssertEqual(groupDetail.pastures.map(\.id), [pasture.id], file: file, line: line)
    }

    static func assertNameLookupExcludesOnlyRequestedPasture(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let alpha = try repository.create(
            input: PastureInput(
                name: "Alpha",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let bravo = try repository.create(
            input: PastureInput(
                name: "Bravo",
                acreage: 24,
                usableAcreage: 21,
                targetAcresPerHead: 1.75
            )
        )

        XCTAssertTrue(
            try repository.nameExists("  ALPHA  ", excluding: bravo.id),
            "Excluding one pasture must not hide a duplicate name owned by another pasture.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            try repository.nameExists(" alpha ", excluding: alpha.id),
            "A pasture must be able to keep its own normalized name during update validation.",
            file: file,
            line: line
        )
    }

    static func assertGroupNameLookupExcludesOnlyRequestedGroup(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let north = try repository.createGroup(
            input: PastureGroupInput(name: "North Rotation", grazeDays: 7, restDays: 21)
        )
        let south = try repository.createGroup(
            input: PastureGroupInput(name: "South Rotation", grazeDays: 5, restDays: 25)
        )

        XCTAssertTrue(
            try repository.groupNameExists("  NORTH ROTATION  ", excluding: south.id),
            "Excluding one group must not hide a duplicate name owned by another group.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            try repository.groupNameExists(" north rotation ", excluding: north.id),
            "A pasture group must be able to keep its own normalized name during update validation.",
            file: file,
            line: line
        )
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

        let pastureSummary = try XCTUnwrap(
            reloadedRepository.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(pastureSummary.groupID, destinationGroup.id, file: file, line: line)
        XCTAssertEqual(pastureSummary.groupName, "Destination Rotation", file: file, line: line)
        XCTAssertEqual(pastureSummary.restDays, 28, file: file, line: line)

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

    static func assertUpdatingGroupPreservesPastureMembership(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(
            input: PastureInput(
                name: "Group Update Member",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let group = try repository.createGroup(
            input: PastureGroupInput(name: "Group Before Update", grazeDays: 5, restDays: 20)
        )

        try repository.assignPasture(id: pasture.id, toGroupID: group.id)

        let updated = try repository.updateGroup(
            id: group.id,
            input: PastureGroupInput(name: "Group After Update", grazeDays: 7, restDays: 28)
        )
        XCTAssertEqual(updated.id, group.id, file: file, line: line)
        XCTAssertEqual(updated.pastures.map(\.id), [pasture.id], file: file, line: line)

        let reloadedRepository = fixture.makePastureRepository()
        let groupDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: group.id),
            file: file,
            line: line
        )
        XCTAssertEqual(groupDetail.name, "Group After Update", file: file, line: line)
        XCTAssertEqual(groupDetail.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(groupDetail.restDays, 28, file: file, line: line)
        XCTAssertEqual(groupDetail.pastures.map(\.id), [pasture.id], file: file, line: line)

        let pastureDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(pastureDetail.groupID, group.id, file: file, line: line)
        XCTAssertEqual(pastureDetail.groupName, "Group After Update", file: file, line: line)

        let pastureSummary = try XCTUnwrap(
            reloadedRepository.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(pastureSummary.groupID, group.id, file: file, line: line)
        XCTAssertEqual(pastureSummary.groupName, "Group After Update", file: file, line: line)
        XCTAssertEqual(pastureSummary.restDays, 28, file: file, line: line)

        let groupSummary = try XCTUnwrap(
            reloadedRepository.fetchPastureGroups().first { $0.id == group.id },
            file: file,
            line: line
        )
        XCTAssertEqual(groupSummary.name, "Group After Update", file: file, line: line)
        XCTAssertEqual(groupSummary.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(groupSummary.restDays, 28, file: file, line: line)
        XCTAssertEqual(groupSummary.pastureCount, 1, file: file, line: line)
    }
}
