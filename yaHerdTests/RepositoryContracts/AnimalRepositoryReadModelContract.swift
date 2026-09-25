import XCTest
@testable import yaHerd

@MainActor
struct AnimalActiveHerdReadProjectionContractFixture {
    let animalFixture: AnimalRepositoryContractFixture
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
}

@MainActor
struct AnimalHealthDashboardReadProjectionContractFixture {
    let animalFixture: AnimalRepositoryContractFixture
    let makeAggregateReader: () -> any AnimalAggregateEditReading
    let makeDashboardRepository: () -> any DashboardRepository
    let makeDashboardQueryReader: () -> any DashboardQueryReading
}

@MainActor
struct AnimalPastureRenameReadProjectionContractFixture {
    let animalFixture: AnimalRepositoryContractFixture
    let makeAggregateReader: () -> any AnimalAggregateEditReading
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
}

@MainActor
struct AnimalListReadProjectionContractFixture {
    let animalFixture: AnimalRepositoryContractFixture
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading

    /// Setup-only deterministic identity seeding for pagination tie-break coverage.
    ///
    /// The target runner must commit the supplied Animal into the same isolated backing store used
    /// by `animalFixture` and every query reader, preserve `animalID` exactly as application
    /// identity, and return the resulting Domain detail snapshot. This hook exists only because the
    /// public Animal repository create API generates UUIDs internally; it must not become a
    /// production mutation API or a compatibility requirement.
    let seedAnimalWithID: (_ animalID: UUID, _ input: AnimalInput) throws -> AnimalDetailSnapshot
}

private enum AnimalReadModelTimelineKind: Hashable {
    case birth
    case health
    case pregnancy
    case movement
    case status
    case tag
}

