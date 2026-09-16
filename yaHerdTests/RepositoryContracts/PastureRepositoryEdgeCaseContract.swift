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
        let group = try repository.createGroup(
            input: PastureGroupInput(name: "Group Before Update", grazeDays: 5, restDays: 20)
        )

        try repository.assignPasture(id: firstPasture.id, toGroupID: group.id)
        try repository.assignPasture(id: secondPasture.id, toGroupID: group.id)

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

        let groupSummary = try XCTUnwrap(
            reloadedRepository.fetchPastureGroups().first { $0.id == group.id },
            file: file,
            line: line
        )
        XCTAssertEqual(groupSummary.name, "Group After Update", file: file, line: line)
        XCTAssertEqual(groupSummary.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(groupSummary.restDays, 28, file: file, line: line)
        XCTAssertEqual(groupSummary.pastureCount, 2, file: file, line: line)
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
}
