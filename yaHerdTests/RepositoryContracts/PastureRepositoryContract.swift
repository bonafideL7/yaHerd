import XCTest
@testable import yaHerd

/// Permanent persistence-neutral behavioral contract for `PastureRepository` implementations.
///
/// The current SwiftData repository is only a characterization runner for behavior it already
/// implements. Production Core Data repositories should run these same assertions unchanged.
/// The contract deliberately stays at Domain repository boundaries.
@MainActor
struct PastureRepositoryContractFixture {
    let makePastureRepository: () -> any PastureRepository
    let makeAnimalRepository: () -> any AnimalRepository
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

        let reloaded = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastureDetail(id: created.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded, updated, file: file, line: line)
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

        let tag20 = try animalRepository.create(
            input: makeAnimalInput(name: "Tag 20", tagNumber: "20", pastureID: pasture.id)
        )
        let tag3 = try animalRepository.create(
            input: makeAnimalInput(name: "Tag 3", tagNumber: "3", pastureID: pasture.id)
        )
        let archived = try animalRepository.create(
            input: makeAnimalInput(name: "Archived", tagNumber: "99", pastureID: pasture.id)
        )
        _ = try animalRepository.create(
            input: makeAnimalInput(name: "Other Pasture", tagNumber: "1", pastureID: otherPasture.id)
        )
        try animalRepository.archive(ids: [archived.id])

        let reloadedPastures = fixture.makePastureRepository()
        let residents = try reloadedPastures.fetchResidentAnimals(pastureID: pasture.id)
        XCTAssertEqual(residents.map(\.id), [tag3.id, tag20.id], file: file, line: line)

        let detail = try XCTUnwrap(
            reloadedPastures.fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(detail.activeAnimalCount, 2, file: file, line: line)
    }

    static func assertGroupLifecycleAndPastureAssignment(
        using fixture: PastureRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makePastureRepository()
        let pasture = try repository.create(input: makePastureInput(name: "Grouped Pasture"))
        let createdGroup = try repository.createGroup(
            input: PastureGroupInput(name: "  Rotation A  ", grazeDays: 5, restDays: 25)
        )

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

        try reloadedRepository.deleteGroups(ids: [createdGroup.id])

        XCTAssertNil(
            try fixture.makePastureRepository().fetchPastureGroupDetail(id: createdGroup.id),
            file: file,
            line: line
        )
        let pastureAfterGroupDelete = try XCTUnwrap(
            fixture.makePastureRepository().fetchPastureDetail(id: pasture.id),
            file: file,
            line: line
        )
        XCTAssertNil(pastureAfterGroupDelete.groupID, file: file, line: line)
        XCTAssertNil(pastureAfterGroupDelete.groupName, file: file, line: line)
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

    private static func makeAnimalInput(name: String, tagNumber: String, pastureID: UUID) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: Date(timeIntervalSince1970: 1_577_836_800),
            status: .active,
            pastureID: pastureID,
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
    }
}
