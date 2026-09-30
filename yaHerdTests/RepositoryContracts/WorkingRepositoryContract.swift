import Foundation
import XCTest
@testable import yaHerd

/// Permanent persistence-neutral behavioral contract for `WorkingRepository` implementations.
///
/// These assertions protect Domain-visible Working behavior that must survive the Core Data cutover.
/// The contract intentionally has no SwiftData runner. The production Core Data repository will
/// execute it once the Working persistence surface is implemented.
@MainActor
struct WorkingRepositoryContractFixture {
    let makeWorkingRepository: () -> any WorkingRepository
    let makeAnimalRepository: () -> any AnimalRepository
    let makePastureRepository: () -> any PastureRepository
    let makeTagColorRepository: () -> any TagColorRepository
}

@MainActor
enum WorkingRepositoryContract {
    static func assertSessionStartAndReadProjections(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Contract North", using: fixture)
        let dam = try makeAnimal(
            name: "Working Dam",
            tagNumber: "10",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let calf = try makeAnimal(
            name: "Working Calf",
            tagNumber: "2",
            sex: .female,
            pastureID: source.id,
            damID: dam.id,
            using: fixture
        )
        let excluded = try makeAnimal(
            name: "Working Excluded",
            tagNumber: "99",
            sex: .male,
            pastureID: source.id,
            using: fixture
        )

        let treatmentID = UUID()
        let treatment = WorkingTreatmentPlanItem(
            id: treatmentID,
            name: "Contract Vaccine",
            suggestedDose: WorkingTreatmentDose(
                amount: 2.5,
                unit: .milliliter,
                route: .subcutaneous
            )
        )
        let requestedDate = date(year: 2026, month: 9, day: 17, hour: 14, minute: 30)
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: requestedDate,
                sourcePastureID: source.id,
                treatmentTemplateName: "  Fall Work  ",
                plannedTreatments: [treatment],
                animalIDs: [dam.id, calf.id, dam.id]
            )
        )

        let created = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(created.id, sessionID, file: file, line: line)
        XCTAssertEqual(
            created.date,
            Calendar.autoupdatingCurrent.startOfDay(for: requestedDate),
            file: file,
            line: line
        )
        XCTAssertEqual(created.status, .active, file: file, line: line)
        XCTAssertEqual(created.sourcePastureID, source.id, file: file, line: line)
        XCTAssertEqual(created.sourcePastureName, "Working Contract North", file: file, line: line)
        XCTAssertTrue(
            created.isSourcePastureAvailable,
            "A session with a live source relationship must expose that source as usable separately from its historical ID/name.",
            file: file,
            line: line
        )
        XCTAssertTrue(created.isSourcePastureAvailable, file: file, line: line)
        XCTAssertEqual(created.treatmentTemplateName, "Fall Work", file: file, line: line)
        XCTAssertEqual(created.plannedTreatments, [treatment], file: file, line: line)
        XCTAssertEqual(created.queueItems.count, 2, "Duplicate requested animal IDs must not create duplicate queue rows.", file: file, line: line)
        XCTAssertEqual(
            Set(created.queueItems.compactMap(\.animalID)),
            Set([dam.id, calf.id]),
            "The repository contract owns queue membership, not presentation ordering.",
            file: file,
            line: line
        )
        XCTAssertEqual(Set(created.queueItems.map(\.id)).count, 2, "Queue item application UUIDs must be unique.", file: file, line: line)
        XCTAssertTrue(created.queueItems.allSatisfy { $0.status == .queued }, file: file, line: line)
        XCTAssertTrue(created.queueItems.allSatisfy { $0.collectedFromPastureName == "Working Contract North" }, file: file, line: line)

        let calfQueue = try XCTUnwrap(created.queueItems.first { $0.animalID == calf.id }, file: file, line: line)
        XCTAssertEqual(calfQueue.animalName, "Working Calf", file: file, line: line)
        XCTAssertEqual(calfQueue.animalDisplayTagNumber, "2", file: file, line: line)
        XCTAssertEqual(calfQueue.animalDamDisplayTagNumber, "10", file: file, line: line)
        XCTAssertEqual(calfQueue.animalSex, .female, file: file, line: line)
        XCTAssertEqual(calfQueue.collectedFromPastureID, source.id, file: file, line: line)