private struct AnimalReadModelTimelineSignature: Hashable {
    let kind: AnimalReadModelTimelineKind
    let date: Date
    let title: String
    let details: String?
}

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
        let otherBullPasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Offspring Draft Other Bull Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let offPastureSire = try repository.create(
            input: readModelAnimalInput(
                name: "Offspring Draft Off-Pasture Sire",
                tagNumber: "OS02",
                tagColorID: TagColorDefaults.whiteID,
                sex: .male,
                birthDate: contractDate(year: 2017, month: 1, day: 2),
                pastureID: otherBullPasture.id
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
        XCTAssertEqual(
            seed.inferredSireID,
            inferredSire.id,
            "Sire inference must choose the sole eligible bull in the dam's pasture even when another eligible bull exists elsewhere.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            seed.inferredSireID,
            offPastureSire.id,
            "An eligible bull from another pasture must not be inferred as the sire.",
            file: file,
            line: line
        )
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

    /// Permanent integration coverage for live Pasture-name fan-out into Animal-facing read
    /// projections while movement history retains the names captured when the movement occurred.
    static func assertHealthAndPregnancyMutationsPropagateToDashboard(
        using fixture: AnimalHealthDashboardReadProjectionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let repository = fixture.animalFixture.makeAnimalRepository()
        let target = try repository.create(
            input: readModelAnimalInput(
                name: "Health Dashboard Contract Cow",
                tagNumber: "HDC01",
                sex: .female,
                birthDate: contractDate(year: 2019, month: 4, day: 5)
            )
        )
        let control = try repository.create(
            input: readModelAnimalInput(
                name: "Health Dashboard Control Cow",
                tagNumber: "HDC02",
                sex: .female,
                birthDate: contractDate(year: 2018, month: 5, day: 6)
            )
        )

        let targetAggregateBefore = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: target.id),
            file: file,
            line: line
        )
        let controlAggregateBefore = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: control.id),
            file: file,
            line: line
        )
        let controlSummaryBefore = try XCTUnwrap(
            repository.fetchAnimals().first { $0.id == control.id },
            file: file,
            line: line
        )
        let controlDashboardBefore = try await fetchDashboardAnimalRecord(
            id: control.id,
            reader: fixture.makeDashboardQueryReader(),
            file: file,
            line: line
        )

        try await assertHealthPregnancyDashboardState(
            animalID: target.id,
            expectedLastTreatmentDate: nil,
            expectedHealthRecords: [],
            expectedPregnancyDate: nil,
            expectedPregnancyStatus: nil,
            expectedDashboardPregnancyStatus: nil,
            expectedCalvingDate: nil,
            aggregateBefore: targetAggregateBefore,
            fixture: fixture,
            file: file,
            line: line
        )

        let newestHealthDate = contractDate(year: 2026, month: 8, day: 20)
        let newestHealth = DashboardHealthRecord(
            date: newestHealthDate,
            treatment: "Health Dashboard vaccination",
            notes: "Newest treatment"
        )
        _ = try repository.addHealthRecord(
            animalID: target.id,
            input: HealthRecordInput(
                date: newestHealth.date,
                treatment: newestHealth.treatment,
                notes: newestHealth.notes
            )
        )
        try await assertHealthPregnancyDashboardState(
            animalID: target.id,
            expectedLastTreatmentDate: newestHealthDate,
            expectedHealthRecords: [newestHealth],
            expectedPregnancyDate: nil,
            expectedPregnancyStatus: nil,
            expectedDashboardPregnancyStatus: nil,
            expectedCalvingDate: nil,
            aggregateBefore: targetAggregateBefore,
            fixture: fixture,
            file: file,
            line: line
        )

        let backdatedHealth = DashboardHealthRecord(
            date: contractDate(year: 2026, month: 7, day: 15),
            treatment: "Health Dashboard backdated treatment",
            notes: nil
        )
        _ = try repository.addHealthRecord(
            animalID: target.id,
            input: HealthRecordInput(
                date: backdatedHealth.date,
                treatment: backdatedHealth.treatment,
                notes: backdatedHealth.notes
            )
        )
        try await assertHealthPregnancyDashboardState(
            animalID: target.id,
            expectedLastTreatmentDate: newestHealthDate,
            expectedHealthRecords: [newestHealth, backdatedHealth],
            expectedPregnancyDate: nil,
            expectedPregnancyStatus: nil,
            expectedDashboardPregnancyStatus: nil,
            expectedCalvingDate: nil,
            aggregateBefore: targetAggregateBefore,
            fixture: fixture,
            file: file,
            line: line
        )

        let pregnantDate = contractDate(year: 2026, month: 8, day: 22)
        let dueDate = contractDate(year: 2027, month: 5, day: 29)
        _ = try repository.addPregnancyCheck(
            animalID: target.id,
            input: PregnancyCheckInput(
                date: pregnantDate,
                result: .pregnant,
                technician: "Health Dashboard Tech",
                estimatedDaysPregnant: 30,
                dueDate: dueDate,
                sireAnimalID: nil
            )
        )
        try await assertHealthPregnancyDashboardState(
            animalID: target.id,
            expectedLastTreatmentDate: newestHealthDate,
            expectedHealthRecords: [newestHealth, backdatedHealth],
            expectedPregnancyDate: pregnantDate,
            expectedPregnancyStatus: .pregnant,
            expectedDashboardPregnancyStatus: .pregnant,
            expectedCalvingDate: dueDate,
            aggregateBefore: targetAggregateBefore,
            fixture: fixture,
            file: file,
            line: line
        )

        _ = try repository.addPregnancyCheck(
            animalID: target.id,
            input: PregnancyCheckInput(
                date: contractDate(year: 2026, month: 7, day: 10),
                result: .open,
                technician: "Health Dashboard Backdated Tech",
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            )
        )
        try await assertHealthPregnancyDashboardState(
            animalID: target.id,
            expectedLastTreatmentDate: newestHealthDate,
            expectedHealthRecords: [newestHealth, backdatedHealth],
            expectedPregnancyDate: pregnantDate,
            expectedPregnancyStatus: .pregnant,
            expectedDashboardPregnancyStatus: .pregnant,
            expectedCalvingDate: dueDate,
            aggregateBefore: targetAggregateBefore,
            fixture: fixture,
            file: file,
            line: line
        )

        let openDate = contractDate(year: 2026, month: 9, day: 1)
        _ = try repository.addPregnancyCheck(
            animalID: target.id,
            input: PregnancyCheckInput(
                date: openDate,
                result: .open,
                technician: "Health Dashboard Follow-up Tech",
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            )
        )
        try await assertHealthPregnancyDashboardState(
            animalID: target.id,
            expectedLastTreatmentDate: newestHealthDate,
            expectedHealthRecords: [newestHealth, backdatedHealth],
            expectedPregnancyDate: openDate,
            expectedPregnancyStatus: .open,
            expectedDashboardPregnancyStatus: .open,
            expectedCalvingDate: nil,
            aggregateBefore: targetAggregateBefore,
            fixture: fixture,
            file: file,
            line: line
        )

        let controlAggregateAfter = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: control.id),
            file: file,
            line: line
        )
        XCTAssertEqual(controlAggregateAfter, controlAggregateBefore, file: file, line: line)

        let controlSummaryAfter = try XCTUnwrap(
            fixture.animalFixture.makeAnimalRepository().fetchAnimals().first { $0.id == control.id },
            file: file,
            line: line
        )
        XCTAssertEqual(controlSummaryAfter, controlSummaryBefore, file: file, line: line)

        let controlDashboardAfter = try await fetchDashboardAnimalRecord(
            id: control.id,
            reader: fixture.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(controlDashboardAfter, controlDashboardBefore, file: file, line: line)

        let bullRepository = fixture.animalFixture.makeAnimalRepository()
        let bull = try bullRepository.create(
            input: readModelAnimalInput(
                name: "Health Dashboard Castration Bull",
                tagNumber: "HDC03",
                sex: .male,
                birthDate: contractDate(year: 2021, month: 1, day: 10)
            )
        )
        XCTAssertEqual(bull.animalType, .bull, file: file, line: line)

        let bullAggregateBefore = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: bull.id),
            file: file,
            line: line
        )
        XCTAssertEqual(bullAggregateBefore.animal.animalType, .bull, file: file, line: line)

        let castrationDate = contractDate(year: 2026, month: 9, day: 3)
        let castrationRecord = DashboardHealthRecord(
            date: castrationDate,
            treatment: "Castration",
            notes: nil
        )
        let bullAfterCastration = try bullRepository.addHealthRecord(
            animalID: bull.id,
            input: HealthRecordInput(
                date: castrationRecord.date,
                treatment: castrationRecord.treatment,
                notes: castrationRecord.notes
            )
        )
        XCTAssertEqual(bullAfterCastration.animalType, .steer, file: file, line: line)

        let bullAggregateAfter = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: bull.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            bullAggregateAfter.revision,
            bullAggregateBefore.revision,
            "Health-derived animal type is not editor-owned aggregate state and must not rotate the aggregate revision.",
            file: file,
            line: line
        )
        assertAnimalDetailPreservedAcrossDerivedTypeChange(
            bullAggregateAfter.animal,
            before: bullAggregateBefore.animal,
            expectedAnimalType: .steer,
            file: file,
            line: line
        )

        let bullSummaryAfter = try XCTUnwrap(
            fixture.animalFixture.makeAnimalRepository().fetchAnimals().first { $0.id == bull.id },
            file: file,
            line: line
        )
        XCTAssertEqual(bullSummaryAfter.animalType, .steer, file: file, line: line)
        XCTAssertEqual(bullSummaryAfter.lastTreatmentDate, castrationDate, file: file, line: line)

        let synchronousBullDashboard = try XCTUnwrap(
            fixture.makeDashboardRepository().fetchDashboardRecords().animals.first { $0.id == bull.id },
            file: file,
            line: line
        )
        XCTAssertEqual(synchronousBullDashboard.animalType, .steer, file: file, line: line)
        XCTAssertEqual(synchronousBullDashboard.lastTreatmentDate, castrationDate, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(synchronousBullDashboard.healthRecords),
            multisetCounts([castrationRecord]),
            file: file,
            line: line
        )

        let productionBullDashboard = try await fetchDashboardAnimalRecord(
            id: bull.id,
            reader: fixture.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(productionBullDashboard, synchronousBullDashboard, file: file, line: line)
    }

    private static func assertHealthPregnancyDashboardState(
        animalID: UUID,
        expectedLastTreatmentDate: Date?,
        expectedHealthRecords: [DashboardHealthRecord],
        expectedPregnancyDate: Date?,
        expectedPregnancyStatus: AnimalPregnancyStatus?,
        expectedDashboardPregnancyStatus: DashboardPregnancyStatus?,
        expectedCalvingDate: Date?,
        aggregateBefore: AnimalAggregateEditSnapshot,
        fixture: AnimalHealthDashboardReadProjectionContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let animalRepository = fixture.animalFixture.makeAnimalRepository()
        let detail = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: animalID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            detail,
            aggregateBefore.animal,
            "Representative non-type-changing health/pregnancy writes must not mutate editor-owned Animal detail state.",
            file: file,
            line: line
        )

        let aggregate = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: animalID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            aggregate,
            aggregateBefore,
            "Health/pregnancy child rows are outside AnimalAggregateAttributes/tag state and must not rotate or rewrite the open aggregate editor snapshot.",
            file: file,
            line: line
        )

        let summary = try XCTUnwrap(
            animalRepository.fetchAnimals().first { $0.id == animalID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.lastTreatmentDate, expectedLastTreatmentDate, file: file, line: line)
        XCTAssertEqual(summary.lastPregnancyCheckDate, expectedPregnancyDate, file: file, line: line)
        XCTAssertEqual(summary.lastPregnancyStatus, expectedPregnancyStatus, file: file, line: line)
        XCTAssertEqual(summary.expectedCalvingDate, expectedCalvingDate, file: file, line: line)

        let synchronousDashboard = fixture.makeDashboardRepository()
        let synchronous = try XCTUnwrap(
            synchronousDashboard.fetchDashboardRecords().animals.first { $0.id == animalID },
            file: file,
            line: line
        )
        assertHealthPregnancyDashboardRecord(
            synchronous,
            expectedLastTreatmentDate: expectedLastTreatmentDate,
            expectedHealthRecords: expectedHealthRecords,
            expectedPregnancyDate: expectedPregnancyDate,
            expectedPregnancyStatus: expectedDashboardPregnancyStatus,
            expectedCalvingDate: expectedCalvingDate,
            file: file,
            line: line
        )

        let productionReader = fixture.makeDashboardQueryReader()
        let productionAll = try await productionReader.fetchDashboardRecords()
        let production = try XCTUnwrap(
            productionAll.animals.first { $0.id == animalID },
            file: file,
            line: line
        )
        assertHealthPregnancyDashboardRecord(
            production,
            expectedLastTreatmentDate: expectedLastTreatmentDate,
            expectedHealthRecords: expectedHealthRecords,
            expectedPregnancyDate: expectedPregnancyDate,
            expectedPregnancyStatus: expectedDashboardPregnancyStatus,
            expectedCalvingDate: expectedCalvingDate,
            file: file,
            line: line
        )
        XCTAssertEqual(production, synchronous, file: file, line: line)

        let active = try await productionReader.fetchDashboardAnimalRecords(kind: .active)
        XCTAssertEqual(
            try XCTUnwrap(active.first { $0.id == animalID }, file: file, line: line),
            production,
            "Health/pregnancy updates must be visible through the production Dashboard/Home active-Animal query as well as the full records query.",
            file: file,
            line: line
        )
    }

    private static func assertHealthPregnancyDashboardRecord(
        _ actual: DashboardAnimalRecord,
        expectedLastTreatmentDate: Date?,
        expectedHealthRecords: [DashboardHealthRecord],
        expectedPregnancyDate: Date?,
        expectedPregnancyStatus: DashboardPregnancyStatus?,
        expectedCalvingDate: Date?,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.lastTreatmentDate, expectedLastTreatmentDate, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(actual.healthRecords),
            multisetCounts(expectedHealthRecords),
            "Dashboard health history must contain the exact committed payload multiset independent of relationship ordering.",
            file: file,
            line: line
        )
        XCTAssertEqual(actual.lastPregnancyCheckDate, expectedPregnancyDate, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyStatus, expectedPregnancyStatus, file: file, line: line)
        XCTAssertEqual(actual.expectedCalvingDate, expectedCalvingDate, file: file, line: line)
    }

    static func assertPastureRenamePropagatesToLiveAnimalProjections(
        using fixture: AnimalPastureRenameReadProjectionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let animalFixture = fixture.animalFixture
        let animalRepository = animalFixture.makeAnimalRepository()
        let pastureRepository = animalFixture.makePastureRepository()
        let originalPastureName = "Pasture Rename Live Original"
        let renamedPastureName = "Pasture Rename Live Updated"

        let sourcePasture = try pastureRepository.create(
            input: PastureInput(
                name: "Pasture Rename Source Control",
                acreage: 18,
                usableAcreage: 16,
                targetAcresPerHead: 1.25
            )
        )
        let targetPasture = try pastureRepository.create(
            input: PastureInput(
                name: originalPastureName,
                acreage: 24,
                usableAcreage: 22,
                targetAcresPerHead: 1.5
            )
        )

        let target = try animalRepository.create(
            input: readModelAnimalInput(
                name: "Pasture Rename Dam",
                tagNumber: "PRD01",
                tagColorID: TagColorDefaults.yellowID,
                sex: .female,
                birthDate: contractDate(year: 2018, month: 4, day: 5),
                pastureID: sourcePasture.id,
                distinguishingFeatures: [
                    DistinguishingFeature(description: "Pasture rename control blaze", order: 0)
                ]
            )
        )
        let unrelated = try animalRepository.create(
            input: readModelAnimalInput(
                name: "Pasture Rename Unrelated",
                tagNumber: "PRU01",
                sex: .female,
                birthDate: contractDate(year: 2017, month: 6, day: 7),
                pastureID: sourcePasture.id
            )
        )

        try animalRepository.move(ids: [target.id], toPastureID: targetPasture.id)

        let targetBefore = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: target.id),
            file: file,
            line: line
        )
        XCTAssertEqual(targetBefore.pastureID, targetPasture.id, file: file, line: line)
        XCTAssertEqual(targetBefore.pastureName, originalPastureName, file: file, line: line)

        let targetSummaryBefore = try XCTUnwrap(
            animalRepository.fetchAnimals().first { $0.id == target.id },
            file: file,
            line: line
        )
        XCTAssertEqual(targetSummaryBefore.pastureName, originalPastureName, file: file, line: line)

        let aggregateBefore = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: target.id),
            file: file,
            line: line
        )
        XCTAssertEqual(aggregateBefore.animal.pastureID, targetPasture.id, file: file, line: line)
        XCTAssertEqual(aggregateBefore.animal.pastureName, originalPastureName, file: file, line: line)

        let seedBefore = try XCTUnwrap(
            animalRepository.fetchOffspringDraftSeed(forDamID: target.id),
            file: file,
            line: line
        )
        XCTAssertEqual(seedBefore.pastureID, targetPasture.id, file: file, line: line)
        XCTAssertEqual(seedBefore.pastureName, originalPastureName, file: file, line: line)

        let timelineBefore = try animalRepository.fetchTimeline(id: target.id)
        let birthBefore = try primaryBirthEvent(
            in: timelineBefore,
            birthDate: targetBefore.birthDate,
            file: file,
            line: line
        )
        XCTAssertEqual(
            birthBefore.details,
            "Pasture: \(originalPastureName)",
            file: file,
            line: line
        )
        let durableTimelineBefore = timelineSignaturesExcludingPrimaryBirth(
            timelineBefore,
            birthDate: targetBefore.birthDate
        )
        XCTAssertTrue(
            durableTimelineBefore.contains {
                $0.kind == .movement
                    && $0.title == "Pasture Movement"
                    && $0.details == "\(sourcePasture.name) → \(originalPastureName)"
            },
            "The fixture must persist a movement event that captures the pre-rename Pasture name.",
            file: file,
            line: line
        )

        let unrelatedBefore = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: unrelated.id),
            file: file,
            line: line
        )
        let unrelatedSummaryBefore = try XCTUnwrap(
            animalRepository.fetchAnimals().first { $0.id == unrelated.id },
            file: file,
            line: line
        )
        let unrelatedTimelineBefore = timelineSignatures(
            try animalRepository.fetchTimeline(id: unrelated.id)
        )
        let sourcePastureBefore = try XCTUnwrap(
            pastureRepository.fetchPastureDetail(id: sourcePasture.id),
            file: file,
            line: line
        )

        let dashboardBefore = try await fixture.makeDashboardQueryReader().fetchDashboardRecords()
        let targetDashboardBefore = try XCTUnwrap(
            dashboardBefore.animals.first { $0.id == target.id },
            file: file,
            line: line
        )
        let unrelatedDashboardBefore = try XCTUnwrap(
            dashboardBefore.animals.first { $0.id == unrelated.id },
            file: file,
            line: line
        )
        let targetDashboardPastureBefore = try XCTUnwrap(
            dashboardBefore.pastures.first { $0.id == targetPasture.id },
            file: file,
            line: line
        )
        let sourceDashboardPastureBefore = try XCTUnwrap(
            dashboardBefore.pastures.first { $0.id == sourcePasture.id },
            file: file,
            line: line
        )

        let updatedPasture = try pastureRepository.update(
            id: targetPasture.id,
            input: PastureInput(
                name: renamedPastureName,
                acreage: targetPasture.acreage,
                usableAcreage: targetPasture.usableAcreage,
                targetAcresPerHead: targetPasture.targetAcresPerHead
            )
        )
        XCTAssertEqual(updatedPasture.id, targetPasture.id, file: file, line: line)
        XCTAssertEqual(updatedPasture.name, renamedPastureName, file: file, line: line)
        XCTAssertEqual(updatedPasture.acreage, targetPasture.acreage, file: file, line: line)
        XCTAssertEqual(updatedPasture.usableAcreage, targetPasture.usableAcreage, file: file, line: line)
        XCTAssertEqual(
            updatedPasture.targetAcresPerHead,
            targetPasture.targetAcresPerHead,
            file: file,
            line: line
        )

        let freshAnimalRepository = animalFixture.makeAnimalRepository()
        let freshPastureRepository = animalFixture.makePastureRepository()

        let targetAfter = try XCTUnwrap(
            freshAnimalRepository.fetchAnimalDetail(id: target.id),
            file: file,
            line: line
        )
        assertAnimalDetailPreservedAcrossPastureRename(
            targetAfter,
            before: targetBefore,
            expectedPastureName: renamedPastureName,
            file: file,
            line: line
        )

        let targetSummaryAfter = try XCTUnwrap(
            freshAnimalRepository.fetchAnimals().first { $0.id == target.id },
            file: file,
            line: line
        )
        assertAnimalSummaryPreservedAcrossPastureRename(
            targetSummaryAfter,
            before: targetSummaryBefore,
            expectedPastureName: renamedPastureName,
            file: file,
            line: line
        )

        let aggregateAfter = try XCTUnwrap(
            fixture.makeAggregateReader().fetchAnimalAggregateForEditing(id: target.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            aggregateAfter.revision,
            aggregateBefore.revision,
            "Renaming the related Pasture must not rotate AnimalAggregateRevision when the resident still owns the same Pasture UUID.",
            file: file,
            line: line
        )
        assertAnimalDetailPreservedAcrossPastureRename(
            aggregateAfter.animal,
            before: aggregateBefore.animal,
            expectedPastureName: renamedPastureName,
            file: file,
            line: line
        )

        let renamedPastureDetail = try XCTUnwrap(
            freshPastureRepository.fetchPastureDetail(id: targetPasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(renamedPastureDetail.name, renamedPastureName, file: file, line: line)
        XCTAssertEqual(renamedPastureDetail.id, targetPasture.id, file: file, line: line)
        XCTAssertEqual(renamedPastureDetail.acreage, targetPasture.acreage, file: file, line: line)
        XCTAssertEqual(
            renamedPastureDetail.usableAcreage,
            targetPasture.usableAcreage,
            file: file,
            line: line
        )
        XCTAssertEqual(
            renamedPastureDetail.targetAcresPerHead,
            targetPasture.targetAcresPerHead,
            file: file,
            line: line
        )

        let renamedPastureSummary = try XCTUnwrap(
            freshPastureRepository.fetchPastures().first { $0.id == targetPasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(renamedPastureSummary.name, renamedPastureName, file: file, line: line)
        XCTAssertEqual(renamedPastureSummary.activeAnimalCount, 1, file: file, line: line)

        let residents = try freshPastureRepository.fetchResidentAnimals(pastureID: targetPasture.id)
        XCTAssertEqual(residents.count, 1, file: file, line: line)
        XCTAssertEqual(
            try XCTUnwrap(residents.first { $0.id == target.id }, file: file, line: line),
            targetSummaryAfter,
            file: file,
            line: line
        )

        let synchronousPastureOption = try XCTUnwrap(
            freshPastureRepository.fetchPastureOptions().first { $0.id == targetPasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(synchronousPastureOption.name, renamedPastureName, file: file, line: line)

        let listReader = fixture.makeAnimalListQueryReader()
        let page = try await listReader.fetchAnimalSummaryPage(
            ReadPageRequest(offset: 0, limit: ReadPageRequest.maximumLimit)
        )
        XCTAssertFalse(
            page.hasMore,
            "The focused Pasture rename fixture must fit in one maximum-size Animal-list page.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(page.animals.first { $0.id == target.id }, file: file, line: line),
            targetSummaryAfter,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(page.animals.first { $0.id == unrelated.id }, file: file, line: line),
            unrelatedSummaryBefore,
            file: file,
            line: line
        )

        let backgroundPastureOptions = try await listReader.fetchAnimalPastureOptions(
            limit: ReadPageRequest.maximumLimit
        )
        XCTAssertEqual(
            try XCTUnwrap(
                backgroundPastureOptions.first { $0.id == targetPasture.id },
                file: file,
                line: line
            ).name,
            renamedPastureName,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(
                backgroundPastureOptions.first { $0.id == sourcePasture.id },
                file: file,
                line: line
            ).name,
            sourcePasture.name,
            file: file,
            line: line
        )

        let seedAfter = try XCTUnwrap(
            freshAnimalRepository.fetchOffspringDraftSeed(forDamID: target.id),
            file: file,
            line: line
        )
        XCTAssertEqual(seedAfter.damID, seedBefore.damID, file: file, line: line)
        XCTAssertEqual(seedAfter.damDisplayName, seedBefore.damDisplayName, file: file, line: line)
        XCTAssertEqual(seedAfter.pastureID, targetPasture.id, file: file, line: line)
        XCTAssertEqual(seedAfter.pastureName, renamedPastureName, file: file, line: line)
        XCTAssertEqual(seedAfter.inferredSireID, seedBefore.inferredSireID, file: file, line: line)
        XCTAssertEqual(
            seedAfter.inferredSireDisplayName,
            seedBefore.inferredSireDisplayName,
            file: file,
            line: line
        )

        let timelineAfter = try freshAnimalRepository.fetchTimeline(id: target.id)
        let birthAfter = try primaryBirthEvent(
            in: timelineAfter,
            birthDate: targetAfter.birthDate,
            file: file,
            line: line
        )
        XCTAssertEqual(
            birthAfter.details,
            "Pasture: \(renamedPastureName)",
            "The primary Birth projection must derive its Pasture label from the current live relationship.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            multisetCounts(
                timelineSignaturesExcludingPrimaryBirth(
                    timelineAfter,
                    birthDate: targetAfter.birthDate
                )
            ),
            multisetCounts(durableTimelineBefore),
            "Renaming a live Pasture must not rewrite any persisted movement or other durable Animal history.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            timelineSignaturesExcludingPrimaryBirth(
                timelineAfter,
                birthDate: targetAfter.birthDate
            ).contains {
                $0.kind == .movement
                    && $0.title == "Pasture Movement"
                    && $0.details == "\(sourcePasture.name) → \(originalPastureName)"
            },
            "Movement history must retain the destination Pasture name captured before the live rename.",
            file: file,
            line: line
        )

        let dashboardAfter = try await fixture.makeDashboardQueryReader().fetchDashboardRecords()
        let targetDashboardAfter = try XCTUnwrap(
            dashboardAfter.animals.first { $0.id == target.id },
            file: file,
            line: line
        )
        assertDashboardAnimalPreservedAcrossPastureRename(
            targetDashboardAfter,
            before: targetDashboardBefore,
            expectedPastureName: renamedPastureName,
            file: file,
            line: line
        )

        let targetDashboardPastureAfter = try XCTUnwrap(
            dashboardAfter.pastures.first { $0.id == targetPasture.id },
            file: file,
            line: line
        )
        assertDashboardPasturePreservedAcrossRename(
            targetDashboardPastureAfter,
            before: targetDashboardPastureBefore,
            expectedName: renamedPastureName,
            file: file,
            line: line
        )

        let activeDashboard = try await fixture.makeDashboardQueryReader()
            .fetchDashboardAnimalRecords(kind: .active)
        XCTAssertEqual(
            try XCTUnwrap(activeDashboard.first { $0.id == target.id }, file: file, line: line),
            targetDashboardAfter,
            file: file,
            line: line
        )

        let dashboardPastures = try await fixture.makeDashboardQueryReader()
            .fetchDashboardPastureRecords()
        XCTAssertEqual(
            try XCTUnwrap(
                dashboardPastures.first { $0.id == targetPasture.id },
                file: file,
                line: line
            ),
            targetDashboardPastureAfter,
            file: file,
            line: line
        )

        let unrelatedAfter = try XCTUnwrap(
            freshAnimalRepository.fetchAnimalDetail(id: unrelated.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            unrelatedAfter,
            unrelatedBefore,
            "Renaming another Pasture must not mutate the unrelated Animal.",
            file: file,
            line: line
        )
        let unrelatedSummaryAfter = try XCTUnwrap(
            freshAnimalRepository.fetchAnimals().first { $0.id == unrelated.id },
            file: file,
            line: line
        )
        XCTAssertEqual(unrelatedSummaryAfter, unrelatedSummaryBefore, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(timelineSignatures(try freshAnimalRepository.fetchTimeline(id: unrelated.id))),
            multisetCounts(unrelatedTimelineBefore),
            file: file,
            line: line
        )

        let sourcePastureAfter = try XCTUnwrap(
            freshPastureRepository.fetchPastureDetail(id: sourcePasture.id),
            file: file,
            line: line
        )
        XCTAssertEqual(sourcePastureAfter, sourcePastureBefore, file: file, line: line)

        let unrelatedDashboardAfter = try XCTUnwrap(
            dashboardAfter.animals.first { $0.id == unrelated.id },
            file: file,
            line: line
        )
        XCTAssertEqual(unrelatedDashboardAfter, unrelatedDashboardBefore, file: file, line: line)
        let sourceDashboardPastureAfter = try XCTUnwrap(
            dashboardAfter.pastures.first { $0.id == sourcePasture.id },
            file: file,
            line: line
        )
        XCTAssertEqual(sourceDashboardPastureAfter, sourceDashboardPastureBefore, file: file, line: line)
    }

    /// Permanent integration coverage for the shared active-in-herd predicate consumed by
    /// Animal list, Pasture stocking, Dashboard, and Home read models.
    static func assertActiveHerdLifecyclePropagatesToPastureAndDashboard(
        using fixture: AnimalActiveHerdReadProjectionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let animalFixture = fixture.animalFixture
        let animalRepository = animalFixture.makeAnimalRepository()
        let pastureRepository = animalFixture.makePastureRepository()
        let pasture = try pastureRepository.create(
            input: PastureInput(
                name: "Active Herd Projection Pasture",
                acreage: 24,
                usableAcreage: 22,
                targetAcresPerHead: 1.5
            )
        )
        let target = try animalRepository.create(
            input: readModelAnimalInput(
                name: "Active Herd Projection Target",
                tagNumber: "AHP01",
                sex: .female,
                birthDate: contractDate(year: 2019, month: 2, day: 3),
                pastureID: pasture.id
            )
        )
        let control = try animalRepository.create(
            input: readModelAnimalInput(
                name: "Active Herd Projection Control",
                tagNumber: "AHP02",
                sex: .female,
                birthDate: contractDate(year: 2018, month: 3, day: 4),
                pastureID: pasture.id
            )
        )

        let targetBefore = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: target.id),
            file: file,
            line: line
        )
        let controlBefore = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: control.id),
            file: file,
            line: line
        )

        try await assertActiveHerdProjectionState(
            targetID: target.id,
            controlID: control.id,
            pastureID: pasture.id,
            expectedTargetStatus: .active,
            expectedTargetArchived: false,
            expectedTargetIsActiveInHerd: true,
            expectedActiveCount: 2,
            immediateAnimalRepository: animalRepository,
            immediatePastureRepository: pastureRepository,
            fixture: fixture,
            file: file,
            line: line
        )

        try animalRepository.archive(ids: [target.id])
        try await assertActiveHerdProjectionState(
            targetID: target.id,
            controlID: control.id,
            pastureID: pasture.id,
            expectedTargetStatus: .active,
            expectedTargetArchived: true,
            expectedTargetIsActiveInHerd: false,
            expectedActiveCount: 1,
            immediateAnimalRepository: animalRepository,
            immediatePastureRepository: pastureRepository,
            fixture: fixture,
            file: file,
            line: line
        )

        try animalRepository.restore(ids: [target.id])
        try await assertActiveHerdProjectionState(
            targetID: target.id,
            controlID: control.id,
            pastureID: pasture.id,
            expectedTargetStatus: .active,
            expectedTargetArchived: false,
            expectedTargetIsActiveInHerd: true,
            expectedActiveCount: 2,
            immediateAnimalRepository: animalRepository,
            immediatePastureRepository: pastureRepository,
            fixture: fixture,
            file: file,
            line: line
        )

        var targetDetail = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: target.id),
            file: file,
            line: line
        )
        _ = try animalRepository.update(
            id: target.id,
            input: sireInferenceMutationInput(
                from: targetDetail,
                sex: targetDetail.sex,
                birthDate: targetDetail.birthDate,
                status: .sold,
                saleDate: contractDate(year: 2026, month: 9, day: 2)
            )
        )
        try await assertActiveHerdProjectionState(
            targetID: target.id,
            controlID: control.id,
            pastureID: pasture.id,
            expectedTargetStatus: .sold,
            expectedTargetArchived: false,
            expectedTargetIsActiveInHerd: false,
            expectedActiveCount: 1,
            immediateAnimalRepository: animalRepository,
            immediatePastureRepository: pastureRepository,
            fixture: fixture,
            file: file,
            line: line
        )

        targetDetail = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: target.id),
            file: file,
            line: line
        )
        _ = try animalRepository.update(
            id: target.id,
            input: sireInferenceMutationInput(
                from: targetDetail,
                sex: targetDetail.sex,
                birthDate: targetDetail.birthDate,
                status: .active
            )
        )
        try await assertActiveHerdProjectionState(
            targetID: target.id,
            controlID: control.id,
            pastureID: pasture.id,
            expectedTargetStatus: .active,
            expectedTargetArchived: false,
            expectedTargetIsActiveInHerd: true,
            expectedActiveCount: 2,
            immediateAnimalRepository: animalRepository,
            immediatePastureRepository: pastureRepository,
            fixture: fixture,
            file: file,
            line: line
        )

        let targetAfter = try XCTUnwrap(
            animalFixture.makeAnimalRepository().fetchAnimalDetail(id: target.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            targetAfter,
            targetBefore,
            "Returning through archive/restore and sold/active must restore the target's Domain-visible non-history state.",
            file: file,
            line: line
        )
        let controlAfter = try XCTUnwrap(
            animalFixture.makeAnimalRepository().fetchAnimalDetail(id: control.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlAfter,
            controlBefore,
            "Active-in-herd lifecycle changes for the target must not mutate the unaffected resident control.",
            file: file,
            line: line
        )
    }

    private static func assertActiveHerdProjectionState(
        targetID: UUID,
        controlID: UUID,
        pastureID: UUID,
        expectedTargetStatus: AnimalStatus,
        expectedTargetArchived: Bool,
        expectedTargetIsActiveInHerd: Bool,
        expectedActiveCount: Int,
        immediateAnimalRepository: any AnimalRepository,
        immediatePastureRepository: any PastureRepository,
        fixture: AnimalActiveHerdReadProjectionContractFixture,
        file: StaticString,
        line: UInt
    ) async throws {
        let targetDetail = try XCTUnwrap(
            immediateAnimalRepository.fetchAnimalDetail(id: targetID),
            file: file,
            line: line
        )
        XCTAssertEqual(targetDetail.status, expectedTargetStatus, file: file, line: line)
        XCTAssertEqual(targetDetail.isArchived, expectedTargetArchived, file: file, line: line)
        XCTAssertEqual(targetDetail.pastureID, pastureID, file: file, line: line)

        let summaries = try immediateAnimalRepository.fetchAnimals()
        let targetSummary = try XCTUnwrap(
            summaries.first { $0.id == targetID },
            file: file,
            line: line
        )
        let controlSummary = try XCTUnwrap(
            summaries.first { $0.id == controlID },
            file: file,
            line: line
        )
        XCTAssertEqual(targetSummary.status, expectedTargetStatus, file: file, line: line)
        XCTAssertEqual(targetSummary.isArchived, expectedTargetArchived, file: file, line: line)
        XCTAssertEqual(targetSummary.pastureID, pastureID, file: file, line: line)
        XCTAssertEqual(controlSummary.status, .active, file: file, line: line)
        XCTAssertFalse(controlSummary.isArchived, file: file, line: line)
        XCTAssertEqual(controlSummary.pastureID, pastureID, file: file, line: line)

        let page = try await fixture.makeAnimalListQueryReader().fetchAnimalSummaryPage(
            ReadPageRequest(offset: 0, limit: ReadPageRequest.maximumLimit)
        )
        XCTAssertFalse(
            page.hasMore,
            "The focused active-in-herd fixture must fit in one maximum-size Animal-list page.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(page.animals.first { $0.id == targetID }, file: file, line: line),
            targetSummary,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(page.animals.first { $0.id == controlID }, file: file, line: line),
            controlSummary,
            file: file,
            line: line
        )

        let residents = try immediatePastureRepository.fetchResidentAnimals(pastureID: pastureID)
        XCTAssertEqual(residents.count, expectedActiveCount, file: file, line: line)
        XCTAssertEqual(
            residents.contains { $0.id == targetID },
            expectedTargetIsActiveInHerd,
            file: file,
            line: line
        )
        XCTAssertTrue(
            residents.contains { $0.id == controlID },
            "The unaffected active resident must remain in the Pasture resident projection.",
            file: file,
            line: line
        )

        let pastureDetail = try XCTUnwrap(
            immediatePastureRepository.fetchPastureDetail(id: pastureID),
            file: file,
            line: line
        )
        XCTAssertEqual(pastureDetail.activeAnimalCount, expectedActiveCount, file: file, line: line)
        let pastureSummary = try XCTUnwrap(
            immediatePastureRepository.fetchPastures().first { $0.id == pastureID },
            file: file,
            line: line
        )
        XCTAssertEqual(pastureSummary.activeAnimalCount, expectedActiveCount, file: file, line: line)

        let freshAnimalRepository = fixture.animalFixture.makeAnimalRepository()
        let freshTarget = try XCTUnwrap(
            freshAnimalRepository.fetchAnimalDetail(id: targetID),
            file: file,
            line: line
        )
        XCTAssertEqual(freshTarget.status, expectedTargetStatus, file: file, line: line)
        XCTAssertEqual(freshTarget.isArchived, expectedTargetArchived, file: file, line: line)
        XCTAssertEqual(freshTarget.pastureID, pastureID, file: file, line: line)

        let freshPastureRepository = fixture.animalFixture.makePastureRepository()
        let freshResidents = try freshPastureRepository.fetchResidentAnimals(pastureID: pastureID)
        XCTAssertEqual(freshResidents.count, expectedActiveCount, file: file, line: line)
        XCTAssertEqual(
            freshResidents.contains { $0.id == targetID },
            expectedTargetIsActiveInHerd,
            file: file,
            line: line
        )
        XCTAssertTrue(freshResidents.contains { $0.id == controlID }, file: file, line: line)
        XCTAssertEqual(
            try XCTUnwrap(
                freshPastureRepository.fetchPastureDetail(id: pastureID),
                file: file,
                line: line
            ).activeAnimalCount,
            expectedActiveCount,
            file: file,
            line: line
        )

        let dashboardReader = fixture.makeDashboardQueryReader()
        let dashboardRecords = try await dashboardReader.fetchDashboardRecords()
        let targetDashboard = try XCTUnwrap(
            dashboardRecords.animals.first { $0.id == targetID },
            "Full Dashboard/Home records must retain archived and non-active Animals for alerts/history-aware summaries.",
            file: file,
            line: line
        )
        XCTAssertEqual(targetDashboard.status, expectedTargetStatus, file: file, line: line)
        XCTAssertEqual(targetDashboard.isArchived, expectedTargetArchived, file: file, line: line)
        XCTAssertEqual(targetDashboard.pastureID, pastureID, file: file, line: line)

        let controlDashboard = try XCTUnwrap(
            dashboardRecords.animals.first { $0.id == controlID },
            file: file,
            line: line
        )
        XCTAssertEqual(controlDashboard.status, .active, file: file, line: line)
        XCTAssertFalse(controlDashboard.isArchived, file: file, line: line)
        XCTAssertEqual(controlDashboard.pastureID, pastureID, file: file, line: line)

        let dashboardPasture = try XCTUnwrap(
            dashboardRecords.pastures.first { $0.id == pastureID },
            file: file,
            line: line
        )
        XCTAssertEqual(dashboardPasture.activeAnimalCount, expectedActiveCount, file: file, line: line)

        let activeDashboard = try await dashboardReader.fetchDashboardAnimalRecords(kind: .active)
        XCTAssertEqual(
            activeDashboard.contains { $0.id == targetID },
            expectedTargetIsActiveInHerd,
            file: file,
            line: line
        )
        XCTAssertTrue(activeDashboard.contains { $0.id == controlID }, file: file, line: line)

        let dashboardPastures = try await dashboardReader.fetchDashboardPastureRecords()
        let dashboardPastureList = try XCTUnwrap(
            dashboardPastures.first { $0.id == pastureID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            dashboardPastureList.activeAnimalCount,
            expectedActiveCount,
            "Dashboard records and the focused Dashboard Pasture query must use the same active-in-herd count.",
            file: file,
            line: line
        )
    }

    /// Permanent coverage that the Add Offspring seed is recomputed from the current persisted
    /// sire-candidate state rather than retaining a stale inferred sire after repository mutations.
    static func assertOffspringDraftSireInferenceTracksCandidateState(
        using fixture: AnimalRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let homePasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Sire Inference Transition Home",
                acreage: 24,
                usableAcreage: 22,
                targetAcresPerHead: 1.5
            )
        )
        let otherPasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Sire Inference Transition Other",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let adultBullBirthDate = contractDate(year: 2018, month: 2, day: 3)
        let dam = try repository.create(
            input: readModelAnimalInput(
                name: "Sire Inference Transition Dam",
                tagNumber: "SID01",
                sex: .female,
                birthDate: contractDate(year: 2019, month: 3, day: 4),
                pastureID: homePasture.id
            )
        )
        let sire = try repository.create(
            input: readModelAnimalInput(
                name: "Sire Inference Transition Bull",
                tagNumber: "SIS01",
                tagColorID: TagColorDefaults.yellowID,
                sex: .male,
                birthDate: adultBullBirthDate,
                pastureID: homePasture.id
            )
        )
        let otherBull = try repository.create(
            input: readModelAnimalInput(
                name: "Sire Inference Transition Other Bull",
                tagNumber: "SIO01",
                sex: .male,
                birthDate: contractDate(year: 2017, month: 1, day: 2),
                pastureID: otherPasture.id
            )
        )

        let damBefore = try XCTUnwrap(
            repository.fetchAnimalDetail(id: dam.id),
            file: file,
            line: line
        )
        let otherBullBefore = try XCTUnwrap(
            repository.fetchAnimalDetail(id: otherBull.id),
            file: file,
            line: line
        )
        let sireParentDisplay = try XCTUnwrap(
            repository.fetchParentOptions(excluding: nil)
                .first { $0.id == sire.id },
            file: file,
            line: line
        ).displayName

        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: sire.id,
            expectedSireDisplayName: sireParentDisplay,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        try repository.move(ids: [sire.id], toPastureID: otherPasture.id)
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: nil,
            expectedSireDisplayName: nil,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        try repository.move(ids: [sire.id], toPastureID: homePasture.id)
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: sire.id,
            expectedSireDisplayName: sireParentDisplay,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        try repository.archive(ids: [sire.id])
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: nil,
            expectedSireDisplayName: nil,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        try repository.restore(ids: [sire.id])
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: sire.id,
            expectedSireDisplayName: sireParentDisplay,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        var sireDetail = try XCTUnwrap(
            repository.fetchAnimalDetail(id: sire.id),
            file: file,
            line: line
        )
        _ = try repository.update(
            id: sire.id,
            input: sireInferenceMutationInput(
                from: sireDetail,
                sex: .male,
                birthDate: adultBullBirthDate,
                status: .sold,
                saleDate: contractDate(year: 2026, month: 9, day: 1)
            )
        )
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: nil,
            expectedSireDisplayName: nil,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        sireDetail = try XCTUnwrap(repository.fetchAnimalDetail(id: sire.id), file: file, line: line)
        _ = try repository.update(
            id: sire.id,
            input: sireInferenceMutationInput(
                from: sireDetail,
                sex: .male,
                birthDate: adultBullBirthDate,
                status: .active
            )
        )
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: sire.id,
            expectedSireDisplayName: sireParentDisplay,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        sireDetail = try XCTUnwrap(repository.fetchAnimalDetail(id: sire.id), file: file, line: line)
        _ = try repository.update(
            id: sire.id,
            input: sireInferenceMutationInput(
                from: sireDetail,
                sex: .female,
                birthDate: adultBullBirthDate,
                status: .active
            )
        )
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: nil,
            expectedSireDisplayName: nil,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        sireDetail = try XCTUnwrap(repository.fetchAnimalDetail(id: sire.id), file: file, line: line)
        _ = try repository.update(
            id: sire.id,
            input: sireInferenceMutationInput(
                from: sireDetail,
                sex: .male,
                birthDate: adultBullBirthDate,
                status: .active
            )
        )
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: sire.id,
            expectedSireDisplayName: sireParentDisplay,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        let youngBullBirthDate = Calendar.current.date(
            byAdding: .month,
            value: -2,
            to: Date()
        ) ?? Date()
        sireDetail = try XCTUnwrap(repository.fetchAnimalDetail(id: sire.id), file: file, line: line)
        _ = try repository.update(
            id: sire.id,
            input: sireInferenceMutationInput(
                from: sireDetail,
                sex: .male,
                birthDate: youngBullBirthDate,
                status: .active
            )
        )
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: nil,
            expectedSireDisplayName: nil,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        sireDetail = try XCTUnwrap(repository.fetchAnimalDetail(id: sire.id), file: file, line: line)
        _ = try repository.update(
            id: sire.id,
            input: sireInferenceMutationInput(
                from: sireDetail,
                sex: .male,
                birthDate: adultBullBirthDate,
                status: .active
            )
        )
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: sire.id,
            expectedSireDisplayName: sireParentDisplay,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        try repository.move(ids: [otherBull.id], toPastureID: homePasture.id)
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: nil,
            expectedSireDisplayName: nil,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        try repository.move(ids: [otherBull.id], toPastureID: otherPasture.id)
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: sire.id,
            expectedSireDisplayName: sireParentDisplay,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )

        let damAfter = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: dam.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            damAfter,
            damBefore,
            "Sire-candidate transitions must not mutate the dam whose Add Offspring seed is being prepared.",
            file: file,
            line: line
        )
        let otherBullAfter = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: otherBull.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            otherBullAfter,
            otherBullBefore,
            "The ambiguity-control bull must return to its original Domain-visible state after the transition lifecycle.",
            file: file,
            line: line
        )
        let sireAfter = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: sire.id),
            file: file,
            line: line
        )
        XCTAssertEqual(sireAfter.id, sire.id, file: file, line: line)
        XCTAssertEqual(sireAfter.sex, .male, file: file, line: line)
        XCTAssertEqual(sireAfter.birthDate, adultBullBirthDate, file: file, line: line)
        XCTAssertEqual(sireAfter.status, .active, file: file, line: line)
        XCTAssertFalse(sireAfter.isArchived, file: file, line: line)
        XCTAssertEqual(sireAfter.pastureID, homePasture.id, file: file, line: line)
        XCTAssertEqual(sireAfter.animalType, .bull, file: file, line: line)

        let castrationDate = contractDate(year: 2026, month: 9, day: 4)
        let sireAfterCastration = try repository.addHealthRecord(
            animalID: sire.id,
            input: HealthRecordInput(
                date: castrationDate,
                treatment: "Castration",
                notes: "Sire inference health-derived type transition"
            )
        )
        XCTAssertEqual(
            sireAfterCastration.animalType,
            .steer,
            "The persisted health row must change the sire candidate's derived type before inference is re-read.",
            file: file,
            line: line
        )
        try assertOffspringDraftSireInference(
            damID: dam.id,
            expectedSireID: nil,
            expectedSireDisplayName: nil,
            expectedPastureID: homePasture.id,
            expectedPastureName: homePasture.name,
            repository: repository,
            freshRepository: fixture.makeAnimalRepository,
            file: file,
            line: line
        )
    }

    /// Freezes the production async Animal-list paging contract used by `AnimalListViewModel`.
    ///
    /// The list caller advances offsets by the number of returned records while `hasMore` is true,
    /// so page boundaries must be complete, ordered, and non-overlapping. The pasture-filter reader
    /// uses its `limit` as an internal fetch size and must still return the complete option set.
    static func assertAsyncAnimalListPaginationAndPastureOptions(
        using fixture: AnimalListReadProjectionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let animalRepository = fixture.animalFixture.makeAnimalRepository()
        let pastureRepository = fixture.animalFixture.makePastureRepository()
        XCTAssertTrue(
            try animalRepository.fetchAnimals().isEmpty,
            "The pagination contract requires an isolated Animal store.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try pastureRepository.fetchPastureOptions().isEmpty,
            "The pagination contract requires an isolated Pasture store.",
            file: file,
            line: line
        )

        // Construct this reader before the writes so the same long-lived production reader must
        // observe subsequently committed state rather than retaining a construction-time snapshot.
        let immediateReader = fixture.makeAnimalListQueryReader()

        let tiedLowerID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000010"),
            file: file,
            line: line
        )
        let tiedHigherID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000020"),
            file: file,
            line: line
        )
        XCTAssertLessThan(
            tiedLowerID.uuidString,
            tiedHigherID.uuidString,
            "The deterministic tied-key fixture must establish the expected UUID tie-break order.",
            file: file,
            line: line
        )

        let alpha = try animalRepository.create(
            input: readModelAnimalInput(
                name: "Paging Alpha",
                tagNumber: "",
                sex: .female,
                birthDate: contractDate(year: 2020, month: 1, day: 1)
            )
        )
        let tiedInput = readModelAnimalInput(
            name: "Paging Boundary Tie",
            tagNumber: "",
            sex: .female,
            birthDate: contractDate(year: 2020, month: 1, day: 2)
        )

        // Seed the larger UUID first. A reader that sorts only by tag/name and falls back to
        // insertion order must therefore fail the contract when the tied pair crosses the page
        // boundary; the final application-UUID sort key must put tiedLowerID first.
        let tiedHigher = try fixture.seedAnimalWithID(tiedHigherID, tiedInput)
        XCTAssertEqual(tiedHigher.id, tiedHigherID, file: file, line: line)

        let pageFive = try animalRepository.create(
            input: readModelAnimalInput(
                name: "Paging Five",
                tagNumber: "PAGE05",
                sex: .female,
                birthDate: contractDate(year: 2020, month: 1, day: 5)
            )
        )
        let pageFour = try animalRepository.create(
            input: readModelAnimalInput(
                name: "Paging Four",
                tagNumber: "PAGE04",
                sex: .female,
                birthDate: contractDate(year: 2020, month: 1, day: 4)
            )
        )

        let tiedLower = try fixture.seedAnimalWithID(tiedLowerID, tiedInput)
        XCTAssertEqual(tiedLower.id, tiedLowerID, file: file, line: line)

        let pastureZulu = try pastureRepository.create(
            input: PastureInput(
                name: "Paging Zulu Pasture",
                acreage: 11,
                usableAcreage: 10,
                targetAcresPerHead: 1.0
            )
        )
        let pastureAlpha = try pastureRepository.create(
            input: PastureInput(
                name: "Paging Alpha Pasture",
                acreage: 13,
                usableAcreage: 12,
                targetAcresPerHead: 1.1
            )
        )
        let pastureMike = try pastureRepository.create(
            input: PastureInput(
                name: "Paging Mike Pasture",
                acreage: 15,
                usableAcreage: 14,
                targetAcresPerHead: 1.2
            )
        )

        let summaryRepository = fixture.animalFixture.makeAnimalRepository()
        var summariesByID: [UUID: AnimalSummary] = [:]
        for summary in try summaryRepository.fetchAnimals() {
            summariesByID[summary.id] = summary
        }

        let tiedLowerSummary = try XCTUnwrap(
            summariesByID[tiedLowerID],
            "The lower UUID member of the boundary tie must be visible through the authoritative summary reader.",
            file: file,
            line: line
        )
        let tiedHigherSummary = try XCTUnwrap(
            summariesByID[tiedHigherID],
            "The higher UUID member of the boundary tie must be visible through the authoritative summary reader.",
            file: file,
            line: line
        )
        XCTAssertEqual(tiedLowerSummary.displayTagNumber, tiedHigherSummary.displayTagNumber, file: file, line: line)
        XCTAssertEqual(tiedLowerSummary.name, tiedHigherSummary.name, file: file, line: line)

        let expectedAnimalIDs = [
            alpha.id,
            tiedLowerID,
            tiedHigherID,
            pageFour.id,
            pageFive.id
        ]
        let expectedAnimals = try expectedAnimalIDs.map { id in
            try XCTUnwrap(
                summariesByID[id],
                "Every seeded Animal must be visible through the authoritative summary reader.",
                file: file,
                line: line
            )
        }

        let immediatePages = try await fetchAnimalListContractPages(
            reader: immediateReader,
            pageSize: 2,
            file: file,
            line: line
        )
        try assertAnimalListContractPages(
            immediatePages,
            expectedAnimals: expectedAnimals,
            tiedBoundaryIDs: (lower: tiedLowerID, higher: tiedHigherID),
            file: file,
            line: line
        )

        let expectedPastureOptions = [
            PastureOption(id: pastureAlpha.id, name: pastureAlpha.name),
            PastureOption(id: pastureMike.id, name: pastureMike.name),
            PastureOption(id: pastureZulu.id, name: pastureZulu.name)
        ]
        XCTAssertEqual(
            try pastureRepository.fetchPastureOptions(),
            expectedPastureOptions,
            "The synchronous reference projection establishes the committed Pasture option set.",
            file: file,
            line: line
        )
        let immediatePastureOptions = try await immediateReader.fetchAnimalPastureOptions(limit: 2)
        XCTAssertEqual(
            immediatePastureOptions,
            expectedPastureOptions,
            "The async Pasture option reader must traverse beyond its internal fetch size instead of treating limit as a total-result cap.",
            file: file,
            line: line
        )

        let freshReader = fixture.makeAnimalListQueryReader()
        let freshPages = try await fetchAnimalListContractPages(
            reader: freshReader,
            pageSize: 2,
            file: file,
            line: line
        )
        try assertAnimalListContractPages(
            freshPages,
            expectedAnimals: expectedAnimals,
            tiedBoundaryIDs: (lower: tiedLowerID, higher: tiedHigherID),
            file: file,
            line: line
        )
        let freshPastureOptions = try await freshReader.fetchAnimalPastureOptions(limit: 2)
        XCTAssertEqual(
            freshPastureOptions,
            expectedPastureOptions,
            "A fresh read-model scope must reproduce the complete committed Pasture option projection.",
            file: file,
            line: line
        )
    }

    private static func fetchAnimalListContractPages(
        reader: any AnimalListQueryReading,
        pageSize: Int,
        file: StaticString,
        line: UInt
    ) async throws -> [AnimalSummaryPage] {
        var pages: [AnimalSummaryPage] = []
        var offset = 0

        while pages.count < 10 {
            let page = try await reader.fetchAnimalSummaryPage(
                ReadPageRequest(offset: offset, limit: pageSize)
            )
            pages.append(page)

            guard page.hasMore else { return pages }
            guard !page.animals.isEmpty else {
                XCTFail(
                    "An Animal page cannot advertise more records while returning an empty page; the production caller would terminate with a truncated list.",
                    file: file,
                    line: line
                )
                return pages
            }
            offset += page.animals.count
        }

        XCTFail(
            "Animal pagination did not converge within the focused five-record fixture.",
            file: file,
            line: line
        )
        return pages
    }

    private static func assertAnimalListContractPages(
        _ pages: [AnimalSummaryPage],
        expectedAnimals: [AnimalSummary],
        tiedBoundaryIDs: (lower: UUID, higher: UUID),
        file: StaticString,
        line: UInt
    ) throws {
        XCTAssertEqual(
            pages.count,
            3,
            "Five records at page size two must produce exactly two full pages and one final partial page.",
            file: file,
            line: line
        )

        let firstPage = try XCTUnwrap(pages.first, file: file, line: line)
        let secondPage = try XCTUnwrap(pages.dropFirst().first, file: file, line: line)
        let thirdPage = try XCTUnwrap(pages.dropFirst(2).first, file: file, line: line)

        XCTAssertEqual(firstPage.animals, Array(expectedAnimals.prefix(2)), file: file, line: line)
        XCTAssertEqual(
            firstPage.animals.last?.id,
            tiedBoundaryIDs.lower,
            "The lower UUID member of the identical tag/name pair must end the first page.",
            file: file,
            line: line
        )
        XCTAssertTrue(firstPage.hasMore, file: file, line: line)
        XCTAssertEqual(
            secondPage.animals,
            Array(expectedAnimals.dropFirst(2).prefix(2)),
            file: file,
            line: line
        )
        XCTAssertEqual(
            secondPage.animals.first?.id,
            tiedBoundaryIDs.higher,
            "The higher UUID member of the identical tag/name pair must begin the second page.",
            file: file,
            line: line
        )
        XCTAssertTrue(secondPage.hasMore, file: file, line: line)
        XCTAssertEqual(
            thirdPage.animals,
            Array(expectedAnimals.dropFirst(4)),
            file: file,
            line: line
        )
        XCTAssertFalse(thirdPage.hasMore, file: file, line: line)

        let assembled = pages.flatMap { $0.animals }
        XCTAssertEqual(
            assembled,
            expectedAnimals,
            "Production-style page concatenation must preserve complete deterministic ordering.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(assembled.map(\.id)).count,
            expectedAnimals.count,
            "No Animal application UUID may be duplicated across page boundaries.",
            file: file,
            line: line
        )
    }

    private static func assertOffspringDraftSireInference(
        damID: UUID,
        expectedSireID: UUID?,
        expectedSireDisplayName: String?,
        expectedPastureID: UUID?,
        expectedPastureName: String?,
        repository: any AnimalRepository,
        freshRepository: () -> any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let immediate = try XCTUnwrap(
            repository.fetchOffspringDraftSeed(forDamID: damID),
            file: file,
            line: line
        )
        XCTAssertEqual(immediate.damID, damID, file: file, line: line)
        XCTAssertEqual(immediate.pastureID, expectedPastureID, file: file, line: line)
        XCTAssertEqual(immediate.pastureName, expectedPastureName, file: file, line: line)
        XCTAssertEqual(immediate.inferredSireID, expectedSireID, file: file, line: line)
        XCTAssertEqual(immediate.inferredSireDisplayName, expectedSireDisplayName, file: file, line: line)

        let reloaded = try XCTUnwrap(
            freshRepository().fetchOffspringDraftSeed(forDamID: damID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.damID, immediate.damID, file: file, line: line)
        XCTAssertEqual(reloaded.damDisplayName, immediate.damDisplayName, file: file, line: line)
        XCTAssertEqual(reloaded.pastureID, immediate.pastureID, file: file, line: line)
        XCTAssertEqual(reloaded.pastureName, immediate.pastureName, file: file, line: line)
        XCTAssertEqual(reloaded.inferredSireID, immediate.inferredSireID, file: file, line: line)
        XCTAssertEqual(
            reloaded.inferredSireDisplayName,
            immediate.inferredSireDisplayName,
            "Fresh repository construction must not retain a stale sire inference after candidate-state mutation.",
            file: file,
            line: line
        )
    }

    private static func assertAnimalDetailPreservedAcrossPastureRename(
        _ actual: AnimalDetailSnapshot,
        before: AnimalDetailSnapshot,
        expectedPastureName: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.name, before.name, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, before.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(actual.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(actual.status, before.status, file: file, line: line)
        XCTAssertEqual(actual.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expectedPastureName, file: file, line: line)
        XCTAssertEqual(actual.sireID, before.sireID, file: file, line: line)
        XCTAssertEqual(actual.sire, before.sire, file: file, line: line)
        XCTAssertEqual(actual.damID, before.damID, file: file, line: line)
        XCTAssertEqual(actual.dam, before.dam, file: file, line: line)
        XCTAssertEqual(actual.distinguishingFeatures, before.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(actual.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(actual.salePrice, before.salePrice, file: file, line: line)
        XCTAssertEqual(actual.reasonSold, before.reasonSold, file: file, line: line)
        XCTAssertEqual(actual.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(actual.causeOfDeath, before.causeOfDeath, file: file, line: line)
        XCTAssertEqual(actual.statusReferenceID, before.statusReferenceID, file: file, line: line)
        XCTAssertEqual(actual.statusReferenceName, before.statusReferenceName, file: file, line: line)
        XCTAssertEqual(actual.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(actual.archivedAt, before.archivedAt, file: file, line: line)
        XCTAssertEqual(actual.archiveReason, before.archiveReason, file: file, line: line)
        XCTAssertEqual(actual.activeTags, before.activeTags, file: file, line: line)
        XCTAssertEqual(actual.inactiveTags, before.inactiveTags, file: file, line: line)
        XCTAssertEqual(actual.location, before.location, file: file, line: line)
        XCTAssertEqual(
            actual.maternalOffspringCountIncludingArchived,
            before.maternalOffspringCountIncludingArchived,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.maternalOffspring, before.maternalOffspring, file: file, line: line)
    }

    private static func fetchDashboardAnimalRecord(
        id: UUID,
        reader: any DashboardQueryReading,
        file: StaticString,
        line: UInt
    ) async throws -> DashboardAnimalRecord {
        let records = try await reader.fetchDashboardRecords()
        return try XCTUnwrap(
            records.animals.first { $0.id == id },
            file: file,
            line: line
        )
    }

    private static func assertAnimalDetailPreservedAcrossDerivedTypeChange(
        _ actual: AnimalDetailSnapshot,
        before: AnimalDetailSnapshot,
        expectedAnimalType: AnimalType,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.name, before.name, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, before.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, expectedAnimalType, file: file, line: line)
        XCTAssertEqual(actual.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(actual.status, before.status, file: file, line: line)
        XCTAssertEqual(actual.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, before.pastureName, file: file, line: line)
        XCTAssertEqual(actual.sireID, before.sireID, file: file, line: line)
        XCTAssertEqual(actual.sire, before.sire, file: file, line: line)
        XCTAssertEqual(actual.damID, before.damID, file: file, line: line)
        XCTAssertEqual(actual.dam, before.dam, file: file, line: line)
        XCTAssertEqual(actual.distinguishingFeatures, before.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(actual.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(actual.salePrice, before.salePrice, file: file, line: line)
        XCTAssertEqual(actual.reasonSold, before.reasonSold, file: file, line: line)
        XCTAssertEqual(actual.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(actual.causeOfDeath, before.causeOfDeath, file: file, line: line)
        XCTAssertEqual(actual.statusReferenceID, before.statusReferenceID, file: file, line: line)
        XCTAssertEqual(actual.statusReferenceName, before.statusReferenceName, file: file, line: line)
        XCTAssertEqual(actual.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(actual.archivedAt, before.archivedAt, file: file, line: line)
        XCTAssertEqual(actual.archiveReason, before.archiveReason, file: file, line: line)
        XCTAssertEqual(actual.activeTags, before.activeTags, file: file, line: line)
        XCTAssertEqual(actual.inactiveTags, before.inactiveTags, file: file, line: line)
        XCTAssertEqual(actual.location, before.location, file: file, line: line)
        XCTAssertEqual(
            actual.maternalOffspringCountIncludingArchived,
            before.maternalOffspringCountIncludingArchived,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.maternalOffspring, before.maternalOffspring, file: file, line: line)
    }

    private static func assertAnimalSummaryPreservedAcrossPastureRename(
        _ actual: AnimalSummary,
        before: AnimalSummary,
        expectedPastureName: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.name, before.name, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagNumber, before.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagColorID, before.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, before.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(actual.firstDistinguishingFeature, before.firstDistinguishingFeature, file: file, line: line)
        XCTAssertEqual(actual.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(actual.status, before.status, file: file, line: line)
        XCTAssertEqual(actual.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(actual.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expectedPastureName, file: file, line: line)
        XCTAssertEqual(actual.location, before.location, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyCheckDate, before.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyStatus, before.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(actual.expectedCalvingDate, before.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(actual.lastTreatmentDate, before.lastTreatmentDate, file: file, line: line)
    }

    private static func assertDashboardAnimalPreservedAcrossPastureRename(
        _ actual: DashboardAnimalRecord,
        before: DashboardAnimalRecord,
        expectedPastureName: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.damID, before.damID, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagNumber, before.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagColorID, before.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, before.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(actual.status, before.status, file: file, line: line)
        XCTAssertEqual(actual.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(actual.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expectedPastureName, file: file, line: line)
        XCTAssertEqual(actual.location, before.location, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyCheckDate, before.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyStatus, before.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(actual.expectedCalvingDate, before.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(actual.lastTreatmentDate, before.lastTreatmentDate, file: file, line: line)
        XCTAssertEqual(actual.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(actual.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(actual.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(actual.healthRecords),
            multisetCounts(before.healthRecords),
            file: file,
            line: line
        )
        XCTAssertEqual(actual.offspringCount, before.offspringCount, file: file, line: line)
    }

    private static func assertDashboardPasturePreservedAcrossRename(
        _ actual: DashboardPastureRecord,
        before: DashboardPastureRecord,
        expectedName: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.name, expectedName, file: file, line: line)
        XCTAssertEqual(actual.acreage, before.acreage, file: file, line: line)
        XCTAssertEqual(actual.usableAcreage, before.usableAcreage, file: file, line: line)
        XCTAssertEqual(actual.targetAcresPerHead, before.targetAcresPerHead, file: file, line: line)
        XCTAssertEqual(actual.activeAnimalCount, before.activeAnimalCount, file: file, line: line)
        XCTAssertEqual(actual.lastGrazedDate, before.lastGrazedDate, file: file, line: line)
        XCTAssertEqual(actual.restDays, before.restDays, file: file, line: line)
    }

    private static func primaryBirthEvent(
        in timeline: [AnimalTimelineEvent],
        birthDate: Date,
        file: StaticString,
        line: UInt
    ) throws -> AnimalTimelineEvent {
        let primaryBirths = timeline.filter { event in
            guard case .birth = event.type else { return false }
            return event.title == "Birth" && event.date == birthDate
        }
        XCTAssertEqual(primaryBirths.count, 1, file: file, line: line)
        return try XCTUnwrap(primaryBirths.first, file: file, line: line)
    }

    private static func timelineSignaturesExcludingPrimaryBirth(
        _ timeline: [AnimalTimelineEvent],
        birthDate: Date
    ) -> [AnimalReadModelTimelineSignature] {
        timeline.compactMap { event in
            if case .birth = event.type,
               event.title == "Birth",
               event.date == birthDate {
                return nil
            }
            return timelineSignature(event)
        }
    }

    private static func timelineSignatures(
        _ timeline: [AnimalTimelineEvent]
    ) -> [AnimalReadModelTimelineSignature] {
        timeline.map(timelineSignature)
    }

    private static func timelineSignature(
        _ event: AnimalTimelineEvent
    ) -> AnimalReadModelTimelineSignature {
        AnimalReadModelTimelineSignature(
            kind: timelineKind(event.type),
            date: event.date,
            title: event.title,
            details: event.details
        )
    }

    private static func timelineKind(
        _ type: AnimalTimelineEventType
    ) -> AnimalReadModelTimelineKind {
        switch type {
        case .birth: return .birth
        case .health: return .health
        case .pregnancy: return .pregnancy
        case .movement: return .movement
        case .status: return .status
        case .tag: return .tag
        }
    }

    private static func multisetCounts<T: Hashable>(_ values: [T]) -> [T: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private static func sireInferenceMutationInput(
        from detail: AnimalDetailSnapshot,
        sex: Sex,
        birthDate: Date,
        status: AnimalStatus,
        saleDate: Date? = nil
    ) -> AnimalInput {
        AnimalInput(
            name: detail.name,
            tagNumber: detail.displayTagNumber,
            tagColorID: detail.displayTagColorID,
            sex: sex,
            birthDate: birthDate,
            status: status,
            pastureID: detail.pastureID,
            sireID: detail.sireID,
            damID: detail.damID,
            distinguishingFeatures: detail.distinguishingFeatures,
            saleDate: saleDate,
            salePrice: status == .sold ? detail.salePrice : nil,
            reasonSold: status == .sold ? detail.reasonSold : nil,
            deathDate: nil,
            causeOfDeath: nil,
            statusReferenceID: detail.statusReferenceID
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
