import Foundation
import XCTest
@testable import yaHerd

@MainActor
extension WorkingRepositoryContract {
    static func assertQueueWorkDataReplacementAndReset(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Data Source", using: fixture)
        let destination = try makePasture(named: "Working Data Destination", using: fixture)
        let sirePasture = try makePasture(named: "Working Data Sire Pasture", using: fixture)
        let animal = try makeAnimal(
            name: "Working Data Cow",
            tagNumber: "301",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let sire = try makeAnimal(
            name: "Working Data Sire",
            tagNumber: "B1",
            sex: .male,
            pastureID: sirePasture.id,
            using: fixture
        )

        let independentHealthDate = date(year: 2026, month: 9, day: 18, hour: 8)
        let independentPregnancyDate = date(year: 2026, month: 9, day: 19, hour: 8)
        let animalRepository = fixture.makeAnimalRepository()
        _ = try animalRepository.addHealthRecord(
            animalID: animal.id,
            input: HealthRecordInput(
                date: independentHealthDate,
                treatment: "Independent hoof trim",
                notes: "Standalone health control"
            )
        )
        _ = try animalRepository.addPregnancyCheck(
            animalID: animal.id,
            input: PregnancyCheckInput(
                date: independentPregnancyDate,
                result: .open,
                technician: "Independent control",
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            )
        )

        let plannedID = UUID()
        let plannedTreatment = WorkingTreatmentPlanItem(
            id: plannedID,
            name: "Planned Vaccine",
            suggestedDose: WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous)
        )
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 20),
                sourcePastureID: source.id,
                treatmentTemplateName: "Work Data Contract",
                plannedTreatments: [plannedTreatment],
                animalIDs: [animal.id]
            )
        )
        let started = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let queueItemID = try XCTUnwrap(started.queueItems.first?.id, file: file, line: line)

        let oneOffID = UUID()
        let treatmentDate = date(year: 2026, month: 9, day: 20, hour: 9)
        let pregnancyDate = date(year: 2026, month: 9, day: 20, hour: 9, minute: 5)
        let dueDate = date(year: 2027, month: 4, day: 28)
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: treatmentDate,
                    treatmentItemID: oneOffID,
                    itemName: "One-Off Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 5, unit: .milliliter, route: .intramuscular)
                ),
                WorkingTreatmentEntryInput(
                    date: treatmentDate,
                    treatmentItemID: plannedID,
                    itemName: "Planned Vaccine",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: pregnancyDate,
                result: .pregnant,
                estimatedDaysPregnant: 55,
                dueDate: dueDate,
                sireAnimalID: sire.id
            ),
            markCastrated: false,
            observationNotes: "  Mild eye irritation  "
        )

        let completed = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(completed.status, .done, file: file, line: line)
        let firstCompletedAt = try XCTUnwrap(completed.completedAt, file: file, line: line)
        XCTAssertEqual(completed.treatmentRecords.count, 2, file: file, line: line)
        XCTAssertEqual(
            Set(completed.treatmentRecords.map(\.treatmentItemID)),
            Set([plannedID, oneOffID]),
            "Planned and valid one-off treatment records must both remain durable; array ordering is presentation-owned.",
            file: file,
            line: line
        )
        let completedPlanned = try XCTUnwrap(
            completed.treatmentRecords.first { $0.treatmentItemID == plannedID },
            file: file,
            line: line
        )
        XCTAssertEqual(completedPlanned.itemName, "Planned Vaccine", file: file, line: line)
        XCTAssertTrue(completedPlanned.given, file: file, line: line)
        XCTAssertEqual(completedPlanned.dose, WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous), file: file, line: line)
        let completedOneOff = try XCTUnwrap(
            completed.treatmentRecords.first { $0.treatmentItemID == oneOffID },
            file: file,
            line: line
        )
        XCTAssertEqual(completedOneOff.itemName, "One-Off Treatment", file: file, line: line)
        XCTAssertTrue(completedOneOff.given, file: file, line: line)
        XCTAssertEqual(completedOneOff.dose, WorkingTreatmentDose(amount: 5, unit: .milliliter, route: .intramuscular), file: file, line: line)
        XCTAssertEqual(Set(completed.treatmentRecords.map(\.id)).count, 2, "Distinct persisted treatment records must expose distinct application UUIDs.", file: file, line: line)

        let pregnancy = try XCTUnwrap(completed.pregnancyCheck, file: file, line: line)
        XCTAssertEqual(pregnancy.date, pregnancyDate, file: file, line: line)
        XCTAssertEqual(pregnancy.result, .pregnant, file: file, line: line)
        XCTAssertEqual(pregnancy.estimatedDaysPregnant, 55, file: file, line: line)
        XCTAssertEqual(pregnancy.dueDate, dueDate, file: file, line: line)
        XCTAssertEqual(pregnancy.sire?.id, sire.id, file: file, line: line)
        XCTAssertEqual(pregnancy.sire?.displayTagNumber, "B1", file: file, line: line)
        XCTAssertFalse(completed.castrationPerformedInSession, file: file, line: line)
        XCTAssertEqual(completed.observationNotes, "Mild eye irritation", file: file, line: line)

        let sessionAfterComplete = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(sessionAfterComplete.doneCount, 1, file: file, line: line)
        XCTAssertEqual(sessionAfterComplete.queueItems.first?.completedAt, firstCompletedAt, file: file, line: line)
        let summaryAfterComplete = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterComplete.completedQueueItems, 1, file: file, line: line)

        let animalTimelineAfterComplete = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(
            animalTimelineAfterComplete.contains { event in
                guard case .health = event.type else { return false }
                return event.date == independentHealthDate
                    && event.title == "Independent hoof trim"
                    && event.details == "Standalone health control"
            },
            "Working completion must not replace unrelated standalone Animal health history.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            animalTimelineAfterComplete.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == independentPregnancyDate
                    && event.title == "Pregnancy Check: Open"
            },
            "Working completion must coexist with unrelated standalone pregnancy history.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            animalTimelineAfterComplete.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == pregnancyDate
                    && event.title == "Pregnancy Check: Pregnant"
                    && event.details == nil
            },
            "Working pregnancy checks must preserve their user-visible Animal timeline payload.",
            file: file,
            line: line
        )
        let animalSummaryAfterComplete = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimals().first { $0.id == animal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(animalSummaryAfterComplete.lastPregnancyCheckDate, pregnancyDate, file: file, line: line)
        XCTAssertEqual(animalSummaryAfterComplete.lastPregnancyStatus, .pregnant, file: file, line: line)
        XCTAssertEqual(animalSummaryAfterComplete.expectedCalvingDate, dueDate, file: file, line: line)
        XCTAssertTrue(
            animalTimelineAfterComplete.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
                    && event.details == "Mild eye irritation"
                    && event.date == firstCompletedAt
            },
            "Working observation history must preserve the generated title, normalized notes, and work timestamp.",
            file: file,
            line: line
        )

        let editedTreatmentDate = date(year: 2026, month: 9, day: 21, hour: 10)
        let editedPregnancyDate = date(year: 2026, month: 9, day: 21, hour: 10, minute: 5)
        try fixture.makeWorkingRepository().saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .inProgress,
                completedAt: firstCompletedAt,
                destinationPastureID: destination.id,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: editedTreatmentDate,
                        treatmentItemID: plannedID,
                        itemName: "Planned Vaccine Updated",
                        given: false,
                        dose: WorkingTreatmentDose(amount: 1.5, unit: .milliliter, route: .subcutaneous)
                    )
                ],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: editedPregnancyDate,
                    result: .open,
                    estimatedDaysPregnant: nil,
                    dueDate: nil,
                    sireAnimalID: nil
                ),
                castrationPerformed: false,
                observationNotes: "  Follow-up observation  "
            )
        )

        let edited = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(edited.status, .inProgress, file: file, line: line)
        XCTAssertNil(edited.completedAt, "Non-done queue states must clear completion metadata.", file: file, line: line)
        XCTAssertEqual(edited.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertEqual(edited.treatmentRecords.count, 1, file: file, line: line)
        XCTAssertEqual(edited.treatmentRecords.first?.treatmentItemID, plannedID, file: file, line: line)
        XCTAssertEqual(edited.treatmentRecords.first?.itemName, "Planned Vaccine Updated", file: file, line: line)
        XCTAssertEqual(edited.treatmentRecords.first?.given, false, file: file, line: line)
        XCTAssertEqual(edited.pregnancyCheck?.result, .open, file: file, line: line)
        XCTAssertNil(edited.pregnancyCheck?.sire, file: file, line: line)
        let editedTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(
            editedTimeline.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == editedPregnancyDate
                    && event.title == "Pregnancy Check: Open"
                    && event.details == nil
            },
            file: file,
            line: line
        )
        XCTAssertFalse(
            editedTimeline.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.title == "Pregnancy Check: Pregnant"
            },
            "Replacing a Working pregnancy check must remove the prior session-linked pregnancy event.",
            file: file,
            line: line
        )
        let animalSummaryAfterEdit = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimals().first { $0.id == animal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(animalSummaryAfterEdit.lastPregnancyCheckDate, editedPregnancyDate, file: file, line: line)
        XCTAssertEqual(animalSummaryAfterEdit.lastPregnancyStatus, .open, file: file, line: line)
        XCTAssertNil(animalSummaryAfterEdit.expectedCalvingDate, file: file, line: line)
        XCTAssertFalse(edited.castrationPerformedInSession, file: file, line: line)
        XCTAssertEqual(edited.observationNotes, "Follow-up observation", file: file, line: line)
        XCTAssertTrue(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id).contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
                    && event.details == "Follow-up observation"
            },
            "Replacing Working observation notes must replace the generated Animal timeline payload.",
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().deleteWorkData(
            forQueueItemID: queueItemID,
            inSessionID: sessionID
        )

        let reset = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(reset.status, .queued, file: file, line: line)
        XCTAssertNil(reset.completedAt, file: file, line: line)
        XCTAssertEqual(reset.destinationPastureID, destination.id, "Resetting work data must not discard the independently persisted destination assignment.", file: file, line: line)
        let resetSessionQueue = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(resetSessionQueue.status, .queued, file: file, line: line)
        XCTAssertNil(resetSessionQueue.completedAt, file: file, line: line)
        XCTAssertEqual(resetSessionQueue.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertTrue(reset.treatmentRecords.isEmpty, file: file, line: line)
        XCTAssertNil(reset.pregnancyCheck, file: file, line: line)
        XCTAssertFalse(reset.castrationPerformedInSession, file: file, line: line)
        XCTAssertEqual(reset.observationNotes, "", file: file, line: line)

        let timelineAfterReset = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(
            timelineAfterReset.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == independentPregnancyDate
                    && event.title == "Pregnancy Check: Open"
            },
            "Deleting Working work data must preserve unrelated standalone pregnancy history.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            timelineAfterReset.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == pregnancyDate || event.date == editedPregnancyDate
            },
            "Deleting Working work data must remove only the session-linked pregnancy checks.",
            file: file,
            line: line
        )
        let animalSummaryAfterReset = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimals().first { $0.id == animal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(animalSummaryAfterReset.lastPregnancyCheckDate, independentPregnancyDate, file: file, line: line)
        XCTAssertEqual(animalSummaryAfterReset.lastPregnancyStatus, .open, file: file, line: line)
        XCTAssertNil(animalSummaryAfterReset.expectedCalvingDate, file: file, line: line)
        XCTAssertTrue(
            timelineAfterReset.contains { event in
                guard case .health = event.type else { return false }
                return event.date == independentHealthDate
                    && event.title == "Independent hoof trim"
                    && event.details == "Standalone health control"
            },
            "Deleting Working work data must preserve unrelated standalone health history.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            timelineAfterReset.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
            },
            "Deleting Working work data must remove only the Working-generated observation history.",
            file: file,
            line: line
        )
    }

    static func assertQueueWorkDataValidationDoesNotPartiallyReplaceState(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Validation Source", using: fixture)
        let animal = try makeAnimal(name: "Validation Steer", tagNumber: "401", sex: .male, pastureID: source.id, using: fixture)
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 22),
                sourcePastureID: source.id,
                treatmentTemplateName: "Validation",
                plannedTreatments: [WorkingTreatmentPlanItem(id: treatmentID, name: "Valid Treatment")],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id, file: file, line: line)
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 9, day: 22, hour: 9),
                    treatmentItemID: treatmentID,
                    itemName: "Valid Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                )
            ],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: "Original durable observation"
        )
        let before = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().saveEdits(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .done,
                    completedAt: before.completedAt,
                    destinationPastureID: nil,
                    treatmentEntries: [
                        WorkingTreatmentEntryInput(
                            date: date(year: 2026, month: 9, day: 22, hour: 10),
                            treatmentItemID: treatmentID,
                            itemName: "Invalid Treatment",
                            given: true,
                            dose: WorkingTreatmentDose(amount: -1, unit: .milliliter)
                        )
                    ],
                    pregnancyCheck: nil,
                    castrationPerformed: true,
                    observationNotes: "Should not persist"
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .invalidTreatmentDose, file: file, line: line)
        }

        let after = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        XCTAssertEqual(after.status, before.status, file: file, line: line)
        XCTAssertEqual(after.completedAt, before.completedAt, file: file, line: line)
        XCTAssertEqual(after.treatmentRecords, before.treatmentRecords, file: file, line: line)
        XCTAssertEqual(after.pregnancyCheck, before.pregnancyCheck, file: file, line: line)
        XCTAssertEqual(after.castrationPerformedInSession, before.castrationPerformedInSession, file: file, line: line)
        XCTAssertEqual(after.observationNotes, before.observationNotes, file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().saveEdits(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .done,
                    completedAt: before.completedAt,
                    destinationPastureID: nil,
                    treatmentEntries: [
                        WorkingTreatmentEntryInput(
                            date: date(year: 2026, month: 9, day: 22, hour: 11),
                            treatmentItemID: treatmentID,
                            itemName: "Duplicate Treatment One",
                            given: true,
                            dose: WorkingTreatmentDose(amount: 1, unit: .milliliter)
                        ),
                        WorkingTreatmentEntryInput(
                            date: date(year: 2026, month: 9, day: 22, hour: 11),
                            treatmentItemID: treatmentID,
                            itemName: "Duplicate Treatment Two",
                            given: false,
                            dose: WorkingTreatmentDose(amount: 1, unit: .milliliter)
                        )
                    ],
                    pregnancyCheck: nil,
                    castrationPerformed: false,
                    observationNotes: "Duplicate entries must not persist"
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .duplicateTreatmentItemIdentifiers,
                file: file,
                line: line
            )
        }

        let afterDuplicateFailure = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterDuplicateFailure,
            before,
            "Duplicate treatment-entry identifiers must fail before replacing any durable queue work data.",
            file: file,
            line: line
        )
    }
}


