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

        let resident = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Update Preserve Resident",
                tagNumber: "U-401",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSince1970: 1_577_836_800),
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
        XCTAssertEqual(detail.activeAnimalCount, 1, file: file, line: line)

        let summaries = try reloadedRepository.fetchPastures()
        let summary = try XCTUnwrap(
            summaries.first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.sortOrder, 1, file: file, line: line)
        XCTAssertEqual(summary.groupID, group.id, file: file, line: line)
        XCTAssertEqual(summary.groupName, "Preserve State Rotation", file: file, line: line)
        XCTAssertEqual(summary.restDays, 24, file: file, line: line)
        XCTAssertEqual(summary.lastGrazedDate, grazedAt, file: file, line: line)
        XCTAssertEqual(summary.activeAnimalCount, 1, file: file, line: line)

        let residents = try reloadedRepository.fetchResidentAnimals(pastureID: pasture.id)
        XCTAssertEqual(
            residents.map(\.id),
            [resident.id],
            "Updating pasture form fields must not drop existing resident relationships.",
            file: file,
            line: line
        )

        let reloadedResident = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: resident.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedResident.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(reloadedResident.pastureName, "Updated Preserve State Pasture", file: file, line: line)

        let groupDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: group.id),
            file: file,
            line: line
        )
        XCTAssertEqual(groupDetail.pastures.map(\.id), [pasture.id], file: file, line: line)

        let anchorDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: orderAnchor.id),
            "Updating one pasture must not mutate an unrelated pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(anchorDetail.name, "Order Anchor", file: file, line: line)
        XCTAssertEqual(anchorDetail.acreage, 18, file: file, line: line)
        XCTAssertEqual(anchorDetail.usableAcreage, 16, file: file, line: line)
        XCTAssertEqual(anchorDetail.targetAcresPerHead, 1.25, file: file, line: line)
        XCTAssertNil(anchorDetail.groupID, file: file, line: line)
        XCTAssertNil(anchorDetail.groupName, file: file, line: line)
        XCTAssertNil(anchorDetail.lastGrazedDate, file: file, line: line)
        XCTAssertEqual(anchorDetail.activeAnimalCount, 0, file: file, line: line)

        let anchorSummary = try XCTUnwrap(
            summaries.first { $0.id == orderAnchor.id },
            "The pasture-list projection must leave unrelated pastures unchanged after an update.",
            file: file,
            line: line
        )
        XCTAssertEqual(anchorSummary.name, "Order Anchor", file: file, line: line)
        XCTAssertEqual(anchorSummary.acreage, 18, file: file, line: line)
        XCTAssertEqual(anchorSummary.usableAcreage, 16, file: file, line: line)
        XCTAssertEqual(anchorSummary.targetAcresPerHead, 1.25, file: file, line: line)
        XCTAssertEqual(anchorSummary.sortOrder, 0, file: file, line: line)
        XCTAssertNil(anchorSummary.groupID, file: file, line: line)
        XCTAssertNil(anchorSummary.groupName, file: file, line: line)
        XCTAssertNil(anchorSummary.restDays, file: file, line: line)
        XCTAssertNil(anchorSummary.lastGrazedDate, file: file, line: line)
        XCTAssertEqual(anchorSummary.activeAnimalCount, 0, file: file, line: line)

        let anchorOption = try XCTUnwrap(
            reloadedRepository.fetchPastureOptions().first { $0.id == orderAnchor.id },
            "The pasture-option projection must leave unrelated pastures unchanged after an update.",
            file: file,
            line: line
        )
        XCTAssertEqual(anchorOption.name, "Order Anchor", file: file, line: line)
    }

    static func assertReorderingPreservesNonOrderState(
        using fixture: PastureRepositoryContractFixture,
        markPastureGrazed: (UUID, Date) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let first = try repository.create(
            input: PastureInput(name: "Reorder First", acreage: 20, usableAcreage: 18, targetAcresPerHead: 1.5)
        )
        let second = try repository.create(
            input: PastureInput(name: "Reorder Second", acreage: 22, usableAcreage: 19, targetAcresPerHead: 1.5)
        )
        let third = try repository.create(
            input: PastureInput(name: "Reorder Stateful", acreage: 24, usableAcreage: 21, targetAcresPerHead: 1.75)
        )
        let group = try repository.createGroup(
            input: PastureGroupInput(name: "Reorder Rotation", grazeDays: 6, restDays: 24)
        )
        let grazedAt = Date(timeIntervalSince1970: 1_780_345_600)

        try repository.assignPasture(id: third.id, toGroupID: group.id)
        try markPastureGrazed(third.id, grazedAt)

        let resident = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Reorder Resident",
                tagNumber: "R-301",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSince1970: 1_577_836_800),
                status: .active,
                pastureID: third.id,
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

        try repository.reorder(ids: [third.id, first.id])

        let reloadedRepository = fixture.makePastureRepository()
        let summaries = try reloadedRepository.fetchPastures()
        XCTAssertEqual(summaries.map(\.id), [third.id, first.id, second.id], file: file, line: line)
        XCTAssertEqual(summaries.map(\.sortOrder), [0, 1, 2], file: file, line: line)

        let summary = try XCTUnwrap(
            summaries.first { $0.id == third.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.acreage, 24, file: file, line: line)
        XCTAssertEqual(summary.usableAcreage, 21, file: file, line: line)
        XCTAssertEqual(summary.targetAcresPerHead, 1.75, file: file, line: line)
        XCTAssertEqual(summary.groupID, group.id, file: file, line: line)
        XCTAssertEqual(summary.groupName, "Reorder Rotation", file: file, line: line)
        XCTAssertEqual(summary.restDays, 24, file: file, line: line)
        XCTAssertEqual(summary.lastGrazedDate, grazedAt, file: file, line: line)
        XCTAssertEqual(summary.activeAnimalCount, 1, file: file, line: line)

        let detail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: third.id),
            file: file,
            line: line
        )
        XCTAssertEqual(detail.acreage, 24, file: file, line: line)
        XCTAssertEqual(detail.usableAcreage, 21, file: file, line: line)
        XCTAssertEqual(detail.targetAcresPerHead, 1.75, file: file, line: line)
        XCTAssertEqual(detail.groupID, group.id, file: file, line: line)
        XCTAssertEqual(detail.groupName, "Reorder Rotation", file: file, line: line)
        XCTAssertEqual(detail.lastGrazedDate, grazedAt, file: file, line: line)
        XCTAssertEqual(detail.activeAnimalCount, 1, file: file, line: line)

        let residents = try reloadedRepository.fetchResidentAnimals(pastureID: third.id)
        XCTAssertEqual(residents.map(\.id), [resident.id], file: file, line: line)

        let groupDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: group.id),
            file: file,
            line: line
        )
        XCTAssertEqual(groupDetail.pastures.map(\.id), [third.id], file: file, line: line)

        let missingID = UUID()
        XCTAssertThrowsError(
            try reloadedRepository.reorder(ids: [third.id, missingID]),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PastureRepositoryError,
                .pastureIDsNotFound([missingID]),
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try fixture.makePastureRepository().fetchPastures().map(\.id),
            [third.id, first.id, second.id],
            "A reorder containing a missing ID must not publish a partial order.",
            file: file,
            line: line
        )
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
        let existingDestinationPasture = try repository.create(
            input: PastureInput(
                name: "Existing Destination Pasture",
                acreage: 22,
                usableAcreage: 20,
                targetAcresPerHead: 1.5
            )
        )
        let sourceGroup = try repository.createGroup(
            input: PastureGroupInput(name: "Source Rotation", grazeDays: 5, restDays: 20)
        )
        let destinationGroup = try repository.createGroup(
            input: PastureGroupInput(name: "Destination Rotation", grazeDays: 7, restDays: 28)
        )

        try repository.assignPasture(id: existingDestinationPasture.id, toGroupID: destinationGroup.id)
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

        let existingDestinationDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: existingDestinationPasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(existingDestinationDetail.groupID, destinationGroup.id, file: file, line: line)
        XCTAssertEqual(existingDestinationDetail.groupName, "Destination Rotation", file: file, line: line)

        let pastureSummaries = try reloadedRepository.fetchPastures()
        let pastureSummary = try XCTUnwrap(
            pastureSummaries.first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(pastureSummary.groupID, destinationGroup.id, file: file, line: line)
        XCTAssertEqual(pastureSummary.groupName, "Destination Rotation", file: file, line: line)
        XCTAssertEqual(pastureSummary.restDays, 28, file: file, line: line)

        let existingDestinationSummary = try XCTUnwrap(
            pastureSummaries.first { $0.id == existingDestinationPasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(existingDestinationSummary.groupID, destinationGroup.id, file: file, line: line)
        XCTAssertEqual(existingDestinationSummary.groupName, "Destination Rotation", file: file, line: line)
        XCTAssertEqual(existingDestinationSummary.restDays, 28, file: file, line: line)

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
        XCTAssertEqual(
            Set(destinationDetail.pastures.map(\.id)),
            Set([pasture.id, existingDestinationPasture.id]),
            "Direct reassignment must preserve pastures already assigned to the destination group.",
            file: file,
            line: line
        )

        let groups = try reloadedRepository.fetchPastureGroups()
        let sourceSummary = try XCTUnwrap(groups.first { $0.id == sourceGroup.id }, file: file, line: line)
        let destinationSummary = try XCTUnwrap(groups.first { $0.id == destinationGroup.id }, file: file, line: line)
        XCTAssertEqual(sourceSummary.pastureCount, 0, file: file, line: line)
        XCTAssertEqual(destinationSummary.pastureCount, 2, file: file, line: line)
    }

    static func assertUpdatingGroupPreservesPastureMembership(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let firstPasture = try repository.create(
            input: PastureInput(
                name: "Group Update Member One",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let secondPasture = try repository.create(
            input: PastureInput(
                name: "Group Update Member Two",
                acreage: 22,
                usableAcreage: 20,
                targetAcresPerHead: 1.5
            )
        )
        let unrelatedPasture = try repository.create(
            input: PastureInput(
                name: "Unrelated Group Member",
                acreage: 26,
                usableAcreage: 23,
                targetAcresPerHead: 1.75
            )
        )
        let group = try repository.createGroup(
            input: PastureGroupInput(name: "Group Before Update", grazeDays: 5, restDays: 20)
        )
        let unrelatedGroup = try repository.createGroup(
            input: PastureGroupInput(name: "Unrelated Rotation", grazeDays: 4, restDays: 16)
        )

        try repository.assignPasture(id: firstPasture.id, toGroupID: group.id)
        try repository.assignPasture(id: secondPasture.id, toGroupID: group.id)
        try repository.assignPasture(id: unrelatedPasture.id, toGroupID: unrelatedGroup.id)

        let updated = try repository.updateGroup(
            id: group.id,
            input: PastureGroupInput(name: "Group After Update", grazeDays: 7, restDays: 28)
        )
        XCTAssertEqual(updated.id, group.id, file: file, line: line)
        XCTAssertEqual(
            Set(updated.pastures.map(\.id)),
            Set([firstPasture.id, secondPasture.id]),
            "Updating a group must preserve every existing pasture member.",
            file: file,
            line: line
        )

        let reloadedRepository = fixture.makePastureRepository()
        let groupDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: group.id),
            file: file,
            line: line
        )
        XCTAssertEqual(groupDetail.name, "Group After Update", file: file, line: line)
        XCTAssertEqual(groupDetail.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(groupDetail.restDays, 28, file: file, line: line)
        XCTAssertEqual(
            Set(groupDetail.pastures.map(\.id)),
            Set([firstPasture.id, secondPasture.id]),
            file: file,
            line: line
        )

        let unrelatedGroupDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: unrelatedGroup.id),
            "Updating one group must not mutate an unrelated group.",
            file: file,
            line: line
        )
        XCTAssertEqual(unrelatedGroupDetail.name, "Unrelated Rotation", file: file, line: line)
        XCTAssertEqual(unrelatedGroupDetail.grazeDays, 4, file: file, line: line)
        XCTAssertEqual(unrelatedGroupDetail.restDays, 16, file: file, line: line)
        XCTAssertEqual(unrelatedGroupDetail.pastures.map(\.id), [unrelatedPasture.id], file: file, line: line)

        let pastureSummaries = try reloadedRepository.fetchPastures()
        for pasture in [firstPasture, secondPasture] {
            let pastureDetail = try XCTUnwrap(
                reloadedRepository.fetchPastureDetail(id: pasture.id),
                file: file,
                line: line
            )
            XCTAssertEqual(pastureDetail.groupID, group.id, file: file, line: line)
            XCTAssertEqual(pastureDetail.groupName, "Group After Update", file: file, line: line)

            let pastureSummary = try XCTUnwrap(
                pastureSummaries.first { $0.id == pasture.id },
                file: file,
                line: line
            )
            XCTAssertEqual(pastureSummary.groupID, group.id, file: file, line: line)
            XCTAssertEqual(pastureSummary.groupName, "Group After Update", file: file, line: line)
            XCTAssertEqual(pastureSummary.restDays, 28, file: file, line: line)
        }

        let unrelatedPastureDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: unrelatedPasture.id),
            "Updating another group must preserve this pasture's assignment.",
            file: file,
            line: line
        )
        XCTAssertEqual(unrelatedPastureDetail.groupID, unrelatedGroup.id, file: file, line: line)
        XCTAssertEqual(unrelatedPastureDetail.groupName, "Unrelated Rotation", file: file, line: line)

        let unrelatedPastureSummary = try XCTUnwrap(
            pastureSummaries.first { $0.id == unrelatedPasture.id },
            "The pasture-list projection must preserve unrelated group membership.",
            file: file,
            line: line
        )
        XCTAssertEqual(unrelatedPastureSummary.groupID, unrelatedGroup.id, file: file, line: line)
        XCTAssertEqual(unrelatedPastureSummary.groupName, "Unrelated Rotation", file: file, line: line)
        XCTAssertEqual(unrelatedPastureSummary.restDays, 16, file: file, line: line)

        let groupSummaries = try reloadedRepository.fetchPastureGroups()
        let groupSummary = try XCTUnwrap(
            groupSummaries.first { $0.id == group.id },
            file: file,
            line: line
        )
        XCTAssertEqual(groupSummary.name, "Group After Update", file: file, line: line)
        XCTAssertEqual(groupSummary.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(groupSummary.restDays, 28, file: file, line: line)
        XCTAssertEqual(groupSummary.pastureCount, 2, file: file, line: line)

        let unrelatedGroupSummary = try XCTUnwrap(
            groupSummaries.first { $0.id == unrelatedGroup.id },
            "The group-list projection must leave unrelated groups unchanged.",
            file: file,
            line: line
        )
        XCTAssertEqual(unrelatedGroupSummary.name, "Unrelated Rotation", file: file, line: line)
        XCTAssertEqual(unrelatedGroupSummary.grazeDays, 4, file: file, line: line)
        XCTAssertEqual(unrelatedGroupSummary.restDays, 16, file: file, line: line)
        XCTAssertEqual(unrelatedGroupSummary.pastureCount, 1, file: file, line: line)
    }

    static func assertArchivedAnimalTimestampSurvivesPastureDeletion(
        using fixture: PastureDeletionWorkflowContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let pasture = try pastureRepository.create(
            input: PastureInput(
                name: "Archived Timestamp Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animalRepository = fixture.makeAnimalRepository()
        let archivedAnimal = try animalRepository.create(
            input: AnimalInput(
                name: "Archived Timestamp Cow",
                tagNumber: "AT-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSince1970: 1_577_836_800),
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
        try animalRepository.archive(ids: [archivedAnimal.id])

        let archivedBeforeDeletion = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: archivedAnimal.id),
            file: file,
            line: line
        )
        let archivedAt = try XCTUnwrap(
            archivedBeforeDeletion.archivedAt,
            "The fixture must persist an archive timestamp before deleting the pasture.",
            file: file,
            line: line
        )

        try fixture.deletePastures(
            [pasture.id],
            Date(timeIntervalSince1970: 1_781_000_000)
        )

        let archivedAfterDeletion = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: archivedAnimal.id),
            "Deleting the pasture must preserve the archived animal.",
            file: file,
            line: line
        )
        XCTAssertTrue(archivedAfterDeletion.isArchived, file: file, line: line)
        XCTAssertEqual(
            archivedAfterDeletion.archivedAt,
            archivedAt,
            "Pasture deletion must preserve the animal's original archive timestamp.",
            file: file,
            line: line
        )
        XCTAssertNil(archivedAfterDeletion.pastureID, file: file, line: line)
        XCTAssertNil(archivedAfterDeletion.pastureName, file: file, line: line)
    }

    static func assertArchivedFieldCheckRemainsWritableAfterPastureDeletion(
        using fixture: PastureDeletionWorkflowContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let pasture = try pastureRepository.create(
            input: PastureInput(
                name: "Writable Archived Check Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Writable Archived Check Cow",
                tagNumber: "WA-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSince1970: 1_577_836_800),
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
        let fieldChecks = fixture.makeFieldCheckRepository()
        let sessionID = try fieldChecks.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: Date(timeIntervalSince1970: 1_781_100_000),
                notes: "Before pasture deletion"
            )
        )
        let sessionBeforeDeletion = try XCTUnwrap(
            fieldChecks.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let animalCheck = try XCTUnwrap(
            sessionBeforeDeletion.animalChecks.first { $0.animalID == animal.id },
            "The Field Check fixture must contain the pasture resident before deletion.",
            file: file,
            line: line
        )
        XCTAssertNil(sessionBeforeDeletion.completedAt, file: file, line: line)

        let archivedAt = Date(timeIntervalSince1970: 1_781_200_000)
        try fixture.deletePastures([pasture.id], archivedAt)

        let archivedFieldChecks = fixture.makeFieldCheckRepository()
        let archivedBeforeWrite = try XCTUnwrap(
            archivedFieldChecks.fetchSessionDetail(id: sessionID),
            "Deleting the pasture must preserve the still-open Field Check.",
            file: file,
            line: line
        )
        XCTAssertNil(archivedBeforeWrite.completedAt, file: file, line: line)
        XCTAssertEqual(archivedBeforeWrite.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(archivedBeforeWrite.pastureName, "Writable Archived Check Pasture", file: file, line: line)
        XCTAssertEqual(archivedBeforeWrite.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(archivedBeforeWrite.isPastureArchived, file: file, line: line)
        XCTAssertEqual(
            archivedBeforeWrite.animalChecks.first { $0.animalID == animal.id }?.id,
            animalCheck.id,
            "Pasture deletion must preserve the child UUID used for later Field Check writes.",
            file: file,
            line: line
        )

        let updatedNotes = "Updated after pasture deletion"
        try archivedFieldChecks.setAnimalCheckCounted(
            sessionID: sessionID,
            animalCheckID: animalCheck.id,
            isCounted: true
        )
        try archivedFieldChecks.updateNotes(sessionID: sessionID, notes: updatedNotes)
        try archivedFieldChecks.completeSession(id: sessionID)

        let reloadedFieldChecks = fixture.makeFieldCheckRepository()
        let reloadedSession = try XCTUnwrap(
            reloadedFieldChecks.fetchSessionDetail(id: sessionID),
            "An archived Field Check must remain writable after its pasture has been deleted.",
            file: file,
            line: line
        )
        let completedAt = try XCTUnwrap(
            reloadedSession.completedAt,
            "Completing the archived Field Check must persist after reload.",
            file: file,
            line: line
        )
        let reloadedAnimalCheck = try XCTUnwrap(
            reloadedSession.animalChecks.first { $0.id == animalCheck.id },
            "The mutated archived roster entry must remain addressable by its application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedAnimalCheck.animalID, animal.id, file: file, line: line)
        XCTAssertTrue(reloadedAnimalCheck.wasCounted, file: file, line: line)
        XCTAssertEqual(reloadedSession.notes, updatedNotes, file: file, line: line)
        XCTAssertEqual(reloadedSession.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(reloadedSession.pastureName, "Writable Archived Check Pasture", file: file, line: line)
        XCTAssertEqual(reloadedSession.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(reloadedSession.isPastureArchived, file: file, line: line)

        let reloadedSummary = try XCTUnwrap(
            reloadedFieldChecks.fetchSessions().first { $0.id == sessionID },
            "The Field Check list reader must reflect writes made after pasture deletion.",
            file: file,
            line: line
        )
        let summaryAnimalCheck = try XCTUnwrap(
            reloadedSummary.animalChecks.first { $0.id == animalCheck.id },
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedSummary.completedAt, completedAt, file: file, line: line)
        XCTAssertTrue(summaryAnimalCheck.wasCounted, file: file, line: line)
        XCTAssertEqual(reloadedSummary.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(reloadedSummary.pastureName, "Writable Archived Check Pasture", file: file, line: line)
        XCTAssertEqual(reloadedSummary.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(reloadedSummary.isPastureArchived, file: file, line: line)
    }

    static func assertActiveWorkingSessionRemainsWritableAfterPastureDeletion(
        using fixture: PastureDeletionWorkflowContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastures = fixture.makePastureRepository()
        let sourcePasture = try pastures.create(
            input: PastureInput(
                name: "Writable Working Source",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let deletedDestination = try pastures.create(
            input: PastureInput(
                name: "Writable Working Deleted Destination",
                acreage: 22,
                usableAcreage: 20,
                targetAcresPerHead: 1.5
            )
        )
        let controlPasture = try pastures.create(
            input: PastureInput(
                name: "Writable Working Control",
                acreage: 24,
                usableAcreage: 21,
                targetAcresPerHead: 1.75
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: "Writable Working Cow",
                tagNumber: "WW-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSince1970: 1_577_836_800),
                status: .active,
                pastureID: sourcePasture.id,
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

        let working = fixture.makeWorkingRepository()
        let sessionID = try working.startSession(
            input: WorkingSessionStartInput(
                date: Date(timeIntervalSince1970: 1_781_300_000),
                sourcePastureID: sourcePasture.id,
                treatmentTemplateName: "Writable Working Contract",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let startedSession = try XCTUnwrap(
            working.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let queueItemID = try XCTUnwrap(
            startedSession.queueItems.first?.id,
            "The Working fixture must contain its selected animal.",
            file: file,
            line: line
        )
        try working.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: "Before pasture deletion"
        )
        let completedQueueItem = try XCTUnwrap(
            working.fetchSessionDetail(id: sessionID)?.queueItems.first,
            file: file,
            line: line
        )
        let completedAt = try XCTUnwrap(completedQueueItem.completedAt, file: file, line: line)
        try working.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: completedAt,
                destinationPastureID: deletedDestination.id,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: "Before pasture deletion"
            )
        )

        let archivedAt = Date(timeIntervalSince1970: 1_781_400_000)
        try fixture.deletePastures([sourcePasture.id, deletedDestination.id], archivedAt)

        let animalsAfterDeletion = fixture.makeAnimalRepository()
        let workingAnimalAfterDeletion = try XCTUnwrap(
            animalsAfterDeletion.fetchAnimalDetail(id: animal.id),
            "An animal in an active Working session must survive deletion of its historical pastures.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingAnimalAfterDeletion.location, .workingPen, file: file, line: line)
        XCTAssertNil(workingAnimalAfterDeletion.pastureID, file: file, line: line)
        XCTAssertNil(workingAnimalAfterDeletion.pastureName, file: file, line: line)
        let movementsBeforeCompletion = try animalsAfterDeletion.fetchTimeline(id: animal.id).compactMap { event -> String? in
            guard case .movement = event.type else { return nil }
            return event.details
        }

        let postDeletionWorking = fixture.makeWorkingRepository()
        let sessionAfterDeletion = try XCTUnwrap(
            postDeletionWorking.fetchSessionDetail(id: sessionID),
            "The active Working session must remain readable after its source and selected destination are deleted.",
            file: file,
            line: line
        )
        XCTAssertEqual(sessionAfterDeletion.status, .active, file: file, line: line)
        XCTAssertEqual(sessionAfterDeletion.sourcePastureID, sourcePasture.id, file: file, line: line)
        XCTAssertEqual(sessionAfterDeletion.sourcePastureName, "Writable Working Source", file: file, line: line)

        let postDeletionNotes = "Updated after pasture deletion"
        try postDeletionWorking.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: completedAt,
                destinationPastureID: controlPasture.id,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: postDeletionNotes
            )
        )

        let editorAfterPostDeletionWrite = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            "The Working editor must persist writes made after its historical pastures are deleted.",
            file: file,
            line: line
        )
        XCTAssertEqual(editorAfterPostDeletionWrite.sessionStatus, .active, file: file, line: line)
        XCTAssertEqual(editorAfterPostDeletionWrite.destinationPastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(editorAfterPostDeletionWrite.observationNotes, postDeletionNotes, file: file, line: line)

        try postDeletionWorking.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItemID,
                    destinationPastureID: controlPasture.id
                )
            ]
        )

        let finalWorking = fixture.makeWorkingRepository()
        let finalSession = try XCTUnwrap(
            finalWorking.fetchSessionDetail(id: sessionID),
            "Finishing the Working session after pasture deletion must persist.",
            file: file,
            line: line
        )
        XCTAssertEqual(finalSession.status, .finished, file: file, line: line)
        XCTAssertEqual(finalSession.sourcePastureID, sourcePasture.id, file: file, line: line)
        XCTAssertEqual(finalSession.sourcePastureName, "Writable Working Source", file: file, line: line)
        let finalQueueItem = try XCTUnwrap(finalSession.queueItems.first, file: file, line: line)
        XCTAssertEqual(finalQueueItem.id, queueItemID, file: file, line: line)
        XCTAssertEqual(finalQueueItem.status, .done, file: file, line: line)
        XCTAssertEqual(finalQueueItem.destinationPastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(finalQueueItem.destinationPastureName, "Writable Working Control", file: file, line: line)

        let finalSummary = try XCTUnwrap(
            finalWorking.fetchSessions().first { $0.id == sessionID },
            "The Working list reader must reflect post-deletion completion.",
            file: file,
            line: line
        )
        XCTAssertEqual(finalSummary.status, .finished, file: file, line: line)
        XCTAssertEqual(finalSummary.sourcePastureName, "Writable Working Source", file: file, line: line)
        XCTAssertEqual(finalSummary.totalQueueItems, 1, file: file, line: line)
        XCTAssertEqual(finalSummary.completedQueueItems, 1, file: file, line: line)

        let finalEditor = try XCTUnwrap(
            finalWorking.fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        XCTAssertEqual(finalEditor.sessionStatus, .finished, file: file, line: line)
        XCTAssertEqual(finalEditor.destinationPastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(finalEditor.observationNotes, postDeletionNotes, file: file, line: line)

        let finalAnimals = fixture.makeAnimalRepository()
        let finalAnimal = try XCTUnwrap(
            finalAnimals.fetchAnimalDetail(id: animal.id),
            "Completing the surviving Working session must move its animal out of the working pen.",
            file: file,
            line: line
        )
        XCTAssertEqual(finalAnimal.location, .pasture, file: file, line: line)
        XCTAssertEqual(finalAnimal.pastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(finalAnimal.pastureName, "Writable Working Control", file: file, line: line)

        let finalAnimalSummary = try XCTUnwrap(
            finalAnimals.fetchAnimals().first { $0.id == animal.id },
            "The animal-list reader must reflect the post-deletion Working completion destination.",
            file: file,
            line: line
        )
        XCTAssertEqual(finalAnimalSummary.location, .pasture, file: file, line: line)
        XCTAssertEqual(finalAnimalSummary.pastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(finalAnimalSummary.pastureName, "Writable Working Control", file: file, line: line)

        let movementsAfterCompletion = try finalAnimals.fetchTimeline(id: animal.id).compactMap { event -> String? in
            guard case .movement = event.type else { return nil }
            return event.details
        }
        XCTAssertEqual(
            Array(movementsAfterCompletion.dropLast()),
            movementsBeforeCompletion,
            "Finishing the session must preserve movement history recorded before the post-deletion write.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            movementsAfterCompletion.count,
            movementsBeforeCompletion.count + 1,
            "Finishing the session must append exactly one movement into the surviving destination.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            movementsAfterCompletion.last?.hasSuffix("→ Writable Working Control") == true,
            "The appended movement must end in the surviving destination pasture.",
            file: file,
            line: line
        )
    }
}