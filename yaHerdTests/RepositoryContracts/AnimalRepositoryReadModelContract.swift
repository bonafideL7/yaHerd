import XCTest
@testable import yaHerd

@MainActor
extension AnimalRepositoryContract {
    /// Permanent future-state coverage for repository read models that are consumed immediately
    /// after creation, while selecting parents, while preparing the Add Offspring editor, and when
    /// presenting pregnancy summary state.
    static func assertCreateSummaryAndOffspringDraftReadModels(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let createdBirthDate = contractDate(year: 2020, month: 1, day: 2)
        let createdDeathDate = contractDate(year: 2026, month: 1, day: 3)
        let createdTagColorID = TagColorDefaults.whiteID
        let createdStatusReference = try fixture.makeStatusReference("Create Summary Contract Deceased", .dead)
        let editedStatusReference = try fixture.makeStatusReference("Edited Summary Contract Deceased", .dead)
        let createdDistinguishingFeatures = [
            DistinguishingFeature(description: "White blaze", order: 0),
            DistinguishingFeature(description: "Black tail switch", order: 1)
        ]

        let created = try repository.create(
            input: readModelAnimalInput(
                name: "Create Summary Contract Heifer",
                tagNumber: "CS01",
                tagColorID: createdTagColorID,
                sex: .female,
                birthDate: createdBirthDate,
                status: .dead,
                deathDate: createdDeathDate,
                causeOfDeath: "Create summary contract",
                statusReferenceID: createdStatusReference.id,
                distinguishingFeatures: createdDistinguishingFeatures
            )
        )

        let createdSummaryRepository = fixture.makeAnimalRepository()
        let createdSummary = try XCTUnwrap(
            createdSummaryRepository.fetchAnimals().first { $0.id == created.id },
            "A newly created animal must be returned through the summary read API before any later update.",
            file: file,
            line: line
        )
        XCTAssertEqual(createdSummary.id, created.id, file: file, line: line)
        XCTAssertEqual(createdSummary.name, "Create Summary Contract Heifer", file: file, line: line)
        XCTAssertEqual(createdSummary.displayTagNumber, "CS01", file: file, line: line)
        XCTAssertEqual(createdSummary.displayTagColorID, createdTagColorID, file: file, line: line)
        XCTAssertNil(createdSummary.damDisplayTagNumber, file: file, line: line)
        XCTAssertNil(createdSummary.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(createdSummary.sex.rawValue, Sex.female.rawValue, file: file, line: line)
        XCTAssertEqual(createdSummary.animalType, .heifer, file: file, line: line)
        XCTAssertEqual(createdSummary.firstDistinguishingFeature, "White blaze", file: file, line: line)
        XCTAssertEqual(createdSummary.birthDate, createdBirthDate, file: file, line: line)
        XCTAssertEqual(createdSummary.status.rawValue, AnimalStatus.dead.rawValue, file: file, line: line)
        XCTAssertFalse(createdSummary.isArchived, file: file, line: line)
        XCTAssertNil(createdSummary.pastureID, file: file, line: line)
        XCTAssertNil(createdSummary.pastureName, file: file, line: line)
        XCTAssertEqual(createdSummary.location, .pasture, file: file, line: line)

        let editedDeathDate = contractDate(year: 2026, month: 2, day: 14)
        let editedCauseOfDeath = "Edited same-status cause"
        let sameStatusUpdated = try createdSummaryRepository.update(
            id: created.id,
            input: readModelAnimalInput(
                name: "Create Summary Contract Heifer",
                tagNumber: "CS01",
                tagColorID: createdTagColorID,
                sex: .female,
                birthDate: createdBirthDate,
                status: .dead,
                deathDate: editedDeathDate,
                causeOfDeath: editedCauseOfDeath,
                statusReferenceID: editedStatusReference.id,
                distinguishingFeatures: createdDistinguishingFeatures
            )
        )
        XCTAssertEqual(sameStatusUpdated.status.rawValue, AnimalStatus.dead.rawValue, file: file, line: line)
        XCTAssertEqual(sameStatusUpdated.deathDate, editedDeathDate, file: file, line: line)
        XCTAssertEqual(sameStatusUpdated.causeOfDeath, editedCauseOfDeath, file: file, line: line)
        XCTAssertEqual(sameStatusUpdated.statusReferenceID, editedStatusReference.id, file: file, line: line)
        XCTAssertEqual(sameStatusUpdated.statusReferenceName, editedStatusReference.name, file: file, line: line)

        let sameStatusReloadRepository = fixture.makeAnimalRepository()
        let reloadedSameStatusUpdate = try XCTUnwrap(
            sameStatusReloadRepository.fetchAnimalDetail(id: created.id),
            "Metadata edits made without changing the base status must survive a fresh repository reload.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedSameStatusUpdate.status.rawValue, AnimalStatus.dead.rawValue, file: file, line: line)
        XCTAssertEqual(reloadedSameStatusUpdate.deathDate, editedDeathDate, file: file, line: line)
        XCTAssertEqual(reloadedSameStatusUpdate.causeOfDeath, editedCauseOfDeath, file: file, line: line)
        XCTAssertEqual(reloadedSameStatusUpdate.statusReferenceID, editedStatusReference.id, file: file, line: line)
        XCTAssertEqual(reloadedSameStatusUpdate.statusReferenceName, editedStatusReference.name, file: file, line: line)

        let offspringPasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Offspring Draft Contract Pasture",
                acreage: 18,
                usableAcreage: 16,
                targetAcresPerHead: 1.5
            )
        )
        let inferredSire = try repository.create(
            input: readModelAnimalInput(
                name: "Offspring Draft Contract Sire",
                tagNumber: "OS01",
                tagColorID: TagColorDefaults.yellowID,
                sex: .male,
                birthDate: contractDate(year: 2018, month: 2, day: 3),
                pastureID: offspringPasture.id
            )
        )
        let dam = try repository.create(
            input: readModelAnimalInput(
                name: "Offspring Draft Contract Dam",
                tagNumber: "OD01",
                tagColorID: TagColorDefaults.blueID,
                sex: .female,
                birthDate: contractDate(year: 2019, month: 3, day: 4),
                pastureID: offspringPasture.id
            )
        )

        let parentOptionsRepository = fixture.makeAnimalRepository()
        let parentOptions = try parentOptionsRepository.fetchParentOptions(excluding: created.id)
        XCTAssertFalse(
            parentOptions.contains { $0.id == created.id },
            "The explicitly excluded animal must not be returned by the parent-options read API.",
            file: file,
            line: line
        )
        let sireOption = try XCTUnwrap(
            parentOptions.first { $0.id == inferredSire.id },
            "Persisted sire candidates must be returned through the parent-options read API.",
            file: file,
            line: line
        )
        XCTAssertEqual(sireOption.name, "Offspring Draft Contract Sire", file: file, line: line)
        XCTAssertEqual(sireOption.displayTagNumber, "OS01", file: file, line: line)
        XCTAssertEqual(sireOption.displayTagColorID, TagColorDefaults.yellowID, file: file, line: line)
        XCTAssertEqual(sireOption.sex.rawValue, Sex.male.rawValue, file: file, line: line)
        XCTAssertFalse(sireOption.isArchived, file: file, line: line)
        XCTAssertEqual(sireOption.displayName, "OS01", file: file, line: line)

        let damOption = try XCTUnwrap(
            parentOptions.first { $0.id == dam.id },
            "Persisted dam candidates must be returned through the parent-options read API.",
            file: file,
            line: line
        )
        XCTAssertEqual(damOption.name, "Offspring Draft Contract Dam", file: file, line: line)
        XCTAssertEqual(damOption.displayTagNumber, "OD01", file: file, line: line)
        XCTAssertEqual(damOption.displayTagColorID, TagColorDefaults.blueID, file: file, line: line)
        XCTAssertEqual(damOption.sex.rawValue, Sex.female.rawValue, file: file, line: line)
        XCTAssertFalse(damOption.isArchived, file: file, line: line)
        XCTAssertEqual(damOption.displayName, "OD01", file: file, line: line)

        let expectedDefaultBirthDate = Calendar.current.startOfDay(for: .now)
        let offspringDraftRepository = fixture.makeAnimalRepository()
        let seed = try XCTUnwrap(
            offspringDraftRepository.fetchOffspringDraftSeed(forDamID: dam.id),
            "A persisted dam must remain available through the offspring-draft read API.",
            file: file,
            line: line
        )
        XCTAssertEqual(seed.damID, dam.id, file: file, line: line)
        XCTAssertEqual(seed.damDisplayName, "OD01", file: file, line: line)
        XCTAssertEqual(seed.pastureID, offspringPasture.id, file: file, line: line)
        XCTAssertEqual(seed.pastureName, offspringPasture.name, file: file, line: line)
        XCTAssertEqual(seed.inferredSireID, inferredSire.id, file: file, line: line)
        XCTAssertEqual(seed.inferredSireDisplayName, "OS01", file: file, line: line)
        XCTAssertEqual(
            seed.defaultBirthDate,
            expectedDefaultBirthDate,
            "The offspring draft must default the birth date to the start of the current day.",
            file: file,
            line: line
        )

        let pregnancySummaryAnimal = try offspringDraftRepository.create(
            input: readModelAnimalInput(
                name: "Pregnancy Summary Contract Cow",
                tagNumber: "PS01",
                sex: .female,
                birthDate: contractDate(year: 2020, month: 5, day: 6)
            )
        )
        let pregnantCheckDate = contractDate(year: 2026, month: 5, day: 1)
        let pregnantDueDate = contractDate(year: 2027, month: 2, day: 8)
        _ = try offspringDraftRepository.addPregnancyCheck(
            animalID: pregnancySummaryAnimal.id,
            input: PregnancyCheckInput(
                date: pregnantCheckDate,
                result: .pregnant,
                technician: "Pregnancy Summary Contract Tech",
                estimatedDaysPregnant: nil,
                dueDate: pregnantDueDate,
                sireAnimalID: nil
            )
        )

        let pregnantSummaryRepository = fixture.makeAnimalRepository()
        let pregnantSummary = try XCTUnwrap(
            pregnantSummaryRepository.fetchAnimals().first { $0.id == pregnancySummaryAnimal.id },
            "The pregnant summary state must survive a fresh repository reload before a later check is recorded.",
            file: file,
            line: line
        )
        XCTAssertEqual(pregnantSummary.lastPregnancyCheckDate, pregnantCheckDate, file: file, line: line)
        XCTAssertEqual(pregnantSummary.lastPregnancyStatus, .pregnant, file: file, line: line)
        XCTAssertEqual(pregnantSummary.expectedCalvingDate, pregnantDueDate, file: file, line: line)

        let openCheckDate = contractDate(year: 2026, month: 6, day: 1)
        _ = try pregnantSummaryRepository.addPregnancyCheck(
            animalID: pregnancySummaryAnimal.id,
            input: PregnancyCheckInput(
                date: openCheckDate,
                result: .open,
                technician: "Pregnancy Summary Follow-up Tech",
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            )
        )

        let openSummaryRepository = fixture.makeAnimalRepository()
        let openSummary = try XCTUnwrap(
            openSummaryRepository.fetchAnimals().first { $0.id == pregnancySummaryAnimal.id },
            "A newer open pregnancy check must replace the prior pregnant summary state after reload.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            openSummary.lastPregnancyCheckDate,
            openCheckDate,
            "Pregnancy summary state must select the newest check by date regardless of result.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            openSummary.lastPregnancyStatus,
            .open,
            "A newer open check must clear the prior pregnant summary status.",
            file: file,
            line: line
        )
        XCTAssertNil(
            openSummary.expectedCalvingDate,
            "A newer open check must clear the prior expected calving date.",
            file: file,
            line: line
        )
    }

    private static func readModelAnimalInput(
        name: String,
        tagNumber: String,
        tagColorID: UUID? = nil,
        sex: Sex,
        birthDate: Date,
        status: AnimalStatus = .active,
        pastureID: UUID? = nil,
        deathDate: Date? = nil,
        causeOfDeath: String? = nil,
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
            sireID: nil,
            damID: nil,
            distinguishingFeatures: distinguishingFeatures,
            saleDate: nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: deathDate,
            causeOfDeath: causeOfDeath,
            statusReferenceID: statusReferenceID
        )
    }

    private static func contractDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
