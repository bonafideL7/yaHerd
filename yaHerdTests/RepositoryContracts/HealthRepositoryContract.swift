import XCTest
@testable import yaHerd

/// Persistence-neutral snapshot used only by the permanent health contract to verify durable child-record
/// identity and fields that are not currently exposed by the public Animal read models.
struct HealthRecordContractSnapshot: Equatable {
    let id: UUID
    let animalID: UUID
    let date: Date
    let treatment: String
    let notes: String?
    let workingSessionID: UUID?
}

/// Persistence-neutral snapshot used only by the permanent health contract to verify durable pregnancy-check
/// identity, optional payload, and relationships that are not currently exposed by the public Animal read models.
struct PregnancyCheckContractSnapshot: Equatable {
    let id: UUID
    let animalID: UUID
    let date: Date
    let resultRawValue: String
    let technician: String?
    let estimatedDaysPregnant: Int?
    let dueDate: Date?
    let sireAnimalID: UUID?
    let workingSessionID: UUID?
}

/// Target-runner test control for facts that cannot be asserted through the current Domain read models.
///
/// This is not a production repository contract and must not expose SwiftData/Core Data model objects or contexts.
/// The future Core Data runner should map persisted health rows into these persistence-neutral snapshots.
@MainActor
protocol HealthRepositoryContractTestControl {
    func healthRecords(forAnimalID animalID: UUID) throws -> [HealthRecordContractSnapshot]
    func pregnancyChecks(forAnimalID animalID: UUID) throws -> [PregnancyCheckContractSnapshot]
    func allHealthRecords() throws -> [HealthRecordContractSnapshot]
    func allPregnancyChecks() throws -> [PregnancyCheckContractSnapshot]
}

/// Permanent persistence-neutral fixture for standalone Animal health and pregnancy behavior.
///
/// yaHerd does not currently have a separate `HealthRepository`; direct health and pregnancy mutations are owned by
/// `AnimalRepository`. The historical Milestone 0 `HealthRepositoryContractTests` plan item is therefore expressed
/// against the existing Animal Domain contracts rather than inventing a new repository solely for persistence work.
@MainActor
struct HealthRepositoryContractFixture {
    let makeAnimalRepository: () -> any AnimalRepository
    let makeTestControl: () -> any HealthRepositoryContractTestControl
}

