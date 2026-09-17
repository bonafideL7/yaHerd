import XCTest
@testable import yaHerd

/// Permanent persistence-neutral behavioral contract for the production `AnimalRepository` implementation.
///
/// The future Core Data repository should execute these assertions through its concrete test fixture.
/// The contract intentionally asserts Domain-facing behavior only and does not inspect persistence models
/// or contexts.
@MainActor
struct AnimalRepositoryContractFixture {
    let makeAnimalRepository: () -> any AnimalRepository
    let makePastureRepository: () -> any PastureRepository
    let makeStatusReference: (_ name: String, _ baseStatus: AnimalStatus) throws -> AnimalStatusReferenceOption
}

@MainActor
enum AnimalRepositoryContract {
    static func assertCreateUpdateAndReload(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let createdBirthDate = date(year: 2020, month: 1, day: 2)
        let createdDeathDate = date(year: 2025, month: 12, day: 20)
        let createdCauseOfDeath = "Contract illness"
        let createdTagColorID = TagColorDefaults.whiteID
        let updatedTagColorID = TagColorDefaults.yellowID
        let updatedDamTagColorID = TagColorDefaults.blueID
        let createdStatusReference = try fixture.makeStatusReference("Contract Deceased", .dead)
        let updatedStatusReference = try fixture.makeStatusReference("Contract Sold", .sold)
        let createdDistinguishingFeatures = [
            DistinguishingFeature(description: "White blaze", order: 0),
            DistinguishingFeature(description: "Black tail switch", order: 1)
        ]

        let statusReferenceOptions = try fixture.makeAnimalRepository().fetchStatusReferenceOptions()
        let reloadedCreatedStatusReference = try XCTUnwrap(
            statusReferenceOptions.first { $0.id == createdStatusReference.id },
            "The created status reference must be returned through the repository read API.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedCreatedStatusReference.name, createdStatusReference.name, file: file, line: line)
        XCTAssertEqual(
            reloadedCreatedStatusReference.baseStatus.rawValue,
            AnimalStatus.dead.rawValue,
            "The dead status reference must retain its exact base status through the repository read API.",
            file: file,
            line: line
        )
        let reloadedUpdatedStatusReference = try XCTUnwrap(
            statusReferenceOptions.first { $0.id == updatedStatusReference.id },
            "The updated status reference must be returned through the repository read API.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedUpdatedStatusReference.name, updatedStatusReference.name, file: file, line: line)
        XCTAssertEqual(
            reloadedUpdatedStatusReference.baseStatus.rawValue,
            AnimalStatus.sold.rawValue,
            "The sold status reference must retain its exact base status through the repository read API.",
            file: file,
            line: line
        )

        let created = try repository.create(
            input: makeAnimalInput(
                name: "Contract Cow",
                tagNumber: "101",
                tagColorID: createdTagColorID,
                sex: .female,
                birthDate: createdBirthDate,
                status: .dead,
                deathDate: createdDeathDate,
                causeOfDeath: createdCauseOfDeath,
                statusReferenceID: createdStatusReference.id,
                distinguishingFeatures: createdDistinguishingFeatures
            )
        )

        XCTAssertEqual(created.name, "Contract Cow", file: file, line: line)
        XCTAssertEqual(created.displayTagNumber, "101", file: file, line: line)
        XCTAssertEqual(created.displayTagColorID, createdTagColorID, file: file, line: line)
        XCTAssertEqual(
            created.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "A tagged animal must have exactly one active primary tag after creation.",
            file: file,
            line: line
        )
        let createdPrimaryTag = try XCTUnwrap(
            created.activeTags.first { $0.isPrimary },
            file: file,
            line: line
        )
        XCTAssertTrue(createdPrimaryTag.isActive, file: file, line: line)
        XCTAssertEqual(createdPrimaryTag.number, "101", file: file, line: line)
        XCTAssertEqual(createdPrimaryTag.colorID, createdTagColorID, file: file, line: line)
        XCTAssertEqual(created.sex.rawValue, Sex.female.rawValue, file: file, line: line)
        XCTAssertEqual(created.birthDate, createdBirthDate, file: file, line: line)
        XCTAssertEqual(created.status.rawValue, AnimalStatus.dead.rawValue, file: file, line: line)
        XCTAssertEqual(created.deathDate, createdDeathDate, file: file, line: line)
        XCTAssertEqual(created.causeOfDeath, createdCauseOfDeath, file: file, line: line)
        XCTAssertEqual(created.statusReferenceID, createdStatusReference.id, file: file, line: line)
        XCTAssertEqual(created.statusReferenceName, createdStatusReference.name, file: file, line: line)
        XCTAssertEqual(
            created.distinguishingFeatures,
            createdDistinguishingFeatures,
            "Creating distinguishing features must preserve their UUIDs and ordering.",
            file: file,
            line: line
        )

        let reloadedCreated = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: created.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedCreated.name, "Contract Cow", file: file, line: line)
        XCTAssertEqual(reloadedCreated.displayTagNumber, "101", file: file, line: line)
        XCTAssertEqual(
            reloadedCreated.displayTagColorID,
            createdTagColorID,
            "Creating must persist the original tag color before later updates.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedCreated.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Reloading a tagged animal after creation must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        let reloadedCreatedPrimaryTag = try XCTUnwrap(
            reloadedCreated.activeTags.first { $0.id == createdPrimaryTag.id },
            "Creating must durably persist the original primary tag identity and payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(reloadedCreatedPrimaryTag.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedCreatedPrimaryTag.isActive, file: file, line: line)
        XCTAssertEqual(reloadedCreatedPrimaryTag.number, "101", file: file, line: line)
        XCTAssertEqual(reloadedCreatedPrimaryTag.colorID, createdTagColorID, file: file, line: line)
        XCTAssertEqual(
            reloadedCreated.sex.rawValue,
            Sex.female.rawValue,
            "Creating must persist the original sex before later updates.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedCreated.birthDate,
            createdBirthDate,
            "Creating must persist the original birth date before later updates.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedCreated.status.rawValue,
            AnimalStatus.dead.rawValue,
            "Creating must persist a non-default status before later updates.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedCreated.deathDate, createdDeathDate, file: file, line: line)
        XCTAssertEqual(reloadedCreated.causeOfDeath, createdCauseOfDeath, file: file, line: line)
        XCTAssertEqual(
            reloadedCreated.statusReferenceID,
            createdStatusReference.id,
            "Creating must persist the selected custom status reference before later updates.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedCreated.statusReferenceName, createdStatusReference.name, file: file, line: line)
        XCTAssertEqual(
            reloadedCreated.distinguishingFeatures,
            createdDistinguishingFeatures,
            "Reloading after creation must preserve exact distinguishing-feature identities and order.",
            file: file,
            line: line
        )

        let updatedBirthDate = date(year: 2019, month: 12, day: 15)
        let saleDate = date(year: 2026, month: 1, day: 15)
        let salePrice = 2475.50
        let reasonSold = "Contract sale"
        let updatedPasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Update Contract Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let updatedSire = try repository.create(
            input: makeAnimalInput(
                name: "Update Contract Sire",
                tagNumber: "US01",
                sex: .male,
                birthDate: date(year: 2015, month: 1, day: 1)
            )
        )
        let updatedDam = try repository.create(
            input: makeAnimalInput(
                name: "Update Contract Dam",
                tagNumber: "UD01",
                tagColorID: updatedDamTagColorID,
                sex: .female,
                birthDate: date(year: 2016, month: 1, day: 1)
            )
        )
        let updatedDistinguishingFeatures = [
            DistinguishingFeature(description: "White blaze", order: 0),
            DistinguishingFeature(description: "Left ear notch", order: 1)
        ]
        let updated = try repository.update(
            id: created.id,
            input: makeAnimalInput(
                name: "Updated Contract Cow",
                tagNumber: "102",
                tagColorID: updatedTagColorID,
                sex: .male,
                birthDate: updatedBirthDate,
                status: .sold,
                saleDate: saleDate,
                salePrice: salePrice,
                reasonSold: reasonSold,
                pastureID: updatedPasture.id,
                sireID: updatedSire.id,
                damID: updatedDam.id,
                statusReferenceID: updatedStatusReference.id,
                distinguishingFeatures: updatedDistinguishingFeatures
            )
        )

        XCTAssertEqual(updated.id, created.id, "Updating must preserve application UUID identity.", file: file, line: line)
        XCTAssertEqual(updated.name, "Updated Contract Cow", file: file, line: line)
        XCTAssertEqual(updated.displayTagNumber, "102", file: file, line: line)
        XCTAssertEqual(updated.displayTagColorID, updatedTagColorID, file: file, line: line)
        XCTAssertEqual(
            updated.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Updating a tagged animal must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        let updatedPrimaryTag = try XCTUnwrap(
            updated.activeTags.first { $0.id == createdPrimaryTag.id },
            "Updating editor tag fields must mutate the existing primary tag instead of replacing it.",
            file: file,
            line: line
        )
        XCTAssertTrue(updatedPrimaryTag.isPrimary, file: file, line: line)
        XCTAssertTrue(updatedPrimaryTag.isActive, file: file, line: line)
        XCTAssertEqual(updatedPrimaryTag.number, "102", file: file, line: line)
        XCTAssertEqual(updatedPrimaryTag.colorID, updatedTagColorID, file: file, line: line)
        XCTAssertEqual(
            updatedPrimaryTag.assignedAt,
            createdPrimaryTag.assignedAt,
            "Editing the primary tag must preserve its original assignment date.",
            file: file,
            line: line
        )
        XCTAssertEqual(updated.sex.rawValue, Sex.male.rawValue, file: file, line: line)
        XCTAssertEqual(updated.animalType, .bull, file: file, line: line)
        XCTAssertEqual(updated.birthDate, updatedBirthDate, file: file, line: line)
        XCTAssertEqual(updated.status.rawValue, AnimalStatus.sold.rawValue, file: file, line: line)
        XCTAssertEqual(updated.saleDate, saleDate, file: file, line: line)
        XCTAssertEqual(updated.salePrice, salePrice, file: file, line: line)
        XCTAssertEqual(updated.reasonSold, reasonSold, file: file, line: line)
        XCTAssertNil(updated.deathDate, "Transitioning from dead to sold must clear the prior death date.", file: file, line: line)
        XCTAssertNil(updated.causeOfDeath, "Transitioning from dead to sold must clear the prior cause of death.", file: file, line: line)
        XCTAssertEqual(updated.pastureID, updatedPasture.id, file: file, line: line)
        XCTAssertEqual(updated.pastureName, updatedPasture.name, file: file, line: line)
        XCTAssertEqual(updated.sireID, updatedSire.id, file: file, line: line)
        XCTAssertEqual(updated.sire, "US01", file: file, line: line)
        XCTAssertEqual(updated.damID, updatedDam.id, file: file, line: line)
        XCTAssertEqual(updated.dam, "UD01", file: file, line: line)
        XCTAssertEqual(updated.statusReferenceID, updatedStatusReference.id, file: file, line: line)
        XCTAssertEqual(updated.statusReferenceName, updatedStatusReference.name, file: file, line: line)
        XCTAssertEqual(
            updated.distinguishingFeatures,
            updatedDistinguishingFeatures,
            "Updating distinguishing features must preserve their UUIDs and ordering.",
            file: file,
            line: line
        )

        let reloadedRepository = fixture.makeAnimalRepository()
        let reloaded = try XCTUnwrap(
            reloadedRepository.fetchAnimalDetail(id: created.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.id, created.id, file: file, line: line)
        XCTAssertEqual(reloaded.name, "Updated Contract Cow", file: file, line: line)
        XCTAssertEqual(reloaded.displayTagNumber, "102", file: file, line: line)
        XCTAssertEqual(reloaded.displayTagColorID, updatedTagColorID, file: file, line: line)
        XCTAssertEqual(
            reloaded.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Reloading an updated tagged animal must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        let reloadedPrimaryTag = try XCTUnwrap(
            reloaded.activeTags.first { $0.id == createdPrimaryTag.id },
            "Reloading must preserve the edited primary tag identity and payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(reloadedPrimaryTag.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedPrimaryTag.isActive, file: file, line: line)
        XCTAssertEqual(reloadedPrimaryTag.number, "102", file: file, line: line)
        XCTAssertEqual(reloadedPrimaryTag.colorID, updatedTagColorID, file: file, line: line)
        XCTAssertEqual(
            reloadedPrimaryTag.assignedAt,
            createdPrimaryTag.assignedAt,
            "Reloading the edited primary tag must preserve its original assignment date.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.sex.rawValue, Sex.male.rawValue, file: file, line: line)
        XCTAssertEqual(reloaded.animalType, .bull, file: file, line: line)
        XCTAssertEqual(reloaded.birthDate, updatedBirthDate, file: file, line: line)
        XCTAssertEqual(reloaded.status.rawValue, AnimalStatus.sold.rawValue, file: file, line: line)
        XCTAssertEqual(reloaded.saleDate, saleDate, file: file, line: line)
        XCTAssertEqual(reloaded.salePrice, salePrice, file: file, line: line)
        XCTAssertEqual(reloaded.reasonSold, reasonSold, file: file, line: line)
        XCTAssertNil(reloaded.deathDate, "Reloading a sold animal must not restore the prior death date.", file: file, line: line)
        XCTAssertNil(reloaded.causeOfDeath, "Reloading a sold animal must not restore the prior cause of death.", file: file, line: line)
        XCTAssertEqual(reloaded.pastureID, updatedPasture.id, file: file, line: line)
        XCTAssertEqual(reloaded.pastureName, updatedPasture.name, file: file, line: line)
        XCTAssertEqual(reloaded.location, .pasture, file: file, line: line)
        XCTAssertEqual(reloaded.sireID, updatedSire.id, file: file, line: line)
        XCTAssertEqual(reloaded.sire, "US01", file: file, line: line)
        XCTAssertEqual(reloaded.damID, updatedDam.id, file: file, line: line)
        XCTAssertEqual(reloaded.dam, "UD01", file: file, line: line)
        XCTAssertEqual(reloaded.statusReferenceID, updatedStatusReference.id, file: file, line: line)
        XCTAssertEqual(reloaded.statusReferenceName, updatedStatusReference.name, file: file, line: line)
        XCTAssertEqual(reloaded.distinguishingFeatures, updatedDistinguishingFeatures, file: file, line: line)

        let reloadedSummary = try XCTUnwrap(
            reloadedRepository.fetchAnimals().first { $0.id == created.id },
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedSummary.name, "Updated Contract Cow", file: file, line: line)
        XCTAssertEqual(reloadedSummary.displayTagNumber, "102", file: file, line: line)
        XCTAssertEqual(reloadedSummary.displayTagColorID, updatedTagColorID, file: file, line: line)
        XCTAssertEqual(reloadedSummary.sex.rawValue, Sex.male.rawValue, file: file, line: line)
        XCTAssertEqual(reloadedSummary.animalType, .bull, file: file, line: line)
        XCTAssertEqual(reloadedSummary.birthDate, updatedBirthDate, file: file, line: line)
        XCTAssertEqual(reloadedSummary.status.rawValue, AnimalStatus.sold.rawValue, file: file, line: line)
        XCTAssertEqual(reloadedSummary.pastureID, updatedPasture.id, file: file, line: line)
        XCTAssertEqual(reloadedSummary.pastureName, updatedPasture.name, file: file, line: line)
        XCTAssertEqual(reloadedSummary.location, .pasture, file: file, line: line)
        XCTAssertEqual(reloadedSummary.damDisplayTagNumber, "UD01", file: file, line: line)
        XCTAssertEqual(reloadedSummary.damDisplayTagColorID, updatedDamTagColorID, file: file, line: line)
        XCTAssertEqual(reloadedSummary.firstDistinguishingFeature, "White blaze", file: file, line: line)

        let timeline = try reloadedRepository.fetchTimeline(id: created.id)
        XCTAssertTrue(
            timeline.contains {
                guard case .status = $0.type else { return false }
                return $0.title == "Status Change" && $0.details == "Dead → Sold"
            },
            "Updating status must create durable history for the exact dead-to-sold transition.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            timeline.contains {
                isMovementEvent($0, from: "—", to: updatedPasture.name)
            },
            "Updating pasture through the repository must create durable movement history from unassigned to the selected pasture.",
            file: file,
            line: line
        )

        let cleared = try reloadedRepository.update(
            id: created.id,
            input: makeAnimalInput(
                name: "Updated Contract Cow",
                tagNumber: "102",
                tagColorID: updatedTagColorID,
                sex: .male,
                birthDate: updatedBirthDate,
                status: .active,
                distinguishingFeatures: updatedDistinguishingFeatures
            )
        )
        XCTAssertEqual(cleared.status.rawValue, AnimalStatus.active.rawValue, file: file, line: line)
        XCTAssertEqual(
            cleared.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Clearing other editable fields must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        XCTAssertNil(cleared.saleDate, "Leaving sold status must clear the prior sale date.", file: file, line: line)
        XCTAssertNil(cleared.salePrice, "Leaving sold status must clear the prior sale price.", file: file, line: line)
        XCTAssertNil(cleared.reasonSold, "Leaving sold status must clear the prior sale reason.", file: file, line: line)
        XCTAssertNil(cleared.statusReferenceID, "Updating with a nil status reference must clear the existing relationship.", file: file, line: line)
        XCTAssertNil(cleared.statusReferenceName, file: file, line: line)
        XCTAssertNil(cleared.pastureID, "Updating with a nil pasture must clear the existing relationship.", file: file, line: line)
        XCTAssertNil(cleared.pastureName, file: file, line: line)
        XCTAssertNil(cleared.sireID, "Updating with a nil sire must clear the existing relationship.", file: file, line: line)
        XCTAssertNil(cleared.sire, file: file, line: line)
        XCTAssertNil(cleared.damID, "Updating with a nil dam must clear the existing relationship.", file: file, line: line)
        XCTAssertNil(cleared.dam, file: file, line: line)
        XCTAssertEqual(
            cleared.distinguishingFeatures,
            updatedDistinguishingFeatures,
            "Clearing unrelated editable fields must preserve exact distinguishing-feature identities and order.",
            file: file,
            line: line
        )

        let clearedRepository = fixture.makeAnimalRepository()
        let reloadedCleared = try XCTUnwrap(
            clearedRepository.fetchAnimalDetail(id: created.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedCleared.status.rawValue, AnimalStatus.active.rawValue, file: file, line: line)
        XCTAssertEqual(
            reloadedCleared.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Reloading after clearing other editable fields must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        XCTAssertNil(reloadedCleared.saleDate, "Cleared sale date must remain nil after reload.", file: file, line: line)
        XCTAssertNil(reloadedCleared.salePrice, "Cleared sale price must remain nil after reload.", file: file, line: line)
        XCTAssertNil(reloadedCleared.reasonSold, "Cleared sale reason must remain nil after reload.", file: file, line: line)
        XCTAssertNil(reloadedCleared.statusReferenceID, "Cleared status reference must remain nil after reload.", file: file, line: line)
        XCTAssertNil(reloadedCleared.statusReferenceName, file: file, line: line)
        XCTAssertNil(reloadedCleared.pastureID, "Cleared pasture must remain nil after reload.", file: file, line: line)
        XCTAssertNil(reloadedCleared.pastureName, file: file, line: line)
        XCTAssertEqual(reloadedCleared.location, .pasture, file: file, line: line)
        XCTAssertNil(reloadedCleared.sireID, "Cleared sire must remain nil after reload.", file: file, line: line)
        XCTAssertNil(reloadedCleared.sire, file: file, line: line)
        XCTAssertNil(reloadedCleared.damID, "Cleared dam must remain nil after reload.", file: file, line: line)
        XCTAssertNil(reloadedCleared.dam, file: file, line: line)
        XCTAssertEqual(
            reloadedCleared.distinguishingFeatures,
            updatedDistinguishingFeatures,
            "Reloading after clearing unrelated fields must preserve exact distinguishing-feature identities and order.",
            file: file,
            line: line
        )

        let clearedSummary = try XCTUnwrap(
            clearedRepository.fetchAnimals().first { $0.id == created.id },
            "Clearing status and relationships must be reflected in the summary read model.",
            file: file,
            line: line
        )
        XCTAssertEqual(clearedSummary.status.rawValue, AnimalStatus.active.rawValue, file: file, line: line)
        XCTAssertNil(clearedSummary.pastureID, "Cleared pasture must be nil in the summary read model.", file: file, line: line)
        XCTAssertNil(clearedSummary.pastureName, "Cleared pasture name must be nil in the summary read model.", file: file, line: line)
        XCTAssertEqual(clearedSummary.location, .pasture, file: file, line: line)
        XCTAssertNil(clearedSummary.damDisplayTagNumber, "Cleared dam must be nil in the summary read model.", file: file, line: line)
        XCTAssertNil(clearedSummary.damDisplayTagColorID, "Cleared dam tag color must be nil in the summary read model.", file: file, line: line)

        let clearedTimeline = try clearedRepository.fetchTimeline(id: created.id)
        XCTAssertTrue(
            clearedTimeline.contains {
                isMovementEvent($0, from: updatedPasture.name, to: "—")
            },
            "Clearing pasture through the repository must create durable movement history from the prior pasture to unassigned.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            clearedTimeline.contains {
                guard case .status = $0.type else { return false }
                return $0.title == "Status Change" && $0.details == "Sold → Active"
            },
            "Leaving sold status must create durable history for the exact sold-to-active transition.",
            file: file,
            line: line
        )
    }

    static func assertArchiveRestorePreservesHistory(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let created = try repository.create(
            input: makeAnimalInput(
                name: "Archive Contract Cow",
                tagNumber: "201",
                sex: .female,
                birthDate: date(year: 2019, month: 4, day: 3)
            )
        )
        let treatmentDate = date(year: 2026, month: 2, day: 10)
        let treatment = "Contract vaccination"
        let treatmentNotes = "Preserve across archive"
        _ = try repository.addHealthRecord(
            animalID: created.id,
            input: HealthRecordInput(
                date: treatmentDate,
                treatment: treatment,
                notes: treatmentNotes
            )
        )

        try repository.archive(ids: [created.id])

        let archivedRepository = fixture.makeAnimalRepository()
        let archived = try XCTUnwrap(
            archivedRepository.fetchAnimalDetail(id: created.id),
            file: file,
            line: line
        )
        XCTAssertEqual(archived.id, created.id, file: file, line: line)
        XCTAssertTrue(archived.isArchived, file: file, line: line)
        XCTAssertNotNil(archived.archivedAt, file: file, line: line)
        let archivedSummary = try XCTUnwrap(
            archivedRepository.fetchAnimals().first { $0.id == created.id },
            "Archiving must mark the summary read model as archived.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            archivedSummary.isArchived,
            "Archived animals must remain archived in the summary read model used by animal-list filtering.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try archivedRepository.fetchTimeline(id: created.id).contains {
                isHealthEvent(
                    $0,
                    date: treatmentDate,
                    treatment: treatment,
                    notes: treatmentNotes
                )
            },
            "Archiving must preserve the complete historical health record.",
            file: file,
            line: line
        )

        try archivedRepository.restore(ids: [created.id])

        let restoredRepository = fixture.makeAnimalRepository()
        let restored = try XCTUnwrap(
            restoredRepository.fetchAnimalDetail(id: created.id),
            file: file,
            line: line
        )
        XCTAssertEqual(restored.id, created.id, file: file, line: line)
        XCTAssertFalse(restored.isArchived, file: file, line: line)
        XCTAssertNil(restored.archivedAt, file: file, line: line)
        let restoredSummary = try XCTUnwrap(
            restoredRepository.fetchAnimals().first { $0.id == created.id },
            "Restoring must return the animal through the summary read model.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            restoredSummary.isArchived,
            "Restored animals must no longer be archived in the summary read model used by animal-list filtering.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try restoredRepository.fetchTimeline(id: created.id).contains {
                isHealthEvent(
                    $0,
                    date: treatmentDate,
                    treatment: treatment,
                    notes: treatmentNotes
                )
            },
            "Restoring must retain the complete historical health record.",
            file: file,
            line: line
        )
    }

    static func assertMovementUpdatesPastureAndTimeline(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let north = try pastureRepository.create(
            input: PastureInput(name: "Contract North", acreage: 25, usableAcreage: 22, targetAcresPerHead: 1.5)
        )
        let south = try pastureRepository.create(
            input: PastureInput(name: "Contract South", acreage: 30, usableAcreage: 28, targetAcresPerHead: 1.75)
        )

        let animalRepository = fixture.makeAnimalRepository()
        let animal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Movement Contract Cow",
                tagNumber: "301",
                sex: .female,
                birthDate: date(year: 2021, month: 3, day: 4),
                pastureID: north.id
            )
        )

        try animalRepository.move(ids: [animal.id], toPastureID: south.id)

        let reloadedRepository = fixture.makeAnimalRepository()
        let reloaded = try XCTUnwrap(
            reloadedRepository.fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.pastureID, south.id, file: file, line: line)
        XCTAssertEqual(reloaded.pastureName, south.name, file: file, line: line)
        XCTAssertTrue(
            try reloadedRepository.fetchTimeline(id: animal.id).contains {
                isMovementEvent($0, from: north.name, to: south.name)
            },
            "Moving an animal must create durable history for the specific source and destination pastures.",
            file: file,
            line: line
        )

        let reloadedPastures = fixture.makePastureRepository()
        XCTAssertFalse(
            try reloadedPastures.fetchResidentAnimals(pastureID: north.id).contains { $0.id == animal.id },
            file: file,
            line: line
        )
        XCTAssertTrue(
            try reloadedPastures.fetchResidentAnimals(pastureID: south.id).contains { $0.id == animal.id },
            file: file,
            line: line
        )

        try reloadedRepository.move(ids: [animal.id], toPastureID: nil)

        let unassignedRepository = fixture.makeAnimalRepository()
        let unassigned = try XCTUnwrap(
            unassignedRepository.fetchAnimalDetail(id: animal.id),
            "Moving to a nil destination must durably unassign the animal from its pasture.",
            file: file,
            line: line
        )
        XCTAssertNil(unassigned.pastureID, file: file, line: line)
        XCTAssertNil(unassigned.pastureName, file: file, line: line)
        XCTAssertTrue(
            try unassignedRepository.fetchTimeline(id: animal.id).contains {
                isMovementEvent($0, from: south.name, to: "—")
            },
            "Moving to a nil destination must create durable history from the prior pasture to unassigned.",
            file: file,
            line: line
        )

        let unassignedPastures = fixture.makePastureRepository()
        XCTAssertFalse(
            try unassignedPastures.fetchResidentAnimals(pastureID: south.id).contains { $0.id == animal.id },
            "An animal moved to a nil destination must no longer appear in the prior pasture's resident lookup.",
            file: file,
            line: line
        )
    }

    static func assertTagLifecyclePreservesHistory(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let created = try repository.create(
            input: makeAnimalInput(
                name: "Tag Contract Cow",
                tagNumber: "401",
                sex: .female,
                birthDate: date(year: 2020, month: 5, day: 6)
            )
        )
        let originalTag = try XCTUnwrap(
            created.activeTags.first { $0.number == "401" },
            file: file,
            line: line
        )

        let replacementColorID = TagColorDefaults.yellowID
        let withReplacement = try repository.addTag(
            animalID: created.id,
            input: AnimalTagInput(number: "402", colorID: replacementColorID, isPrimary: true)
        )
        XCTAssertEqual(
            withReplacement.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Adding a primary tag must leave exactly one active primary tag.",
            file: file,
            line: line
        )
        let replacementTag = try XCTUnwrap(
            withReplacement.activeTags.first { $0.number == "402" },
            file: file,
            line: line
        )
        XCTAssertTrue(replacementTag.isPrimary, file: file, line: line)
        XCTAssertEqual(replacementTag.colorID, replacementColorID, file: file, line: line)
        XCTAssertEqual(withReplacement.displayTagNumber, "402", file: file, line: line)
        XCTAssertEqual(withReplacement.displayTagColorID, replacementColorID, file: file, line: line)
        XCTAssertTrue(withReplacement.activeTags.contains { $0.id == originalTag.id }, file: file, line: line)

        let addedTagRepository = fixture.makeAnimalRepository()
        let reloadedAfterAdd = try XCTUnwrap(
            addedTagRepository.fetchAnimalDetail(id: created.id),
            "Adding a tag must persist before any later tag mutation occurs.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedAfterAdd.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Reloading immediately after addTag must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        let reloadedReplacementAfterAdd = try XCTUnwrap(
            reloadedAfterAdd.activeTags.first { $0.id == replacementTag.id },
            "The newly added tag must survive a fresh-repository reload before any subsequent mutation.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedReplacementAfterAdd.number, "402", file: file, line: line)
        XCTAssertEqual(reloadedReplacementAfterAdd.colorID, replacementColorID, file: file, line: line)
        XCTAssertTrue(reloadedReplacementAfterAdd.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedReplacementAfterAdd.isActive, file: file, line: line)
        XCTAssertEqual(reloadedReplacementAfterAdd.assignedAt, replacementTag.assignedAt, file: file, line: line)
        let reloadedOriginalAfterAdd = try XCTUnwrap(
            reloadedAfterAdd.activeTags.first { $0.id == originalTag.id },
            file: file,
            line: line
        )
        XCTAssertFalse(reloadedOriginalAfterAdd.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedOriginalAfterAdd.isActive, file: file, line: line)
        XCTAssertEqual(reloadedAfterAdd.displayTagNumber, "402", file: file, line: line)
        XCTAssertEqual(reloadedAfterAdd.displayTagColorID, replacementColorID, file: file, line: line)

        let updatedOriginalColorID = TagColorDefaults.blueID
        let withUpdatedOriginal = try addedTagRepository.updateTag(
            animalID: created.id,
            tagID: originalTag.id,
            input: AnimalTagInput(number: "403", colorID: updatedOriginalColorID, isPrimary: true)
        )
        XCTAssertEqual(
            withUpdatedOriginal.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Promoting an updated tag must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        XCTAssertEqual(withUpdatedOriginal.displayTagNumber, "403", file: file, line: line)
        XCTAssertEqual(withUpdatedOriginal.displayTagColorID, updatedOriginalColorID, file: file, line: line)
        let updatedOriginalTag = try XCTUnwrap(
            withUpdatedOriginal.activeTags.first { $0.id == originalTag.id },
            file: file,
            line: line
        )
        XCTAssertEqual(updatedOriginalTag.number, "403", file: file, line: line)
        XCTAssertEqual(updatedOriginalTag.colorID, updatedOriginalColorID, file: file, line: line)
        XCTAssertTrue(updatedOriginalTag.isPrimary, file: file, line: line)
        XCTAssertTrue(updatedOriginalTag.isActive, file: file, line: line)
        XCTAssertEqual(updatedOriginalTag.assignedAt, originalTag.assignedAt, file: file, line: line)

        let updatedTagRepository = fixture.makeAnimalRepository()
        let reloadedAfterTagUpdate = try XCTUnwrap(
            updatedTagRepository.fetchAnimalDetail(id: created.id),
            "Updating an existing tag must persist its exact identity, payload, and primary state.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedAfterTagUpdate.displayTagNumber, "403", file: file, line: line)
        XCTAssertEqual(reloadedAfterTagUpdate.displayTagColorID, updatedOriginalColorID, file: file, line: line)
        let reloadedUpdatedOriginalTag = try XCTUnwrap(
            reloadedAfterTagUpdate.activeTags.first { $0.id == originalTag.id },
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedUpdatedOriginalTag.number, "403", file: file, line: line)
        XCTAssertEqual(reloadedUpdatedOriginalTag.colorID, updatedOriginalColorID, file: file, line: line)
        XCTAssertTrue(reloadedUpdatedOriginalTag.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedUpdatedOriginalTag.isActive, file: file, line: line)
        XCTAssertEqual(reloadedUpdatedOriginalTag.assignedAt, originalTag.assignedAt, file: file, line: line)
        let reloadedReplacementBeforeRetire = try XCTUnwrap(
            reloadedAfterTagUpdate.activeTags.first { $0.id == replacementTag.id },
            file: file,
            line: line
        )
        XCTAssertFalse(reloadedReplacementBeforeRetire.isPrimary, file: file, line: line)
        XCTAssertEqual(reloadedReplacementBeforeRetire.number, "402", file: file, line: line)
        XCTAssertEqual(reloadedReplacementBeforeRetire.colorID, replacementColorID, file: file, line: line)

        let withPromotedReplacement = try updatedTagRepository.promoteTag(
            animalID: created.id,
            tagID: replacementTag.id
        )
        XCTAssertEqual(
            withPromotedReplacement.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "The standalone promoteTag mutation must leave exactly one active primary tag.",
            file: file,
            line: line
        )
        let promotedReplacement = try XCTUnwrap(
            withPromotedReplacement.activeTags.first { $0.id == replacementTag.id },
            file: file,
            line: line
        )
        XCTAssertTrue(promotedReplacement.isPrimary, file: file, line: line)
        XCTAssertTrue(promotedReplacement.isActive, file: file, line: line)
        XCTAssertEqual(promotedReplacement.number, "402", file: file, line: line)
        XCTAssertEqual(promotedReplacement.colorID, replacementColorID, file: file, line: line)
        XCTAssertEqual(withPromotedReplacement.displayTagNumber, "402", file: file, line: line)
        let demotedOriginal = try XCTUnwrap(
            withPromotedReplacement.activeTags.first { $0.id == originalTag.id },
            file: file,
            line: line
        )
        XCTAssertFalse(demotedOriginal.isPrimary, file: file, line: line)
        XCTAssertTrue(demotedOriginal.isActive, file: file, line: line)

        let promotedTagRepository = fixture.makeAnimalRepository()
        let reloadedAfterPromotion = try XCTUnwrap(
            promotedTagRepository.fetchAnimalDetail(id: created.id),
            "Promoting a tag through the dedicated repository method must survive a fresh-repository reload.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedAfterPromotion.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Reloading after promoteTag must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        let reloadedPromotedReplacement = try XCTUnwrap(
            reloadedAfterPromotion.activeTags.first { $0.id == replacementTag.id },
            file: file,
            line: line
        )
        XCTAssertTrue(reloadedPromotedReplacement.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedPromotedReplacement.isActive, file: file, line: line)
        XCTAssertEqual(reloadedPromotedReplacement.number, "402", file: file, line: line)
        XCTAssertEqual(reloadedPromotedReplacement.colorID, replacementColorID, file: file, line: line)
        XCTAssertEqual(reloadedPromotedReplacement.assignedAt, replacementTag.assignedAt, file: file, line: line)
        let reloadedDemotedOriginal = try XCTUnwrap(
            reloadedAfterPromotion.activeTags.first { $0.id == originalTag.id },
            file: file,
            line: line
        )
        XCTAssertFalse(reloadedDemotedOriginal.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedDemotedOriginal.isActive, file: file, line: line)
        XCTAssertEqual(reloadedDemotedOriginal.number, "403", file: file, line: line)
        XCTAssertEqual(reloadedDemotedOriginal.colorID, updatedOriginalColorID, file: file, line: line)
        XCTAssertEqual(reloadedAfterPromotion.displayTagNumber, "402", file: file, line: line)

        let restoredOriginalPrimary = try promotedTagRepository.promoteTag(
            animalID: created.id,
            tagID: originalTag.id
        )
        XCTAssertEqual(
            restoredOriginalPrimary.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Restoring the updated original tag as primary must preserve the single-primary invariant before retirement.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            restoredOriginalPrimary.activeTags.contains { $0.id == originalTag.id && $0.isPrimary && $0.isActive },
            file: file,
            line: line
        )
        XCTAssertTrue(
            restoredOriginalPrimary.activeTags.contains { $0.id == replacementTag.id && !$0.isPrimary && $0.isActive },
            file: file,
            line: line
        )

        _ = try promotedTagRepository.retireTag(animalID: created.id, tagID: originalTag.id)

        let reloadedRepository = fixture.makeAnimalRepository()
        let reloaded = try XCTUnwrap(
            reloadedRepository.fetchAnimalDetail(id: created.id),
            file: file,
            line: line
        )
        let reloadedReplacement = try XCTUnwrap(
            reloaded.activeTags.first { $0.id == replacementTag.id },
            file: file,
            line: line
        )
        XCTAssertTrue(reloadedReplacement.isPrimary, file: file, line: line)
        XCTAssertEqual(reloadedReplacement.number, "402", file: file, line: line)
        XCTAssertEqual(reloadedReplacement.colorID, replacementColorID, file: file, line: line)
        XCTAssertFalse(reloaded.activeTags.contains { $0.id == originalTag.id }, file: file, line: line)
        let retiredTag = try XCTUnwrap(
            reloaded.inactiveTags.first { $0.id == originalTag.id },
            file: file,
            line: line
        )
        XCTAssertEqual(retiredTag.number, "403", file: file, line: line)
        XCTAssertEqual(retiredTag.colorID, updatedOriginalColorID, file: file, line: line)
        XCTAssertNotNil(retiredTag.removedAt, file: file, line: line)

        let timeline = try reloadedRepository.fetchTimeline(id: created.id)
        XCTAssertTrue(
            timeline.contains { isTagEvent($0, title: "Tag Assigned", number: "402") },
            "Adding the replacement tag must create assignment history for tag 402.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            timeline.contains { isTagEvent($0, title: "Tag Retired", number: "403") },
            "Retiring the updated original tag must create retirement history for its current number 403.",
            file: file,
            line: line
        )

        let secondaryMutationRepository = fixture.makeAnimalRepository()
        let secondaryPrimaryColorID = TagColorDefaults.whiteID
        let secondaryUpdatedColorID = TagColorDefaults.blueID
        let secondaryMutationAnimal = try secondaryMutationRepository.create(
            input: makeAnimalInput(
                name: "Secondary Tag Contract Cow",
                tagNumber: "411",
                tagColorID: secondaryPrimaryColorID,
                sex: .female,
                birthDate: date(year: 2020, month: 5, day: 7)
            )
        )
        let secondaryPrimaryTag = try XCTUnwrap(
            secondaryMutationAnimal.activeTags.first { $0.isPrimary && $0.isActive },
            file: file,
            line: line
        )
        let withSecondaryTag = try secondaryMutationRepository.addTag(
            animalID: secondaryMutationAnimal.id,
            input: AnimalTagInput(number: "412", colorID: replacementColorID, isPrimary: false)
        )
        let secondaryTag = try XCTUnwrap(
            withSecondaryTag.activeTags.first { $0.number == "412" },
            file: file,
            line: line
        )
        XCTAssertFalse(secondaryTag.isPrimary, file: file, line: line)
        XCTAssertEqual(withSecondaryTag.displayTagNumber, "411", file: file, line: line)
        XCTAssertEqual(withSecondaryTag.displayTagColorID, secondaryPrimaryColorID, file: file, line: line)

        let withEditedSecondaryTag = try secondaryMutationRepository.updateTag(
            animalID: secondaryMutationAnimal.id,
            tagID: secondaryTag.id,
            input: AnimalTagInput(number: "413", colorID: secondaryUpdatedColorID, isPrimary: false)
        )
        XCTAssertEqual(
            withEditedSecondaryTag.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            "Editing a secondary tag without promotion must preserve exactly one active primary tag.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            withEditedSecondaryTag.activeTags.contains {
                $0.id == secondaryPrimaryTag.id && $0.isPrimary && $0.isActive
            },
            "Editing a secondary tag with isPrimary false must not replace the existing primary tag.",
            file: file,
            line: line
        )
        let editedSecondaryTag = try XCTUnwrap(
            withEditedSecondaryTag.activeTags.first { $0.id == secondaryTag.id },
            file: file,
            line: line
        )
        XCTAssertEqual(editedSecondaryTag.number, "413", file: file, line: line)
        XCTAssertEqual(editedSecondaryTag.colorID, secondaryUpdatedColorID, file: file, line: line)
        XCTAssertFalse(editedSecondaryTag.isPrimary, file: file, line: line)
        XCTAssertTrue(editedSecondaryTag.isActive, file: file, line: line)
        XCTAssertEqual(editedSecondaryTag.assignedAt, secondaryTag.assignedAt, file: file, line: line)
        XCTAssertEqual(withEditedSecondaryTag.displayTagNumber, "411", file: file, line: line)
        XCTAssertEqual(withEditedSecondaryTag.displayTagColorID, secondaryPrimaryColorID, file: file, line: line)

        let secondaryReloadRepository = fixture.makeAnimalRepository()
        let reloadedAfterSecondaryEdit = try XCTUnwrap(
            secondaryReloadRepository.fetchAnimalDetail(id: secondaryMutationAnimal.id),
            "Editing a secondary tag without promotion must persist without changing the primary tag.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedAfterSecondaryEdit.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            file: file,
            line: line
        )
        let reloadedSecondaryPrimary = try XCTUnwrap(
            reloadedAfterSecondaryEdit.activeTags.first { $0.id == secondaryPrimaryTag.id },
            file: file,
            line: line
        )
        XCTAssertTrue(reloadedSecondaryPrimary.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedSecondaryPrimary.isActive, file: file, line: line)
        XCTAssertEqual(reloadedSecondaryPrimary.number, "411", file: file, line: line)
        XCTAssertEqual(reloadedSecondaryPrimary.colorID, secondaryPrimaryColorID, file: file, line: line)
        let reloadedEditedSecondary = try XCTUnwrap(
            reloadedAfterSecondaryEdit.activeTags.first { $0.id == secondaryTag.id },
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedEditedSecondary.number, "413", file: file, line: line)
        XCTAssertEqual(reloadedEditedSecondary.colorID, secondaryUpdatedColorID, file: file, line: line)
        XCTAssertFalse(reloadedEditedSecondary.isPrimary, file: file, line: line)
        XCTAssertTrue(reloadedEditedSecondary.isActive, file: file, line: line)
        XCTAssertEqual(reloadedEditedSecondary.assignedAt, secondaryTag.assignedAt, file: file, line: line)
        XCTAssertEqual(reloadedAfterSecondaryEdit.displayTagNumber, "411", file: file, line: line)
        XCTAssertEqual(reloadedAfterSecondaryEdit.displayTagColorID, secondaryPrimaryColorID, file: file, line: line)

        _ = try secondaryReloadRepository.retireTag(
            animalID: secondaryMutationAnimal.id,
            tagID: secondaryTag.id
        )

        let retiredSecondaryRepository = fixture.makeAnimalRepository()
        let reloadedAfterSecondaryRetire = try XCTUnwrap(
            retiredSecondaryRepository.fetchAnimalDetail(id: secondaryMutationAnimal.id),
            "Retiring a nonprimary tag must persist without changing the existing primary tag.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedAfterSecondaryRetire.activeTags.filter { $0.isPrimary && $0.isActive }.count,
            1,
            file: file,
            line: line
        )
        let primaryAfterSecondaryRetire = try XCTUnwrap(
            reloadedAfterSecondaryRetire.activeTags.first { $0.id == secondaryPrimaryTag.id },
            file: file,
            line: line
        )
        XCTAssertTrue(primaryAfterSecondaryRetire.isPrimary, file: file, line: line)
        XCTAssertTrue(primaryAfterSecondaryRetire.isActive, file: file, line: line)
        XCTAssertEqual(primaryAfterSecondaryRetire.number, "411", file: file, line: line)
        XCTAssertEqual(primaryAfterSecondaryRetire.colorID, secondaryPrimaryColorID, file: file, line: line)
        XCTAssertEqual(reloadedAfterSecondaryRetire.displayTagNumber, "411", file: file, line: line)
        XCTAssertEqual(reloadedAfterSecondaryRetire.displayTagColorID, secondaryPrimaryColorID, file: file, line: line)
        XCTAssertFalse(
            reloadedAfterSecondaryRetire.activeTags.contains { $0.id == secondaryTag.id },
            file: file,
            line: line
        )
        let retiredSecondaryTag = try XCTUnwrap(
            reloadedAfterSecondaryRetire.inactiveTags.first { $0.id == secondaryTag.id },
            file: file,
            line: line
        )
        XCTAssertEqual(retiredSecondaryTag.number, "413", file: file, line: line)
        XCTAssertEqual(retiredSecondaryTag.colorID, secondaryUpdatedColorID, file: file, line: line)
        XCTAssertEqual(retiredSecondaryTag.assignedAt, secondaryTag.assignedAt, file: file, line: line)
        XCTAssertNotNil(retiredSecondaryTag.removedAt, file: file, line: line)
        XCTAssertTrue(
            try retiredSecondaryRepository.fetchTimeline(id: secondaryMutationAnimal.id).contains {
                isTagEvent($0, title: "Tag Retired", number: "413")
            },
            "Retiring a nonprimary tag must create retirement history without changing the current primary.",
            file: file,
            line: line
        )
    }

    static func assertParentRelationshipsSurviveReload(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let sire = try repository.create(
            input: makeAnimalInput(
                name: "Contract Sire",
                tagNumber: "S01",
                sex: .male,
                birthDate: date(year: 2018, month: 1, day: 1)
            )
        )
        let dam = try repository.create(
            input: makeAnimalInput(
                name: "Contract Dam",
                tagNumber: "D01",
                sex: .female,
                birthDate: date(year: 2019, month: 1, day: 1)
            )
        )
        let calf = try repository.create(
            input: makeAnimalInput(
                name: "Contract Calf",
                tagNumber: "C01",
                sex: .female,
                birthDate: date(year: 2025, month: 2, day: 1),
                sireID: sire.id,
                damID: dam.id
            )
        )

        let reloadedRepository = fixture.makeAnimalRepository()
        let reloadedCalf = try XCTUnwrap(
            reloadedRepository.fetchAnimalDetail(id: calf.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedCalf.sireID, sire.id, file: file, line: line)
        XCTAssertEqual(reloadedCalf.damID, dam.id, file: file, line: line)

        var reloadedDam = try XCTUnwrap(
            reloadedRepository.fetchAnimalDetail(id: dam.id),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedDam.maternalOffspringCountIncludingArchived, 1, file: file, line: line)
        XCTAssertTrue(reloadedDam.maternalOffspring.contains { $0.id == calf.id }, file: file, line: line)

        try reloadedRepository.archive(ids: [calf.id])
        reloadedDam = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: dam.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedDam.maternalOffspringCountIncludingArchived,
            1,
            "Archiving offspring must not break parent relationship history.",
            file: file,
            line: line
        )
        XCTAssertTrue(reloadedDam.maternalOffspring.contains { $0.id == calf.id }, file: file, line: line)
    }

    static func assertHealthAndPregnancyRecordsSurviveReload(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let animal = try repository.create(
            input: makeAnimalInput(
                name: "Records Contract Cow",
                tagNumber: "501",
                sex: .female,
                birthDate: date(year: 2020, month: 6, day: 7)
            )
        )
        let treatmentDate = date(year: 2026, month: 3, day: 1)
        let treatment = "Contract treatment"
        let treatmentNotes = "Repository contract"
        let pregnancyDate = date(year: 2026, month: 3, day: 2)
        let pregnancyResult = PregnancyResult.pregnant
        let technician = "Contract Tech"
        let pregnancyDueDate = date(year: 2026, month: 9, day: 1)

        _ = try repository.addHealthRecord(
            animalID: animal.id,
            input: HealthRecordInput(
                date: treatmentDate,
                treatment: treatment,
                notes: treatmentNotes
            )
        )

        let healthReloadRepository = fixture.makeAnimalRepository()
        XCTAssertTrue(
            try healthReloadRepository.fetchTimeline(id: animal.id).contains {
                isHealthEvent(
                    $0,
                    date: treatmentDate,
                    treatment: treatment,
                    notes: treatmentNotes
                )
            },
            "Adding a health record must durably persist it before any later mutation occurs.",
            file: file,
            line: line
        )

        _ = try repository.addPregnancyCheck(
            animalID: animal.id,
            input: PregnancyCheckInput(
                date: pregnancyDate,
                result: pregnancyResult,
                technician: technician,
                estimatedDaysPregnant: 90,
                dueDate: pregnancyDueDate,
                sireAnimalID: nil
            )
        )

        let reloadedRepository = fixture.makeAnimalRepository()
        let timeline = try reloadedRepository.fetchTimeline(id: animal.id)
        XCTAssertTrue(
            timeline.contains {
                isHealthEvent(
                    $0,
                    date: treatmentDate,
                    treatment: treatment,
                    notes: treatmentNotes
                )
            },
            "Reloading must preserve the complete health record exposed through the timeline.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            timeline.contains {
                isPregnancyEvent(
                    $0,
                    date: pregnancyDate,
                    result: pregnancyResult,
                    technician: technician
                )
            },
            "Reloading must preserve the pregnancy result and technician exposed through the timeline.",
            file: file,
            line: line
        )

        let summary = try XCTUnwrap(
            reloadedRepository.fetchAnimals().first { $0.id == animal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.lastTreatmentDate, treatmentDate, file: file, line: line)
        XCTAssertEqual(summary.lastPregnancyCheckDate, pregnancyDate, file: file, line: line)
        XCTAssertEqual(
            summary.lastPregnancyStatus,
            AnimalPregnancyStatus.pregnant,
            "Reloading must preserve the latest pregnancy result exposed through the animal summary.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            summary.expectedCalvingDate,
            pregnancyDueDate,
            "Reloading must preserve the explicit pregnancy due date exposed through the animal summary.",
            file: file,
            line: line
        )
    }

    static func assertDeleteRemovesAggregate(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let animal = try repository.create(
            input: makeAnimalInput(
                name: "Delete Contract Cow",
                tagNumber: "601",
                sex: .female,
                birthDate: date(year: 2020, month: 7, day: 8)
            )
        )
        _ = try repository.addHealthRecord(
            animalID: animal.id,
            input: HealthRecordInput(
                date: date(year: 2026, month: 4, day: 1),
                treatment: "Delete contract treatment",
                notes: nil
            )
        )

        try repository.delete(ids: [animal.id])

        let reloadedRepository = fixture.makeAnimalRepository()
        XCTAssertNil(try reloadedRepository.fetchAnimalDetail(id: animal.id), file: file, line: line)
        XCTAssertFalse(try reloadedRepository.fetchAnimals().contains { $0.id == animal.id }, file: file, line: line)
        XCTAssertTrue(try reloadedRepository.fetchTimeline(id: animal.id).isEmpty, file: file, line: line)
        XCTAssertFalse(
            try reloadedRepository.fetchParentOptions(excluding: nil).contains { $0.id == animal.id },
            file: file,
            line: line
        )
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        tagColorID: UUID? = nil,
        sex: Sex,
        birthDate: Date,
        status: AnimalStatus = .active,
        saleDate: Date? = nil,
        salePrice: Double? = nil,
        reasonSold: String? = nil,
        deathDate: Date? = nil,
        causeOfDeath: String? = nil,
        pastureID: UUID? = nil,
        sireID: UUID? = nil,
        damID: UUID? = nil,
        statusReferenceID: UUID? = nil,
        distinguishingFeatures: [DistinguishingFeature] = []
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            sex: sex,
            birthDate: birthDate,
            status: status,
            pastureID: pastureID,
            sireID: sireID,
            damID: damID,
            distinguishingFeatures: distinguishingFeatures,
            saleDate: saleDate,
            salePrice: salePrice,
            reasonSold: reasonSold,
            deathDate: deathDate,
            causeOfDeath: causeOfDeath,
            statusReferenceID: statusReferenceID
        )
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }

    private static func isHealthEvent(
        _ event: AnimalTimelineEvent,
        date: Date,
        treatment: String,
        notes: String?
    ) -> Bool {
        guard case .health = event.type else { return false }
        return event.date == date
            && event.title == treatment
            && event.details == notes
    }

    private static func isPregnancyEvent(
        _ event: AnimalTimelineEvent,
        date: Date,
        result: PregnancyResult,
        technician: String?
    ) -> Bool {
        guard case .pregnancy = event.type else { return false }
        return event.date == date
            && event.title == "Pregnancy Check: \(result.rawValue.capitalized)"
            && event.details == technician
    }

    private static func isMovementEvent(
        _ event: AnimalTimelineEvent,
        from sourcePasture: String,
        to destinationPasture: String
    ) -> Bool {
        guard case .movement = event.type else { return false }
        return event.title == "Pasture Movement"
            && event.details == "\(sourcePasture) → \(destinationPasture)"
    }

    private static func isTagEvent(
        _ event: AnimalTimelineEvent,
        title: String,
        number: String
    ) -> Bool {
        guard case .tag = event.type else { return false }
        return event.title == title && event.details == number
    }
}
