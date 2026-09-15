import XCTest
@testable import yaHerd

/// Permanent persistence-neutral behavioral contract for `PastureRepository` implementations.
///
/// Production Core Data repositories should run these assertions unchanged.
/// The contract deliberately stays at Domain repository boundaries.
@MainActor
struct PastureRepositoryContractFixture {
    let makePastureRepository: () -> any PastureRepository
    let makeAnimalRepository: () -> any AnimalRepository
    let makeTagColorRepository: () -> any TagColorRepository
}

@MainActor
enum PastureRepositoryContract {
    static func assertCreateUpdateAndReload(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let created = try repository.create(
            input: PastureInput(
                name: "  Contract North  ",
                acreage: 25,
                usableAcreage: 22,
                targetAcresPerHead: 1.5
            )
        )

        XCTAssertEqual(created.name, "Contract North", file: file, line: line)
        XCTAssertEqual(created.acreage, 25, file: file, line: line)
        XCTAssertEqual(created.usableAcreage, 22, file: file, line: line)
        XCTAssertEqual(created.targetAcresPerHead, 1.5, file: file, line: line)

        let updated = try repository.update(
            id: created.id,
            input: PastureInput(
                name: "  Updated Contract North  ",
                acreage: 30,
                usableAcreage: 27,
                targetAcresPerHead: 1.75
            )
        )

        XCTAssertEqual(updated.id, created.id, "Updating must preserve application UUID identity.", file: file, line: line)
        XCTAssertEqual(updated.name, "Updated Contract North", file: file, line: line)
        XCTAssertEqual(updated.acreage, 30, file: file, line: line)
        XCTAssertEqual(updated.usableAcreage, 27, file: file, line: line)
        XCTAssertEqual(updated.targetAcresPerHead, 1.75, file: file, line: line)

        let reloadedRepository = fixture.makePastureRepository()
        let reloaded = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: created.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded, updated, file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedRepository.fetchPastures().first { $0.id == created.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.name, "Updated Contract North", file: file, line: line)
        XCTAssertEqual(summary.acreage, 30, file: file, line: line)
        XCTAssertEqual(summary.usableAcreage, 27, file: file, line: line)
        XCTAssertEqual(summary.targetAcresPerHead, 1.75, file: file, line: line)
        XCTAssertEqual(summary.activeAnimalCount, 0, file: file, line: line)
        XCTAssertNil(summary.groupID, file: file, line: line)
        XCTAssertNil(summary.groupName, file: file, line: line)

        let option = try XCTUnwrap(
            reloadedRepository.fetchPastureOptions().first { $0.id == created.id },
            "Renaming a pasture must update the option projection used by pasture selectors.",
            file: file,
            line: line
        )
        XCTAssertEqual(option.name, "Updated Contract North", file: file, line: line)
    }

    static func assertListOrderingAndSubsetReorder(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let first = try repository.create(input: makePastureInput(name: "First"))
        let second = try repository.create(input: makePastureInput(name: "Second"))
        let third = try repository.create(input: makePastureInput(name: "Third"))

        XCTAssertEqual(
            try repository.fetchPastures().map(\.id),
            [first.id, second.id, third.id],
            "New pastures should append to the persisted ordering.",
            file: file,
            line: line
        )

        try repository.reorder(ids: [third.id, first.id])

        let reloaded = try fixture.makePastureRepository().fetchPastures()
        XCTAssertEqual(reloaded.map(\.id), [third.id, first.id, second.id], file: file, line: line)
        XCTAssertEqual(reloaded.map(\.sortOrder), [0, 1, 2], file: file, line: line)
        XCTAssertEqual(reloaded.map(\.name), ["Third", "First", "Second"], file: file, line: line)
        XCTAssertEqual(reloaded.map(\.acreage), [20, 20, 20], file: file, line: line)
        XCTAssertEqual(reloaded.map(\.usableAcreage), [18, 18, 18], file: file, line: line)
        XCTAssertEqual(reloaded.map(\.targetAcresPerHead), [1.5, 1.5, 1.5], file: file, line: line)
    }