/// Permanent persistence-neutral behavioral contract for standalone animal health history.
///
/// Ownership boundaries:
/// - This contract owns direct Animal health-record and pregnancy-check child identity, complete persisted payload,
///   sire-nullification behavior, orphan prevention, and animal hard-delete cascading.
/// - `AnimalRepositoryContract` owns Animal projections/timeline ordering, archive/restore preservation, and summary
///   calculations such as latest treatment/pregnancy and expected-calving-date behavior.
/// - `WorkingRepositoryContract` owns health/pregnancy rows generated from Working, their session linkage, editing,
///   cleanup, and transaction rollback semantics.
/// - Generic mutation publication and broad duplicate-identity enforcement remain separate Milestone 0 slices.
@MainActor
enum HealthRepositoryContract {
    static func assertStandaloneHealthRecordsPreserveIdentityPayloadAndOwnership(
        using fixture: HealthRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let animal = try repository.create(
            input: makeAnimalInput(
                name: "Health Contract Cow",
                tagNumber: "H101",
                sex: .female,
                birthDate: date(year: 2020, month: 1, day: 10)
            )
        )
        let controlAnimal = try repository.create(
            input: makeAnimalInput(
                name: "Health Contract Control",
                tagNumber: "H102",
                sex: .female,
                birthDate: date(year: 2020, month: 1, day: 11)
            )
        )

        let firstDate = date(year: 2026, month: 6, day: 10)
        let firstTreatment = "Pinkeye treatment"
        let firstNotes = "Left eye"
        let firstResult = try repository.addHealthRecord(
            animalID: animal.id,
            input: HealthRecordInput(
                date: firstDate,
                treatment: firstTreatment,
                notes: firstNotes
            )
        )
        XCTAssertEqual(firstResult.id, animal.id, file: file, line: line)

        let firstReload = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(firstReload.id, animal.id, file: file, line: line)

        let firstPersistedRecords = try fixture.makeTestControl().healthRecords(forAnimalID: animal.id)
        XCTAssertEqual(firstPersistedRecords.count, 1, file: file, line: line)
        let firstPersisted = try XCTUnwrap(firstPersistedRecords.first, file: file, line: line)
        XCTAssertEqual(firstPersisted.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(firstPersisted.date, firstDate, file: file, line: line)
        XCTAssertEqual(firstPersisted.treatment, firstTreatment, file: file, line: line)
        XCTAssertEqual(firstPersisted.notes, firstNotes, file: file, line: line)
        XCTAssertNil(
            firstPersisted.workingSessionID,
            "A health record added directly from Animal must not acquire a Working-session relationship.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try fixture.makeTestControl().healthRecords(forAnimalID: controlAnimal.id).isEmpty,
            "Adding health history to one animal must not create history for an unrelated animal.",
            file: file,
            line: line
        )

        let secondDate = date(year: 2026, month: 5, day: 20)
        let secondTreatment = "Backdated vaccination"
        _ = try fixture.makeAnimalRepository().addHealthRecord(
            animalID: animal.id,
            input: HealthRecordInput(
                date: secondDate,
                treatment: secondTreatment,
                notes: nil
            )
        )

        let reloadedRecords = try fixture.makeTestControl().healthRecords(forAnimalID: animal.id)
        XCTAssertEqual(reloadedRecords.count, 2, file: file, line: line)
        XCTAssertEqual(
            Set(reloadedRecords.map(\.id)).count,
            2,
            "Each durable health record must have its own application UUID.",
            file: file,
            line: line
        )
        let reloadedFirst = try XCTUnwrap(
            reloadedRecords.first { $0.id == firstPersisted.id },
            "Adding another record must preserve the original health-record UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedFirst.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(reloadedFirst.date, firstDate, file: file, line: line)
        XCTAssertEqual(reloadedFirst.treatment, firstTreatment, file: file, line: line)
        XCTAssertEqual(reloadedFirst.notes, firstNotes, file: file, line: line)
        XCTAssertNil(reloadedFirst.workingSessionID, file: file, line: line)

        let reloadedSecond = try XCTUnwrap(
            reloadedRecords.first { $0.id != firstPersisted.id },
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedSecond.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(reloadedSecond.date, secondDate, file: file, line: line)
        XCTAssertEqual(reloadedSecond.treatment, secondTreatment, file: file, line: line)
        XCTAssertNil(
            reloadedSecond.notes,
            "A nil health-record note must remain nil after persistence rather than becoming an empty string.",
            file: file,
            line: line
        )
        XCTAssertNil(reloadedSecond.workingSessionID, file: file, line: line)
    }

    static func assertStandalonePregnancyChecksPreserveIdentityPayloadAndSire(
        using fixture: HealthRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let cow = try repository.create(
            input: makeAnimalInput(
                name: "Pregnancy Contract Cow",
                tagNumber: "P201",
                sex: .female,
                birthDate: date(year: 2020, month: 2, day: 10)
            )
        )
        let sire = try repository.create(
            input: makeAnimalInput(
                name: "Pregnancy Contract Sire",
                tagNumber: "P202",
                sex: .male,
                birthDate: date(year: 2018, month: 2, day: 10)
            )
        )
        let controlAnimal = try repository.create(
            input: makeAnimalInput(
                name: "Pregnancy Contract Control",
                tagNumber: "P203",
                sex: .female,
                birthDate: date(year: 2021, month: 2, day: 10)
            )
        )

        let pregnancyDate = date(year: 2026, month: 6, day: 12)
        let dueDate = date(year: 2026, month: 12, day: 20)
        let technician = "Contract Technician"
        let result = try repository.addPregnancyCheck(
            animalID: cow.id,
            input: PregnancyCheckInput(
                date: pregnancyDate,
                result: .pregnant,
                technician: technician,
                estimatedDaysPregnant: 110,
                dueDate: dueDate,
                sireAnimalID: sire.id
            )
        )
        XCTAssertEqual(result.id, cow.id, file: file, line: line)

        let firstReloadRecords = try fixture.makeTestControl().pregnancyChecks(forAnimalID: cow.id)
        XCTAssertEqual(firstReloadRecords.count, 1, file: file, line: line)
        let firstPersisted = try XCTUnwrap(firstReloadRecords.first, file: file, line: line)
        XCTAssertEqual(firstPersisted.animalID, cow.id, file: file, line: line)
        XCTAssertEqual(firstPersisted.date, pregnancyDate, file: file, line: line)
        XCTAssertEqual(firstPersisted.resultRawValue, PregnancyResult.pregnant.rawValue, file: file, line: line)
        XCTAssertEqual(firstPersisted.technician, technician, file: file, line: line)
        XCTAssertEqual(firstPersisted.estimatedDaysPregnant, 110, file: file, line: line)
        XCTAssertEqual(firstPersisted.dueDate, dueDate, file: file, line: line)
        XCTAssertEqual(firstPersisted.sireAnimalID, sire.id, file: file, line: line)
        XCTAssertNil(
            firstPersisted.workingSessionID,
            "A pregnancy check added directly from Animal must not acquire a Working-session relationship.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try fixture.makeTestControl().pregnancyChecks(forAnimalID: controlAnimal.id).isEmpty,
            "Adding a pregnancy check to one animal must not create a check for an unrelated animal.",
            file: file,
            line: line
        )

        let backdatedDate = date(year: 2026, month: 4, day: 1)
        _ = try fixture.makeAnimalRepository().addPregnancyCheck(
            animalID: cow.id,
            input: PregnancyCheckInput(
                date: backdatedDate,
                result: .open,
                technician: nil,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            )
        )

        let reloadedRecords = try fixture.makeTestControl().pregnancyChecks(forAnimalID: cow.id)
        XCTAssertEqual(reloadedRecords.count, 2, file: file, line: line)
        XCTAssertEqual(
            Set(reloadedRecords.map(\.id)).count,
            2,
            "Each durable pregnancy check must have its own application UUID.",
            file: file,
            line: line
        )
        let reloadedFirst = try XCTUnwrap(
            reloadedRecords.first { $0.id == firstPersisted.id },
            "Adding another pregnancy check must preserve the original check UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedFirst.animalID, cow.id, file: file, line: line)
        XCTAssertEqual(reloadedFirst.date, pregnancyDate, file: file, line: line)
        XCTAssertEqual(reloadedFirst.resultRawValue, PregnancyResult.pregnant.rawValue, file: file, line: line)
        XCTAssertEqual(reloadedFirst.technician, technician, file: file, line: line)
        XCTAssertEqual(reloadedFirst.estimatedDaysPregnant, 110, file: file, line: line)
        XCTAssertEqual(reloadedFirst.dueDate, dueDate, file: file, line: line)
        XCTAssertEqual(reloadedFirst.sireAnimalID, sire.id, file: file, line: line)
        XCTAssertNil(reloadedFirst.workingSessionID, file: file, line: line)

        let reloadedBackdated = try XCTUnwrap(
            reloadedRecords.first { $0.id != firstPersisted.id },
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedBackdated.animalID, cow.id, file: file, line: line)
        XCTAssertEqual(reloadedBackdated.date, backdatedDate, file: file, line: line)
        XCTAssertEqual(reloadedBackdated.resultRawValue, PregnancyResult.open.rawValue, file: file, line: line)
        XCTAssertNil(reloadedBackdated.technician, file: file, line: line)
        XCTAssertNil(reloadedBackdated.estimatedDaysPregnant, file: file, line: line)
        XCTAssertNil(reloadedBackdated.dueDate, file: file, line: line)
        XCTAssertNil(reloadedBackdated.sireAnimalID, file: file, line: line)
        XCTAssertNil(reloadedBackdated.workingSessionID, file: file, line: line)
    }

    static func assertDeletingPregnancySireNullifiesOnlySireRelationship(
        using fixture: HealthRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let cow = try repository.create(
            input: makeAnimalInput(
                name: "Sire Nullify Contract Cow",
                tagNumber: "P301",
                sex: .female,
                birthDate: date(year: 2020, month: 3, day: 10)
            )
        )
        let sire = try repository.create(
            input: makeAnimalInput(
                name: "Sire Nullify Contract Bull",
                tagNumber: "P302",
                sex: .male,
                birthDate: date(year: 2017, month: 3, day: 10)
            )
        )
        let checkDate = date(year: 2026, month: 6, day: 15)
        _ = try repository.addPregnancyCheck(
            animalID: cow.id,
            input: PregnancyCheckInput(
                date: checkDate,
                result: .pregnant,
                technician: "Contract Tech",
                estimatedDaysPregnant: 80,
                dueDate: nil,
                sireAnimalID: sire.id
            )
        )

        let beforeDelete = try XCTUnwrap(
            fixture.makeTestControl().pregnancyChecks(forAnimalID: cow.id).first,
            file: file,
            line: line
        )
        XCTAssertEqual(beforeDelete.sireAnimalID, sire.id, file: file, line: line)

        try fixture.makeAnimalRepository().delete(ids: [sire.id])

        let afterDeleteRecords = try fixture.makeTestControl().pregnancyChecks(forAnimalID: cow.id)
        XCTAssertEqual(
            afterDeleteRecords.count,
            1,
            "Deleting a breeding sire must not delete a pregnancy check owned by another animal.",
            file: file,
            line: line
        )
        let afterDelete = try XCTUnwrap(afterDeleteRecords.first, file: file, line: line)
        XCTAssertEqual(
            afterDelete.id,
            beforeDelete.id,
            "Nullifying the deleted sire relationship must preserve pregnancy-check identity.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDelete.animalID, cow.id, file: file, line: line)
        XCTAssertEqual(afterDelete.date, checkDate, file: file, line: line)
        XCTAssertEqual(afterDelete.resultRawValue, PregnancyResult.pregnant.rawValue, file: file, line: line)
        XCTAssertNil(
            afterDelete.sireAnimalID,
            "A deleted breeding sire must leave the historical pregnancy check intact with a nil live sire relationship.",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: cow.id),
            "Deleting the sire must not delete or archive the pregnancy-check owner.",
            file: file,
            line: line
        )
    }

    static func assertHardDeletingAnimalCascadesOwnedHealthHistory(
        using fixture: HealthRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let animal = try repository.create(
            input: makeAnimalInput(
                name: "Health Cascade Contract Cow",
                tagNumber: "H401",
                sex: .female,
                birthDate: date(year: 2020, month: 4, day: 10)
            )
        )
        let sire = try repository.create(
            input: makeAnimalInput(
                name: "Health Cascade Contract Sire",
                tagNumber: "H402",
                sex: .male,
                birthDate: date(year: 2017, month: 4, day: 10)
            )
        )
        _ = try repository.addHealthRecord(
            animalID: animal.id,
            input: HealthRecordInput(
                date: date(year: 2026, month: 6, day: 20),
                treatment: "Cascade contract treatment",
                notes: "Must disappear with owner"
            )
        )
        _ = try repository.addPregnancyCheck(
            animalID: animal.id,
            input: PregnancyCheckInput(
                date: date(year: 2026, month: 6, day: 21),
                result: .pregnant,
                technician: "Cascade Tech",
                estimatedDaysPregnant: 70,
                dueDate: nil,
                sireAnimalID: sire.id
            )
        )

        XCTAssertEqual(
            try fixture.makeTestControl().healthRecords(forAnimalID: animal.id).count,
            1,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeTestControl().pregnancyChecks(forAnimalID: animal.id).count,
            1,
            file: file,
            line: line
        )

        try fixture.makeAnimalRepository().delete(ids: [animal.id])

        let reloadedControl = fixture.makeTestControl()
        XCTAssertTrue(
            try reloadedControl.healthRecords(forAnimalID: animal.id).isEmpty,
            "Hard deleting an animal must cascade its owned standalone health records.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try reloadedControl.pregnancyChecks(forAnimalID: animal.id).isEmpty,
            "Hard deleting an animal must cascade its owned standalone pregnancy checks.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            try reloadedControl.allHealthRecords().contains { $0.animalID == animal.id },
            "A hard-deleted animal must not leave orphaned health rows behind.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            try reloadedControl.allPregnancyChecks().contains { $0.animalID == animal.id },
            "A hard-deleted animal must not leave orphaned pregnancy rows behind.",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: sire.id),
            "Deleting the pregnancy-check owner must not delete the referenced breeding sire.",
            file: file,
            line: line
        )
    }

    static func assertMissingAnimalMutationsDoNotCreateOrphans(
        using fixture: HealthRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeAnimalRepository()
        let controlAnimal = try repository.create(
            input: makeAnimalInput(
                name: "Missing Animal Contract Control",
                tagNumber: "H501",
                sex: .female,
                birthDate: date(year: 2020, month: 5, day: 10)
            )
        )
        _ = try repository.addHealthRecord(
            animalID: controlAnimal.id,
            input: HealthRecordInput(
                date: date(year: 2026, month: 6, day: 25),
                treatment: "Existing control treatment",
                notes: nil
            )
        )
        _ = try repository.addPregnancyCheck(
            animalID: controlAnimal.id,
            input: PregnancyCheckInput(
                date: date(year: 2026, month: 6, day: 26),
                result: .open,
                technician: nil,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            )
        )

        let beforeHealth = sortedHealth(try fixture.makeTestControl().allHealthRecords())
        let beforePregnancy = sortedPregnancy(try fixture.makeTestControl().allPregnancyChecks())
        let missingAnimalID = UUID()

        assertAnimalNotFound(file: file, line: line) {
            _ = try fixture.makeAnimalRepository().addHealthRecord(
                animalID: missingAnimalID,
                input: HealthRecordInput(
                    date: date(year: 2026, month: 7, day: 1),
                    treatment: "Must not persist",
                    notes: "Missing owner"
                )
            )
        }
        assertAnimalNotFound(file: file, line: line) {
            _ = try fixture.makeAnimalRepository().addPregnancyCheck(
                animalID: missingAnimalID,
                input: PregnancyCheckInput(
                    date: date(year: 2026, month: 7, day: 2),
                    result: .pregnant,
                    technician: "Must not persist",
                    estimatedDaysPregnant: 50,
                    dueDate: nil,
                    sireAnimalID: nil
                )
            )
        }

        let afterHealth = sortedHealth(try fixture.makeTestControl().allHealthRecords())
        let afterPregnancy = sortedPregnancy(try fixture.makeTestControl().allPregnancyChecks())
        XCTAssertEqual(
            afterHealth,
            beforeHealth,
            "A failed health mutation for a missing animal must not create an orphan or alter existing health history.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterPregnancy,
            beforePregnancy,
            "A failed pregnancy mutation for a missing animal must not create an orphan or alter existing pregnancy history.",
            file: file,
            line: line
        )
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        sex: Sex,
        birthDate: Date
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: sex,
            birthDate: birthDate,
            status: .active,
            pastureID: nil,
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

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }

    private static func sortedHealth(
        _ records: [HealthRecordContractSnapshot]
    ) -> [HealthRecordContractSnapshot] {
        records.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func sortedPregnancy(
        _ records: [PregnancyCheckContractSnapshot]
    ) -> [PregnancyCheckContractSnapshot] {
        records.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func assertAnimalNotFound(
        file: StaticString,
        line: UInt,
        _ operation: () throws -> Void
    ) {
        do {
            try operation()
            XCTFail("Expected AnimalValidationError.animalNotFound.", file: file, line: line)
        } catch let error as AnimalValidationError {
            XCTAssertEqual(error, .animalNotFound, file: file, line: line)
        } catch {
            XCTFail("Expected AnimalValidationError.animalNotFound, got \(error).", file: file, line: line)
        }
    }
}