        for animalID in [dam.id, calf.id] {
            let animal = try XCTUnwrap(
                fixture.makeAnimalRepository().fetchAnimalDetail(id: animalID),
                file: file,
                line: line
            )
            XCTAssertNil(animal.pastureID, file: file, line: line)
            XCTAssertEqual(animal.location, .workingPen, file: file, line: line)
        }
        let unaffected = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: excluded.id),
            file: file,
            line: line
        )
        XCTAssertEqual(unaffected.pastureID, source.id, file: file, line: line)
        XCTAssertEqual(unaffected.location, .pasture, file: file, line: line)

        let reloadedRepository = fixture.makeWorkingRepository()
        let reloaded = try XCTUnwrap(
            reloadedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.id, created.id, "Session application UUID must survive reload.", file: file, line: line)
        XCTAssertEqual(Set(reloaded.queueItems.map(\.id)), Set(created.queueItems.map(\.id)), "Queue application UUIDs must survive reload.", file: file, line: line)
        XCTAssertEqual(reloaded.plannedTreatments, [treatment], file: file, line: line)

        let summary = try XCTUnwrap(
            reloadedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.date, reloaded.date, file: file, line: line)
        XCTAssertEqual(summary.status, .active, file: file, line: line)
        XCTAssertEqual(summary.sourcePastureName, reloaded.sourcePastureName, file: file, line: line)
        XCTAssertEqual(summary.treatmentTemplateName, reloaded.treatmentTemplateName, file: file, line: line)
        XCTAssertEqual(summary.totalQueueItems, 2, file: file, line: line)
        XCTAssertEqual(summary.completedQueueItems, 0, file: file, line: line)

        let editor = try XCTUnwrap(
            reloadedRepository.fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: calfQueue.id
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(editor.id, calfQueue.id, file: file, line: line)
        XCTAssertEqual(editor.sessionID, sessionID, file: file, line: line)
        XCTAssertEqual(editor.sessionStatus, .active, file: file, line: line)
        XCTAssertEqual(editor.sessionSourcePastureName, "Working Contract North", file: file, line: line)
        XCTAssertEqual(editor.plannedTreatments, [treatment], file: file, line: line)
        XCTAssertEqual(editor.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(editor.animalDisplayTagNumber, "2", file: file, line: line)
        XCTAssertEqual(editor.animalDamDisplayTagNumber, "10", file: file, line: line)
        XCTAssertEqual(editor.status, .queued, file: file, line: line)
        XCTAssertTrue(editor.treatmentRecords.isEmpty, file: file, line: line)
        XCTAssertNil(editor.pregnancyCheck, file: file, line: line)
        XCTAssertFalse(editor.castrationPerformedInSession, file: file, line: line)
        XCTAssertEqual(editor.observationNotes, "", file: file, line: line)
    }

    static func assertStartAllEligibleAnimalsAndValidation(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Eligibility Source", using: fixture)
        let other = try makePasture(named: "Working Eligibility Other", using: fixture)
        let first = try makeAnimal(name: "Eligible One", tagNumber: "101", sex: .female, pastureID: source.id, using: fixture)
        let second = try makeAnimal(name: "Eligible Two", tagNumber: "102", sex: .male, pastureID: source.id, using: fixture)
        let archived = try makeAnimal(name: "Archived Source Animal", tagNumber: "103", sex: .female, pastureID: source.id, using: fixture)
        try fixture.makeAnimalRepository().archive(ids: [archived.id])
        let otherAnimal = try makeAnimal(name: "Other Pasture", tagNumber: "201", sex: .female, pastureID: other.id, using: fixture)

        let repository = fixture.makeWorkingRepository()
        let allEligibleSessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 18),
                sourcePastureID: source.id,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: nil
            )
        )
        let allEligible = try XCTUnwrap(repository.fetchSessionDetail(id: allEligibleSessionID), file: file, line: line)
        XCTAssertEqual(Set(allEligible.queueItems.compactMap(\.animalID)), Set([first.id, second.id]), file: file, line: line)
        XCTAssertFalse(
            allEligible.queueItems.contains { $0.animalID == archived.id },
            "Starting all eligible animals must exclude archived source-pasture animals.",
            file: file,
            line: line
        )
        XCTAssertEqual(allEligible.treatmentTemplateName, "Working Session", file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().startSession(
                input: WorkingSessionStartInput(
                    date: date(year: 2026, month: 9, day: 19),
                    sourcePastureID: other.id,
                    treatmentTemplateName: "Invalid Selection",
                    plannedTreatments: [],
                    animalIDs: [first.id]
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .animalAlreadyInAnotherSession, file: file, line: line)
        }

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().startSession(
                input: WorkingSessionStartInput(
                    date: date(year: 2026, month: 9, day: 19),
                    sourcePastureID: source.id,
                    treatmentTemplateName: nil,
                    plannedTreatments: [],
                    animalIDs: []
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .noEligibleAnimals, file: file, line: line)
        }

        let missingAnimalID = UUID()
        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().startSession(
                input: WorkingSessionStartInput(
                    date: date(year: 2026, month: 9, day: 19),
                    sourcePastureID: other.id,
                    treatmentTemplateName: nil,
                    plannedTreatments: [],
                    animalIDs: [otherAnimal.id, missingAnimalID]
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .animalNotFound, file: file, line: line)
        }

        let otherAfterFailures = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: otherAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(otherAfterFailures.pastureID, other.id, "Failed starts must not collect otherwise-valid animals.", file: file, line: line)
        XCTAssertEqual(otherAfterFailures.location, .pasture, file: file, line: line)

        let noEligiblePasture = try makePasture(named: "Working No Eligible Source", using: fixture)
        let archivedOnly = try makeAnimal(
            name: "Archived Only Working Candidate",
            tagNumber: "NE101",
            sex: .female,
            pastureID: noEligiblePasture.id,
            using: fixture
        )
        try fixture.makeAnimalRepository().archive(ids: [archivedOnly.id])

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().startSession(
                input: WorkingSessionStartInput(
                    date: date(year: 2026, month: 9, day: 19),
                    sourcePastureID: noEligiblePasture.id,
                    treatmentTemplateName: nil,
                    plannedTreatments: [],
                    animalIDs: nil
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .noEligibleAnimals,
                "Nil animal IDs means all eligible animals; if none exist, no empty Working session may be created.",
                file: file,
                line: line
            )
        }
        XCTAssertFalse(
            try fixture.makeWorkingRepository().fetchSessions().contains {
                $0.sourcePastureName == "Working No Eligible Source"
            },
            file: file,
            line: line
        )
    }

    static func assertSessionListOrderingPersists(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let olderPasture = try makePasture(named: "Working List Older", using: fixture)
        let newerPasture = try makePasture(named: "Working List Newer", using: fixture)
        let olderAnimal = try makeAnimal(
            name: "Working List Older Cow",
            tagNumber: "LS101",
            sex: .female,
            pastureID: olderPasture.id,
            using: fixture
        )
        let newerAnimal = try makeAnimal(
            name: "Working List Newer Cow",
            tagNumber: "LS102",
            sex: .female,
            pastureID: newerPasture.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let olderID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 1),
                sourcePastureID: olderPasture.id,
                treatmentTemplateName: "Older Session",
                plannedTreatments: [],
                animalIDs: [olderAnimal.id]
            )
        )
        let newerID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 3),
                sourcePastureID: newerPasture.id,
                treatmentTemplateName: "Newer Session",
                plannedTreatments: [],
                animalIDs: [newerAnimal.id]
            )
        )

        let summaries = try fixture.makeWorkingRepository().fetchSessions()
            .filter { $0.id == olderID || $0.id == newerID }

        XCTAssertEqual(
            summaries.map(\.id),
            [newerID, olderID],
            "Working session list reads must remain newest-first after a fresh repository access.",
            file: file,
            line: line
        )
        XCTAssertEqual(summaries.first?.sourcePastureName, "Working List Newer", file: file, line: line)
        XCTAssertEqual(summaries.last?.sourcePastureName, "Working List Older", file: file, line: line)
        XCTAssertTrue(summaries.allSatisfy { $0.status == .active }, file: file, line: line)
        XCTAssertTrue(summaries.allSatisfy { $0.totalQueueItems == 1 }, file: file, line: line)
        XCTAssertTrue(summaries.allSatisfy { $0.completedQueueItems == 0 }, file: file, line: line)
    }

    @discardableResult
    static func makePasture(
        named name: String,
        using fixture: WorkingRepositoryContractFixture
    ) throws -> PastureDetailSnapshot {
        try fixture.makePastureRepository().create(
            input: PastureInput(
                name: name,
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
    }

    @discardableResult
    static func makeAnimal(
        name: String,
        tagNumber: String,
        sex: Sex,
        pastureID: UUID,
        tagColorID: UUID? = nil,
        damID: UUID? = nil,
        using fixture: WorkingRepositoryContractFixture
    ) throws -> AnimalDetailSnapshot {
        try fixture.makeAnimalRepository().create(
            input: AnimalInput(
                name: name,
                tagNumber: tagNumber,
                tagColorID: tagColorID,
                sex: sex,
                birthDate: date(year: 2024, month: 1, day: 1),
                status: .active,
                pastureID: pastureID,
                sireID: nil,
                damID: damID,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            )
        )
    }

    static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertMissingIdentifiersAndEligibilityErrorsRemainStable(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeWorkingRepository()
        let missingSessionID = UUID()
        let missingTemplateID = UUID()
        let missingQueueItemID = UUID()

        XCTAssertNil(try repository.fetchSessionDetail(id: missingSessionID), file: file, line: line)
        XCTAssertNil(try repository.fetchTemplateDetail(id: missingTemplateID), file: file, line: line)
        XCTAssertNil(
            try repository.fetchQueueItemEditor(
                sessionID: missingSessionID,
                queueItemID: missingQueueItemID
            ),
            file: file,
            line: line
        )

        assertThrowsWorkingError(.pastureNotFound, file: file, line: line) {
            _ = try fixture.makeWorkingRepository().startSession(
                input: WorkingSessionStartInput(
                    date: date(year: 2026, month: 10, day: 10),
                    sourcePastureID: UUID(),
                    treatmentTemplateName: nil,
                    plannedTreatments: [],
                    animalIDs: nil
                )
            )
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().collectAnimals(
                sessionID: missingSessionID,
                animalIDs: [UUID()]
            )
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().deleteSession(id: missingSessionID)
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().reopenSession(id: missingSessionID)
        }
        assertThrowsWorkingError(.templateNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().updateTemplate(
                id: missingTemplateID,
                name: "Missing Template",
                items: []
            )
        }
        assertThrowsWorkingError(.templateNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().deleteTemplates(ids: [missingTemplateID])
        }

        let source = try makePasture(named: "Working Error Source", using: fixture)
        let other = try makePasture(named: "Working Error Other", using: fixture)
        let selected = try makeAnimal(
            name: "Working Error Selected",
            tagNumber: "ER101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let wrongPastureAnimal = try makeAnimal(
            name: "Working Error Wrong Pasture",
            tagNumber: "ER102",
            sex: .female,
            pastureID: other.id,
            using: fixture
        )

        assertThrowsWorkingError(.animalNotEligibleForCollection, file: file, line: line) {
            _ = try fixture.makeWorkingRepository().startSession(
                input: WorkingSessionStartInput(
                    date: date(year: 2026, month: 10, day: 10),
                    sourcePastureID: source.id,
                    treatmentTemplateName: "Eligibility Error",
                    plannedTreatments: [],
                    animalIDs: [wrongPastureAnimal.id]
                )
            )
        }

        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 10),
                sourcePastureID: source.id,
                treatmentTemplateName: "Queue Error",
                plannedTreatments: [],
                animalIDs: [selected.id]
            )
        )
        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )

        assertThrowsWorkingError(.queueItemNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().complete(
                queueItemID: missingQueueItemID,
                inSessionID: sessionID,
                treatmentEntries: [],
                pregnancyCheck: nil,
                markCastrated: false,
                observationNotes: ""
            )
        }
        assertThrowsWorkingError(.queueItemNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().saveEdits(
                forQueueItemID: missingQueueItemID,
                inSessionID: sessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .queued,
                    completedAt: nil,
                    destinationPastureID: nil,
                    treatmentEntries: [],
                    pregnancyCheck: nil,
                    castrationPerformed: false,
                    observationNotes: ""
                )
            )
        }
        assertThrowsWorkingError(.queueItemNotFound, file: file, line: line) {
            _ = try fixture.makeWorkingRepository().replacePrimaryTag(
                forQueueItemID: missingQueueItemID,
                inSessionID: sessionID,
                input: WorkingTagReplacementInput(number: "ER999", colorID: nil)
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "Missing queue-item mutations must leave the active Working session unchanged.",
            file: file,
            line: line
        )
        let wrongPastureAfterFailure = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: wrongPastureAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(wrongPastureAfterFailure.pastureID, other.id, file: file, line: line)
        XCTAssertEqual(wrongPastureAfterFailure.location, .pasture, file: file, line: line)
    }

    private static func assertThrowsWorkingError(
        _ expected: WorkingRepositoryError,
        file: StaticString,
        line: UInt,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(
            try operation(),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, expected, file: file, line: line)
        }
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertSessionStartRejectsInvalidPlanBeforeMutation(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Invalid Start Plan Source", using: fixture)
        let animal = try makeAnimal(
            name: "Invalid Start Plan Cow",
            tagNumber: "IP101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let beforeSessions = try fixture.makeWorkingRepository().fetchSessions()
        let beforeAnimal = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().startSession(
                input: WorkingSessionStartInput(
                    date: date(year: 2026, month: 10, day: 14),
                    sourcePastureID: source.id,
                    treatmentTemplateName: "Invalid Start Plan",
                    plannedTreatments: [
                        WorkingTreatmentPlanItem(
                            id: UUID(),
                            name: "Invalid Negative Dose",
                            suggestedDose: WorkingTreatmentDose(
                                amount: -1,
                                unit: .milliliter
                            )
                        )
                    ],
                    animalIDs: [animal.id]
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .invalidTreatmentDose,
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessions(),
            beforeSessions,
            "Invalid session-plan input must fail before creating a Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            beforeAnimal,
            "Invalid session-plan input must fail before changing Animal collection state.",
            file: file,
            line: line
        )
    }

    static func assertMissingIdentifiersAcrossMutationSurfaceRemainStable(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let missingSessionID = UUID()
        let missingQueueItemID = UUID()

        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().updateSessionTreatments(
                id: missingSessionID,
                plannedTreatments: []
            )
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().completeSession(
                id: missingSessionID,
                assignments: []
            )
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().complete(
                queueItemID: missingQueueItemID,
                inSessionID: missingSessionID,
                treatmentEntries: [],
                pregnancyCheck: nil,
                markCastrated: false,
                observationNotes: ""
            )
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().saveEdits(
                forQueueItemID: missingQueueItemID,
                inSessionID: missingSessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .queued,
                    completedAt: nil,
                    destinationPastureID: nil,
                    treatmentEntries: [],
                    pregnancyCheck: nil,
                    castrationPerformed: false,
                    observationNotes: ""
                )
            )
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().deleteWorkData(
                forQueueItemID: missingQueueItemID,
                inSessionID: missingSessionID
            )
        }
        assertThrowsWorkingError(.sessionNotFound, file: file, line: line) {
            _ = try fixture.makeWorkingRepository().replacePrimaryTag(
                forQueueItemID: missingQueueItemID,
                inSessionID: missingSessionID,
                input: WorkingTagReplacementInput(
                    number: "MI101",
                    colorID: nil
                )
            )
        }

        let source = try makePasture(named: "Working Missing Queue Source", using: fixture)
        let animal = try makeAnimal(
            name: "Missing Queue Cow",
            tagNumber: "MQ101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 15),
                sourcePastureID: source.id,
                treatmentTemplateName: "Missing Queue",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let beforeSession = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )

        XCTAssertNil(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: missingQueueItemID
            ),
            file: file,
            line: line
        )
        assertThrowsWorkingError(.queueItemNotFound, file: file, line: line) {
            try fixture.makeWorkingRepository().deleteWorkData(
                forQueueItemID: missingQueueItemID,
                inSessionID: sessionID
            )
        }
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            file: file,
            line: line
        )
    }
}