@MainActor
extension WorkingRepositoryContract {
    static func assertCastrationGeneratedHealthRecordCanBeRecordedAndCleared(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Castration Source", using: fixture)
        let animal = try makeAnimal(
            name: "Working Castration Calf",
            tagNumber: "C101",
            sex: .male,
            pastureID: source.id,
            using: fixture
        )
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 9),
                sourcePastureID: source.id,
                treatmentTemplateName: "Castration Contract",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )

        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: true,
            observationNotes: ""
        )

        let recorded = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertTrue(recorded.castrationPerformedInSession, file: file, line: line)
        let castrationCompletedAt = try XCTUnwrap(recorded.completedAt, file: file, line: line)
        XCTAssertTrue(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id).contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.castration.treatmentName
                    && event.details == nil
                    && event.date == castrationCompletedAt
            },
            "Recording castration in Working must create the canonical generated Animal history event.",
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: recorded.completedAt,
                destinationPastureID: recorded.destinationPastureID,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: "   "
            )
        )

        let cleared = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertFalse(cleared.castrationPerformedInSession, file: file, line: line)
        XCTAssertEqual(cleared.completedAt, recorded.completedAt, file: file, line: line)
        XCTAssertFalse(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id).contains { event in
                if case .health = event.type { return true }
                return false
            },
            "Clearing castration in Working must remove the generated session-linked health history.",
            file: file,
            line: line
        )
    }
}