    static func assertReferenceDataAndNameLookup(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let bravo = try repository.create(input: makePastureInput(name: "Bravo"))
        let alpha = try repository.create(input: makePastureInput(name: "Alpha"))

        let options = try fixture.makePastureRepository().fetchPastureOptions()
        XCTAssertEqual(options.map(\.id), [alpha.id, bravo.id], file: file, line: line)
        XCTAssertEqual(options.map(\.name), ["Alpha", "Bravo"], file: file, line: line)

        XCTAssertTrue(try repository.nameExists("  alpha  ", excluding: nil), file: file, line: line)
        XCTAssertFalse(try repository.nameExists(" alpha ", excluding: alpha.id), file: file, line: line)

        XCTAssertThrowsError(
            try repository.create(input: makePastureInput(name: "  ALPHA  ")),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PastureValidationError,
                .duplicateName("ALPHA"),
                file: file,
                line: line
            )
        }
    }

    static func assertResidentAnimalsAndActiveCount(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let pasture = try pastureRepository.create(input: makePastureInput(name: "Residents"))
        let otherPasture = try pastureRepository.create(input: makePastureInput(name: "Other"))
        let animalRepository = fixture.makeAnimalRepository()
        let tagColorRepository = fixture.makeTagColorRepository()
        let damColor = TagColorSnapshot(
            name: "Contract Dam Color",
            prefix: "D",
            rgba: RGBAColor(r: 0.2, g: 0.4, b: 0.8)
        )
        let tag3Color = TagColorSnapshot(
            name: "Contract Resident Color",
            prefix: "R",
            rgba: RGBAColor(r: 0.2, g: 0.7, b: 0.3)
        )
        try tagColorRepository.upsert(damColor)
        try tagColorRepository.upsert(tag3Color)

        let dam = try animalRepository.create(
            input: makeAnimalInput(
                name: "Resident Dam",
                tagNumber: "D3",
                pastureID: otherPasture.id,
                tagColorID: damColor.id
            )
        )
        let tag20 = try animalRepository.create(
            input: makeAnimalInput(name: "Tag 20", tagNumber: "20", pastureID: pasture.id)
        )
        let tag3 = try animalRepository.create(
            input: makeAnimalInput(
                name: "Tag 3",
                tagNumber: "3",
                pastureID: pasture.id,
                tagColorID: tag3Color.id,
                damID: dam.id
            )
        )
        let archived = try animalRepository.create(
            input: makeAnimalInput(name: "Archived", tagNumber: "99", pastureID: pasture.id)
        )
        let sold = try animalRepository.create(
            input: makeAnimalInput(name: "Sold", tagNumber: "98", pastureID: pasture.id, status: .sold)
        )
        let dead = try animalRepository.create(
            input: makeAnimalInput(name: "Dead", tagNumber: "97", pastureID: pasture.id, status: .dead)
        )
        _ = try animalRepository.create(
            input: makeAnimalInput(name: "Other Pasture", tagNumber: "1", pastureID: otherPasture.id)
        )
        try animalRepository.archive(ids: [archived.id])

        let reloadedPastures = fixture.makePastureRepository()
        let residents = try reloadedPastures.fetchResidentAnimals(pastureID: pasture.id)
        XCTAssertEqual(residents.map(\.id), [tag3.id, tag20.id], file: file, line: line)
        XCTAssertFalse(residents.contains { $0.id == archived.id }, file: file, line: line)
        XCTAssertFalse(residents.contains { $0.id == sold.id }, file: file, line: line)
        XCTAssertFalse(residents.contains { $0.id == dead.id }, file: file, line: line)

        let tag3Summary = try XCTUnwrap(residents.first { $0.id == tag3.id }, file: file, line: line)
        XCTAssertEqual(tag3Summary.name, "Tag 3", file: file, line: line)
        XCTAssertEqual(tag3Summary.displayTagNumber, "3", file: file, line: line)
        XCTAssertEqual(tag3Summary.displayTagColorID, tag3Color.id, file: file, line: line)
        XCTAssertEqual(tag3Summary.damDisplayTagNumber, "D3", file: file, line: line)
        XCTAssertEqual(tag3Summary.damDisplayTagColorID, damColor.id, file: file, line: line)
        XCTAssertEqual(tag3Summary.sex, .female, file: file, line: line)
        XCTAssertEqual(tag3Summary.animalType, .heifer, file: file, line: line)
        XCTAssertEqual(tag3Summary.status, .active, file: file, line: line)
        XCTAssertFalse(tag3Summary.isArchived, file: file, line: line)
        XCTAssertEqual(tag3Summary.pastureID, pasture.id, file: file, line: line)
        XCTAssertEqual(tag3Summary.pastureName, "Residents", file: file, line: line)

        let tag20Summary = try XCTUnwrap(residents.first { $0.id == tag20.id }, file: file, line: line)
        XCTAssertEqual(tag20Summary.displayTagNumber, "20", file: file, line: line)
        XCTAssertNil(tag20Summary.displayTagColorID, file: file, line: line)
        XCTAssertNil(tag20Summary.damDisplayTagNumber, file: file, line: line)
        XCTAssertNil(tag20Summary.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(tag20Summary.animalType, .heifer, file: file, line: line)

        let detail = try XCTUnwrap(
            reloadedPastures.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(detail.activeAnimalCount, 2, file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedPastures.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.name, "Residents", file: file, line: line)
        XCTAssertEqual(summary.activeAnimalCount, 2, file: file, line: line)
        XCTAssertEqual(summary.acreage, 20, file: file, line: line)
        XCTAssertEqual(summary.usableAcreage, 18, file: file, line: line)
        XCTAssertEqual(summary.targetAcresPerHead, 1.5, file: file, line: line)
    }

    static func assertGroupLifecycleAndPastureAssignment(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(input: makePastureInput(name: "Grouped Pasture"))
        let survivingPasture = try repository.create(input: makePastureInput(name: "Surviving Group Pasture"))
        let createdGroup = try repository.createGroup(
            input: PastureGroupInput(name: "  Rotation A  ", grazeDays: 5, restDays: 25)
        )
        let survivingGroup = try repository.createGroup(
            input: PastureGroupInput(name: "Surviving Rotation", grazeDays: 4, restDays: 18)
        )
        try repository.assignPasture(id: survivingPasture.id, toGroupID: survivingGroup.id)

        XCTAssertEqual(createdGroup.name, "Rotation A", file: file, line: line)
        XCTAssertEqual(createdGroup.grazeDays, 5, file: file, line: line)
        XCTAssertEqual(createdGroup.restDays, 25, file: file, line: line)

        let updatedGroup = try repository.updateGroup(
            id: createdGroup.id,
            input: PastureGroupInput(name: "Rotation Updated", grazeDays: 7, restDays: 30)
        )
        XCTAssertEqual(updatedGroup.id, createdGroup.id, file: file, line: line)
        XCTAssertEqual(updatedGroup.name, "Rotation Updated", file: file, line: line)
        XCTAssertEqual(updatedGroup.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(updatedGroup.restDays, 30, file: file, line: line)

        try repository.assignPasture(id: pasture.id, toGroupID: createdGroup.id)

        let reloadedRepository = fixture.makePastureRepository()
        let groupedPasture = try XCTUnwrap(
            reloadedRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(groupedPasture.groupID, createdGroup.id, file: file, line: line)
        XCTAssertEqual(groupedPasture.groupName, "Rotation Updated", file: file, line: line)

        let groupDetail = try XCTUnwrap(
            reloadedRepository.fetchPastureGroupDetail(id: createdGroup.id),
            file: file,
            line: line
        )
        XCTAssertEqual(groupDetail.name, "Rotation Updated", file: file, line: line)
        XCTAssertEqual(groupDetail.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(groupDetail.restDays, 30, file: file, line: line)
        XCTAssertEqual(groupDetail.pastures.map(\.id), [pasture.id], file: file, line: line)

        let updatedGroupSummary = try XCTUnwrap(
            reloadedRepository.fetchPastureGroups().first { $0.id == createdGroup.id },
            "Updating a group must refresh the group-list projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(updatedGroupSummary.name, "Rotation Updated", file: file, line: line)
        XCTAssertEqual(updatedGroupSummary.grazeDays, 7, file: file, line: line)
        XCTAssertEqual(updatedGroupSummary.restDays, 30, file: file, line: line)
        XCTAssertEqual(updatedGroupSummary.pastureCount, 1, file: file, line: line)

        let groupedSummary = try XCTUnwrap(
            reloadedRepository.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(groupedSummary.name, "Grouped Pasture", file: file, line: line)
        XCTAssertEqual(groupedSummary.groupID, createdGroup.id, file: file, line: line)
        XCTAssertEqual(groupedSummary.groupName, "Rotation Updated", file: file, line: line)
        XCTAssertEqual(groupedSummary.restDays, 30, file: file, line: line)

        try reloadedRepository.assignPasture(id: pasture.id, toGroupID: nil)

        let unassignedRepository = fixture.makePastureRepository()
        let unassignedPasture = try XCTUnwrap(
            unassignedRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertNil(unassignedPasture.groupID, file: file, line: line)
        XCTAssertNil(unassignedPasture.groupName, file: file, line: line)
        let groupAfterUnassignment = try XCTUnwrap(
            unassignedRepository.fetchPastureGroupDetail(id: createdGroup.id),
            file: file,
            line: line
        )
        XCTAssertTrue(groupAfterUnassignment.pastures.isEmpty, file: file, line: line)

        let unassignedSummary = try XCTUnwrap(
            unassignedRepository.fetchPastures().first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertNil(unassignedSummary.groupID, file: file, line: line)
        XCTAssertNil(unassignedSummary.groupName, file: file, line: line)
        XCTAssertNil(unassignedSummary.restDays, file: file, line: line)

        try unassignedRepository.assignPasture(id: pasture.id, toGroupID: createdGroup.id)
        let reassignedPasture = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reassignedPasture.groupID, createdGroup.id, file: file, line: line)

        try unassignedRepository.deleteGroups(ids: [createdGroup.id])

        let postDeleteRepository = fixture.makePastureRepository()
        XCTAssertNil(
            try postDeleteRepository.fetchPastureGroupDetail(id: createdGroup.id),
            file: file,
            line: line
        )
        let pastureAfterGroupDelete = try XCTUnwrap(
            postDeleteRepository.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertNil(pastureAfterGroupDelete.groupID, file: file, line: line)
        XCTAssertNil(pastureAfterGroupDelete.groupName, file: file, line: line)

        let groupSummariesAfterDelete = try postDeleteRepository.fetchPastureGroups()
        XCTAssertFalse(
            groupSummariesAfterDelete.contains { $0.id == createdGroup.id },
            "Deleting a group must remove it from the group-list projection.",
            file: file,
            line: line
        )
        let survivingGroupSummary = try XCTUnwrap(
            groupSummariesAfterDelete.first { $0.id == survivingGroup.id },
            "Deleting one group must not remove an unrelated rotation.",
            file: file,
            line: line
        )
        XCTAssertEqual(survivingGroupSummary.name, "Surviving Rotation", file: file, line: line)
        XCTAssertEqual(survivingGroupSummary.grazeDays, 4, file: file, line: line)
        XCTAssertEqual(survivingGroupSummary.restDays, 18, file: file, line: line)
        XCTAssertEqual(survivingGroupSummary.pastureCount, 1, file: file, line: line)

        let survivingGroupDetail = try XCTUnwrap(
            postDeleteRepository.fetchPastureGroupDetail(id: survivingGroup.id),
            "Deleting one group must preserve unrelated group detail and membership.",
            file: file,
            line: line
        )
        XCTAssertEqual(survivingGroupDetail.name, "Surviving Rotation", file: file, line: line)
        XCTAssertEqual(survivingGroupDetail.grazeDays, 4, file: file, line: line)
        XCTAssertEqual(survivingGroupDetail.restDays, 18, file: file, line: line)
        XCTAssertEqual(survivingGroupDetail.pastures.map(\.id), [survivingPasture.id], file: file, line: line)

        let survivingPastureDetail = try XCTUnwrap(
            postDeleteRepository.fetchPastureDetail(id: survivingPasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(survivingPastureDetail.groupID, survivingGroup.id, file: file, line: line)
        XCTAssertEqual(survivingPastureDetail.groupName, "Surviving Rotation", file: file, line: line)

        let pastureSummariesAfterDelete = try postDeleteRepository.fetchPastures()
        let pastureSummaryAfterGroupDelete = try XCTUnwrap(
            pastureSummariesAfterDelete.first { $0.id == pasture.id },
            file: file,
            line: line
        )
        XCTAssertNil(pastureSummaryAfterGroupDelete.groupID, file: file, line: line)
        XCTAssertNil(pastureSummaryAfterGroupDelete.groupName, file: file, line: line)
        XCTAssertNil(pastureSummaryAfterGroupDelete.restDays, file: file, line: line)

        let survivingPastureSummary = try XCTUnwrap(
            pastureSummariesAfterDelete.first { $0.id == survivingPasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(survivingPastureSummary.groupID, survivingGroup.id, file: file, line: line)
        XCTAssertEqual(survivingPastureSummary.groupName, "Surviving Rotation", file: file, line: line)
        XCTAssertEqual(survivingPastureSummary.restDays, 18, file: file, line: line)
    }

    static func assertGroupListOrderingAndPastureCounts(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let north = try repository.create(input: makePastureInput(name: "North Pasture"))
        let south = try repository.create(input: makePastureInput(name: "South Pasture"))
        let east = try repository.create(input: makePastureInput(name: "East Pasture"))

        let zulu = try repository.createGroup(
            input: PastureGroupInput(name: "Zulu Rotation", grazeDays: 4, restDays: 16)
        )
        let alpha = try repository.createGroup(
            input: PastureGroupInput(name: "Alpha Rotation", grazeDays: 6, restDays: 24)
        )

        try repository.assignPasture(id: north.id, toGroupID: alpha.id)
        try repository.assignPasture(id: south.id, toGroupID: alpha.id)
        try repository.assignPasture(id: east.id, toGroupID: zulu.id)

        let groups = try fixture.makePastureRepository().fetchPastureGroups()
        XCTAssertEqual(groups.map(\.id), [alpha.id, zulu.id], file: file, line: line)
        XCTAssertEqual(groups.map(\.name), ["Alpha Rotation", "Zulu Rotation"], file: file, line: line)

        let alphaSummary = try XCTUnwrap(groups.first { $0.id == alpha.id }, file: file, line: line)
        XCTAssertEqual(alphaSummary.grazeDays, 6, file: file, line: line)
        XCTAssertEqual(alphaSummary.restDays, 24, file: file, line: line)
        XCTAssertEqual(alphaSummary.pastureCount, 2, file: file, line: line)

        let zuluSummary = try XCTUnwrap(groups.first { $0.id == zulu.id }, file: file, line: line)
        XCTAssertEqual(zuluSummary.grazeDays, 4, file: file, line: line)
        XCTAssertEqual(zuluSummary.restDays, 16, file: file, line: line)
        XCTAssertEqual(zuluSummary.pastureCount, 1, file: file, line: line)
    }

    static func assertGroupNameLookupAndDuplicateProtection(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let group = try repository.createGroup(
            input: PastureGroupInput(name: "North Rotation", grazeDays: 7, restDays: 21)
        )

        XCTAssertTrue(try repository.groupNameExists(" north rotation ", excluding: nil), file: file, line: line)
        XCTAssertFalse(try repository.groupNameExists("NORTH ROTATION", excluding: group.id), file: file, line: line)

        XCTAssertThrowsError(
            try repository.createGroup(
                input: PastureGroupInput(name: " NORTH ROTATION ", grazeDays: 4, restDays: 18)
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PastureValidationError,
                .duplicateName("NORTH ROTATION"),
                file: file,
                line: line
            )
        }
    }

    static func assertIDValidationRejectsDuplicatesAndMissingRecords(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(input: makePastureInput(name: "Validation Pasture"))
        let group = try repository.createGroup(
            input: PastureGroupInput(name: "Validation Group", grazeDays: 7, restDays: 21)
        )

        XCTAssertNoThrow(
            try repository.validatePastureIDsExist([pasture.id]),
            "Existing pasture IDs must pass validation.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try repository.validatePastureIDsExist([pasture.id, pasture.id]),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureIDs, file: file, line: line)
        }

        let missingPastureID = UUID()
        XCTAssertThrowsError(
            try repository.validatePastureIDsExist([missingPastureID]),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PastureRepositoryError,
                .pastureIDsNotFound([missingPastureID]),
                file: file,
                line: line
            )
        }

        XCTAssertNoThrow(
            try repository.validatePastureGroupIDsExist([group.id]),
            "Existing pasture-group IDs must pass validation.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try repository.validatePastureGroupIDsExist([group.id, group.id]),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureGroupIDs, file: file, line: line)
        }

        let missingGroupID = UUID()
        XCTAssertThrowsError(
            try repository.validatePastureGroupIDsExist([missingGroupID]),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PastureRepositoryError,
                .pastureGroupIDsNotFound([missingGroupID]),
                file: file,
                line: line
            )
        }
    }

    static func assertDeleteRemovesPasture(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(input: makePastureInput(name: "Delete Pasture"))

        try repository.delete(ids: [pasture.id])

        let reloadedRepository = fixture.makePastureRepository()
        XCTAssertNil(try reloadedRepository.fetchPastureDetail(id: pasture.id), file: file, line: line)
        XCTAssertFalse(try reloadedRepository.fetchPastures().contains { $0.id == pasture.id }, file: file, line: line)
        XCTAssertFalse(try reloadedRepository.fetchPastureOptions().contains { $0.id == pasture.id }, file: file, line: line)
    }

    private static func makePastureInput(name: String) -> PastureInput {
        PastureInput(
            name: name,
            acreage: 20,
            usableAcreage: 18,
            targetAcresPerHead: 1.5
        )
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID,
        tagColorID: UUID? = nil,
        damID: UUID? = nil,
        status: AnimalStatus = .active
    ) -> AnimalInput {
        let statusDate = Date(timeIntervalSince1970: 1_700_000_000)
        let saleDate: Date?
        let deathDate: Date?
        switch status {
        case .active:
            saleDate = nil
            deathDate = nil
        case .sold:
            saleDate = statusDate
            deathDate = nil
        case .dead:
            saleDate = nil
            deathDate = statusDate
        }

        return AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            sex: .female,
            birthDate: Date(timeIntervalSince1970: 1_577_836_800),
            status: status,
            pastureID: pastureID,
            sireID: nil,
            damID: damID,
            distinguishingFeatures: [],
            saleDate: saleDate,
            salePrice: nil,
            reasonSold: nil,
            deathDate: deathDate,
            causeOfDeath: nil,
            statusReferenceID: nil
        )
    }
}