@MainActor
extension WorkingRepositoryContract {
    static func assertQueueEditsCanClearDestinationAndPregnancyCheck(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Clear Source", using: fixture)
        let destination = try makePasture(named: "Working Clear Destination", using: fixture)
        let animal = try makeAnimal(name: "Working Clear Cow", tagNumber: "CL101", sex: .female, pastureID: source.id, using: fixture)
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 30),
                sourcePastureID: source.id,
                treatmentTemplateName: "Optional Clear",
                plannedTreatments: [
                    WorkingTreatmentPlanItem(
                        id: treatmentID,
                        name: "Optional Clear Treatment"
                    )
                ],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id, file: file, line: line)
        let pregnancyDate = date(year: 2026, month: 9, day: 30, hour: 9)
        try repository.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: nil,
                destinationPastureID: destination.id,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: pregnancyDate,
                        treatmentItemID: treatmentID,
                        itemName: "Optional Clear Treatment",
                        given: true,
                        dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                    )
                ],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: pregnancyDate,
                    result: .pregnant,
                    estimatedDaysPregnant: 45,
                    dueDate: date(year: 2027, month: 5, day: 1),
                    sireAnimalID: nil
                ),
                castrationPerformed: false,
                observationNotes: "  Clear this observation later  "
            )
        )

        let populated = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        let completedAt = try XCTUnwrap(populated.completedAt, file: file, line: line)
        XCTAssertEqual(populated.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertEqual(populated.pregnancyCheck?.result, .pregnant, file: file, line: line)
        XCTAssertEqual(populated.treatmentRecords.count, 1, file: file, line: line)
        XCTAssertEqual(populated.treatmentRecords.first?.treatmentItemID, treatmentID, file: file, line: line)
        XCTAssertEqual(populated.observationNotes, "Clear this observation later", file: file, line: line)

        try fixture.makeWorkingRepository().saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: completedAt,
                destinationPastureID: nil,
                treatmentEntries: [],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: pregnancyDate,
                    result: .unknown,
                    estimatedDaysPregnant: nil,
                    dueDate: nil,
                    sireAnimalID: nil
                ),
                castrationPerformed: false,
                observationNotes: ""
            )
        )

        let cleared = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        XCTAssertEqual(cleared.status, .done, file: file, line: line)
        XCTAssertEqual(cleared.completedAt, completedAt, "Clearing optional editor state must not churn an explicitly preserved completion timestamp.", file: file, line: line)
        XCTAssertNil(cleared.destinationPastureID, file: file, line: line)
        let clearedSessionQueue = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(clearedSessionQueue.status, .done, file: file, line: line)
        XCTAssertEqual(clearedSessionQueue.completedAt, completedAt, file: file, line: line)
        XCTAssertNil(
            clearedSessionQueue.destinationPastureID,
            "Clearing an editor destination must clear the same queue destination in session detail.",
            file: file,
            line: line
        )
        XCTAssertNil(cleared.pregnancyCheck, "An unknown pregnancy result represents no persisted Working pregnancy check.", file: file, line: line)
        XCTAssertTrue(cleared.treatmentRecords.isEmpty, "Saving an empty treatment replacement must clear prior Working treatment records.", file: file, line: line)
        XCTAssertEqual(cleared.observationNotes, "", "Blank observation notes must clear the generated observation record.", file: file, line: line)
        XCTAssertFalse(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id).contains { event in
                if case .pregnancy = event.type { return true }
                return false
            },
            "Clearing the Working pregnancy selection must remove the session-linked pregnancy history.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id).contains { event in
                if case .health = event.type { return true }
                return false
            },
            "Blank observation notes must remove the generated session-linked health history.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertQueueEditsRejectInvalidReferencesWithoutPartialReplacement(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Reference Validation Source", using: fixture)
        let animal = try makeAnimal(
            name: "Reference Validation Cow",
            tagNumber: "RV101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 13),
                sourcePastureID: source.id,
                treatmentTemplateName: "Reference Validation",
                plannedTreatments: [
                    WorkingTreatmentPlanItem(
                        id: treatmentID,
                        name: "Reference Validation Treatment"
                    )
                ],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )

        try repository.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: nil,
                destinationPastureID: nil,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: date(year: 2026, month: 10, day: 13, hour: 9),
                        treatmentItemID: treatmentID,
                        itemName: "Reference Validation Treatment",
                        given: true,
                        dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                    )
                ],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: date(year: 2026, month: 10, day: 13, hour: 9, minute: 5),
                    result: .open,
                    estimatedDaysPregnant: nil,
                    dueDate: nil,
                    sireAnimalID: nil
                ),
                castrationPerformed: false,
                observationNotes: "Reference validation baseline"
            )
        )

        let beforeEditor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeTimeline = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().saveEdits(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .inProgress,
                    completedAt: beforeEditor.completedAt,
                    destinationPastureID: UUID(),
                    treatmentEntries: [],
                    pregnancyCheck: nil,
                    castrationPerformed: false,
                    observationNotes: "Invalid destination should not persist"
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .pastureNotFound,
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            beforeEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            beforeTimeline,
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().saveEdits(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .done,
                    completedAt: beforeEditor.completedAt,
                    destinationPastureID: nil,
                    treatmentEntries: [],
                    pregnancyCheck: WorkingPregnancyCheckInput(
                        date: date(year: 2026, month: 10, day: 13, hour: 10),
                        result: .pregnant,
                        estimatedDaysPregnant: 30,
                        dueDate: date(year: 2027, month: 6, day: 1),
                        sireAnimalID: UUID()
                    ),
                    castrationPerformed: false,
                    observationNotes: "Invalid sire should not persist"
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .animalNotFound,
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            beforeEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            beforeTimeline,
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertWorkingPregnancyCheckSurvivesSireDeletion(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Sire Deletion Source", using: fixture)
        let sirePasture = try makePasture(named: "Working Sire Deletion Sire Pasture", using: fixture)
        let cow = try makeAnimal(
            name: "Working Sire Deletion Cow",
            tagNumber: "SD101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let sire = try makeAnimal(
            name: "Working Sire Deletion Bull",
            tagNumber: "SD-B1",
            sex: .male,
            pastureID: sirePasture.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 17),
                sourcePastureID: source.id,
                treatmentTemplateName: "Sire Deletion",
                plannedTreatments: [],
                animalIDs: [cow.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )
        let checkDate = date(year: 2026, month: 10, day: 17, hour: 9)
        let dueDate = date(year: 2027, month: 5, day: 20)

        try repository.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: nil,
                destinationPastureID: nil,
                treatmentEntries: [],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: checkDate,
                    result: .pregnant,
                    estimatedDaysPregnant: 50,
                    dueDate: dueDate,
                    sireAnimalID: sire.id
                ),
                castrationPerformed: false,
                observationNotes: ""
            )
        )

        let beforeDeletion = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(beforeDeletion.pregnancyCheck?.sire?.id, sire.id, file: file, line: line)

        let animalRepository = fixture.makeAnimalRepository()
        try animalRepository.archive(ids: [sire.id])
        try animalRepository.delete(ids: [sire.id])

        let afterDeletion = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        let pregnancy = try XCTUnwrap(afterDeletion.pregnancyCheck, file: file, line: line)
        XCTAssertEqual(pregnancy.date, checkDate, file: file, line: line)
        XCTAssertEqual(pregnancy.result, .pregnant, file: file, line: line)
        XCTAssertEqual(pregnancy.estimatedDaysPregnant, 50, file: file, line: line)
        XCTAssertEqual(pregnancy.dueDate, dueDate, file: file, line: line)
        XCTAssertNil(
            pregnancy.sire,
            "Deleting the referenced sire must nullify only the live sire relationship, not delete the Working pregnancy check.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try fixture.makeAnimalRepository().fetchTimeline(id: cow.id).contains { event in
                if case .pregnancy = event.type { return true }
                return false
            },
            "The cow's Working pregnancy history must survive deletion of the referenced sire.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertDirectQueueCompletionValidationDoesNotMutateQueuedState(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Direct Completion Validation Source", using: fixture)
        let animal = try makeAnimal(
            name: "Direct Completion Validation Cow",
            tagNumber: "DCV101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 27),
                sourcePastureID: source.id,
                treatmentTemplateName: "Direct Completion Validation",
                plannedTreatments: [
                    WorkingTreatmentPlanItem(
                        id: treatmentID,
                        name: "Direct Validation Treatment"
                    )
                ],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )

        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeEditor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        let beforeTimeline = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        )
        XCTAssertEqual(beforeEditor.status, .queued, file: file, line: line)
        XCTAssertNil(beforeEditor.completedAt, file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().complete(
                queueItemID: queueItemID,
                inSessionID: sessionID,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: date(year: 2026, month: 10, day: 27, hour: 9),
                        treatmentItemID: treatmentID,
                        itemName: "Direct Validation Treatment",
                        given: true,
                        dose: WorkingTreatmentDose(amount: -1, unit: .milliliter)
                    )
                ],
                pregnancyCheck: nil,
                markCastrated: false,
                observationNotes: "Must not persist"
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .invalidTreatmentDose, file: file, line: line)
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            beforeEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            beforeTimeline,
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().complete(
                queueItemID: queueItemID,
                inSessionID: sessionID,
                treatmentEntries: [],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: date(year: 2026, month: 10, day: 27, hour: 10),
                    result: .pregnant,
                    estimatedDaysPregnant: 30,
                    dueDate: date(year: 2027, month: 6, day: 1),
                    sireAnimalID: UUID()
                ),
                markCastrated: false,
                observationNotes: "Must not persist"
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .animalNotFound, file: file, line: line)
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            beforeEditor,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            beforeTimeline,
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertQueueWorkDataMutationsRemainScopedToTargetAnimal(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Work Scope Source", using: fixture)
        let first = try makeAnimal(
            name: "Working Work Scope One",
            tagNumber: "WS201",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let second = try makeAnimal(
            name: "Working Work Scope Two",
            tagNumber: "WS202",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let firstTreatmentID = UUID()
        let secondTreatmentID = UUID()

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 29),
                sourcePastureID: source.id,
                treatmentTemplateName: "Work Scope",
                plannedTreatments: [
                    WorkingTreatmentPlanItem(id: firstTreatmentID, name: "First Scoped Treatment"),
                    WorkingTreatmentPlanItem(id: secondTreatmentID, name: "Second Scoped Treatment")
                ],
                animalIDs: [first.id, second.id]
            )
        )
        let started = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let firstQueueID = try XCTUnwrap(
            started.queueItems.first { $0.animalID == first.id }?.id,
            file: file,
            line: line
        )
        let secondQueueID = try XCTUnwrap(
            started.queueItems.first { $0.animalID == second.id }?.id,
            file: file,
            line: line
        )

        try repository.complete(
            queueItemID: firstQueueID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 10, day: 29, hour: 9),
                    treatmentItemID: firstTreatmentID,
                    itemName: "First Scoped Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 1, unit: .milliliter)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: date(year: 2026, month: 10, day: 29, hour: 9, minute: 5),
                result: .open,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            ),
            markCastrated: false,
            observationNotes: "First scoped observation"
        )
        try repository.complete(
            queueItemID: secondQueueID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 10, day: 29, hour: 10),
                    treatmentItemID: secondTreatmentID,
                    itemName: "Second Scoped Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: date(year: 2026, month: 10, day: 29, hour: 10, minute: 5),
                result: .pregnant,
                estimatedDaysPregnant: 40,
                dueDate: date(year: 2027, month: 5, day: 20),
                sireAnimalID: nil
            ),
            markCastrated: false,
            observationNotes: "Second scoped observation"
        )

        let secondBeforeFirstEdit = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: secondQueueID
            ),
            file: file,
            line: line
        )
        let secondTimelineBeforeFirstEdit = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: second.id)
        )

        try fixture.makeWorkingRepository().saveEdits(
            forQueueItemID: firstQueueID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .inProgress,
                completedAt: nil,
                destinationPastureID: nil,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: ""
            )
        )

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: secondQueueID
            ),
            secondBeforeFirstEdit,
            "Replacing one queue Animal's Working children must not touch sibling session-linked work data.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: second.id)),
            secondTimelineBeforeFirstEdit,
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().deleteWorkData(
            forQueueItemID: firstQueueID,
            inSessionID: sessionID
        )

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: secondQueueID
            ),
            secondBeforeFirstEdit,
            "Resetting one queue Animal's Working data must remain scoped by both session and Animal identity.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: second.id)),
            secondTimelineBeforeFirstEdit,
            file: file,
            line: line
        )
    }
}

