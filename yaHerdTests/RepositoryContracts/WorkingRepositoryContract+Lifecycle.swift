import Foundation
import XCTest
@testable import yaHerd

@MainActor
extension WorkingRepositoryContract {
    static func assertAdditionalCollectionPersistsQueueAndAnimalOwnership(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Collection Source", using: fixture)
        let first = try makeAnimal(name: "Collected First", tagNumber: "501", sex: .female, pastureID: source.id, using: fixture)
        let second = try makeAnimal(name: "Collected Second", tagNumber: "502", sex: .male, pastureID: source.id, using: fixture)
        let duplicateInputAnimal = try makeAnimal(name: "Collected Duplicate Input", tagNumber: "503", sex: .female, pastureID: source.id, using: fixture)
        let control = try makeAnimal(name: "Collection Control", tagNumber: "504", sex: .female, pastureID: source.id, using: fixture)

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 23),
                sourcePastureID: source.id,
                treatmentTemplateName: "Collection Contract",
                plannedTreatments: [],
                animalIDs: [first.id]
            )
        )
        let initial = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let initialQueueID = try XCTUnwrap(initial.queueItems.first?.id, file: file, line: line)
        let initialQueue = try XCTUnwrap(
            initial.queueItems.first { $0.id == initialQueueID },
            file: file,
            line: line
        )
        XCTAssertEqual(initial.sourcePastureName, "Working Collection Source", file: file, line: line)
        XCTAssertEqual(initialQueue.collectedFromPastureName, "Working Collection Source", file: file, line: line)

        _ = try fixture.makePastureRepository().update(
            id: source.id,
            input: PastureInput(
                name: "Working Collection Source Renamed",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )

        try repository.collectAnimals(sessionID: sessionID, animalIDs: [second.id])

        let reloaded = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(Set(reloaded.queueItems.compactMap(\.animalID)), Set([first.id, second.id]), file: file, line: line)
        XCTAssertTrue(reloaded.queueItems.contains { $0.id == initialQueueID && $0.animalID == first.id }, "Existing queue identity must survive later collection.", file: file, line: line)
        let secondQueue = try XCTUnwrap(reloaded.queueItems.first { $0.animalID == second.id }, file: file, line: line)
        XCTAssertNotEqual(secondQueue.id, initialQueueID, file: file, line: line)
        XCTAssertEqual(secondQueue.status, .queued, file: file, line: line)
        XCTAssertEqual(secondQueue.animalName, "Collected Second", file: file, line: line)
        XCTAssertEqual(secondQueue.collectedFromPastureID, source.id, file: file, line: line)
        XCTAssertEqual(
            secondQueue.collectedFromPastureName,
            "Working Collection Source Renamed",
            "Each queue item captures the live source-pasture name at the time that animal is collected.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded.sourcePastureName,
            "Working Collection Source",
            "The session source-name snapshot remains the name captured when the session started.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded.queueItems.first { $0.id == initialQueueID }?.collectedFromPastureName,
            "Working Collection Source",
            "Earlier queue-item collected-from history must not be rewritten by a later live pasture rename.",
            file: file,
            line: line
        )

        let collectedAnimal = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), file: file, line: line)
        XCTAssertNil(collectedAnimal.pastureID, file: file, line: line)
        XCTAssertEqual(collectedAnimal.location, .workingPen, file: file, line: line)
        let controlAnimal = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: control.id), file: file, line: line)
        XCTAssertEqual(controlAnimal.pastureID, source.id, file: file, line: line)
        XCTAssertEqual(controlAnimal.location, .pasture, file: file, line: line)

        try fixture.makeWorkingRepository().collectAnimals(
            sessionID: sessionID,
            animalIDs: [duplicateInputAnimal.id, duplicateInputAnimal.id]
        )
        let afterDuplicateInput = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterDuplicateInput.queueItems.filter { $0.animalID == duplicateInputAnimal.id }.count,
            1,
            "Duplicate IDs within one collection request normalize to one queue row.",
            file: file,
            line: line
        )
        let duplicateInputAnimalAfter = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: duplicateInputAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(duplicateInputAnimalAfter.location, .workingPen, file: file, line: line)
        XCTAssertNil(duplicateInputAnimalAfter.pastureID, file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().collectAnimals(sessionID: sessionID, animalIDs: [second.id]),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateAnimalCollection, file: file, line: line)
        }
        let afterDuplicateFailure = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(afterDuplicateFailure.queueItems.map(\.id)),
            Set(afterDuplicateInput.queueItems.map(\.id)),
            "A later duplicate-collection failure must not remove the queue row created by the normalized duplicate-input batch.",
            file: file,
            line: line
        )
    }

    static func assertSessionCompletionMovesAnimalsAndReopenPreservesCompletedState(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Finish Source", using: fixture)
        let destination = try makePasture(named: "Working Finish Destination", using: fixture)
        let first = try makeAnimal(name: "Finish One", tagNumber: "601", sex: .female, pastureID: source.id, using: fixture)
        let second = try makeAnimal(name: "Finish Two", tagNumber: "602", sex: .male, pastureID: source.id, using: fixture)

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 24),
                sourcePastureID: source.id,
                treatmentTemplateName: "Finish Contract",
                plannedTreatments: [],
                animalIDs: [first.id, second.id]
            )
        )
        let started = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let firstQueue = try XCTUnwrap(started.queueItems.first { $0.animalID == first.id }, file: file, line: line)
        let secondQueue = try XCTUnwrap(started.queueItems.first { $0.animalID == second.id }, file: file, line: line)

        try repository.complete(
            queueItemID: firstQueue.id,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )
        try repository.complete(
            queueItemID: secondQueue.id,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )

        let beforeInvalidFinish = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().completeSession(
                id: sessionID,
                assignments: [
                    WorkingQueueDestinationAssignment(queueItemID: firstQueue.id, destinationPastureID: destination.id),
                    WorkingQueueDestinationAssignment(queueItemID: firstQueue.id, destinationPastureID: nil)
                ]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateQueueItemAssignments, file: file, line: line)
        }
        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().completeSession(
                id: sessionID,
                assignments: [
                    WorkingQueueDestinationAssignment(queueItemID: firstQueue.id, destinationPastureID: destination.id)
                ]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .assignmentSetDoesNotMatchSession, file: file, line: line)
        }
        let afterInvalidFinish = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertEqual(afterInvalidFinish, beforeInvalidFinish, "Assignment validation failures must not mutate the session.", file: file, line: line)
        for animalID in [first.id, second.id] {
            let animal = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: animalID), file: file, line: line)
            XCTAssertNil(animal.pastureID, file: file, line: line)
            XCTAssertEqual(animal.location, .workingPen, file: file, line: line)
        }

        _ = try fixture.makePastureRepository().update(
            id: source.id,
            input: PastureInput(
                name: "Working Finish Source Renamed",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try fixture.makePastureRepository().update(
            id: destination.id,
            input: PastureInput(
                name: "Working Finish Destination Renamed",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )

        let beforeFinishAfterRename = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            beforeFinishAfterRename.sourcePastureName,
            "Working Finish Source",
            "Renaming the live source pasture during an active session must not rewrite the session's captured source name.",
            file: file,
            line: line
        )
        let summaryBeforeFinishAfterRename = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            summaryBeforeFinishAfterRename.sourcePastureName,
            "Working Finish Source",
            "Working session list history uses the same start-time source-name snapshot as detail.",
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(queueItemID: firstQueue.id, destinationPastureID: destination.id),
                WorkingQueueDestinationAssignment(queueItemID: secondQueue.id, destinationPastureID: nil)
            ]
        )

        let finished = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertEqual(finished.status, .finished, file: file, line: line)
        XCTAssertEqual(finished.queueItems.first { $0.id == firstQueue.id }?.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertEqual(
            finished.queueItems.first { $0.id == firstQueue.id }?.destinationPastureName,
            "Working Finish Destination Renamed",
            "The final destination name snapshot is captured when finish resolves and commits the live destination.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            finished.queueItems.first { $0.id == secondQueue.id }?.destinationPastureID,
            source.id,
            "A nil completion assignment means return to the session source pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            finished.queueItems.first { $0.id == secondQueue.id }?.destinationPastureName,
            "Working Finish Source Renamed",
            "Source fallback uses the live source pasture at finish time for the final destination snapshot while retaining the session's original source-name history.",
            file: file,
            line: line
        )

        let firstFinished = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id), file: file, line: line)
        XCTAssertEqual(firstFinished.pastureID, destination.id, file: file, line: line)
        XCTAssertEqual(firstFinished.pastureName, "Working Finish Destination Renamed", file: file, line: line)
        XCTAssertEqual(firstFinished.location, .pasture, file: file, line: line)
        let secondFinished = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), file: file, line: line)
        XCTAssertEqual(
            secondFinished.pastureID,
            source.id,
            "A nil completion assignment returns the animal to the session source pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(secondFinished.pastureName, "Working Finish Source Renamed", file: file, line: line)
        XCTAssertEqual(secondFinished.location, .pasture, file: file, line: line)

        let firstTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: first.id)
        XCTAssertTrue(
            firstTimeline.contains { event in
                guard case .movement = event.type else { return false }
                return event.details == "Working Finish Source → Working Finish Destination Renamed"
            },
            "Working completion movement history uses the queue's collected-from snapshot for the origin and the live destination name committed at finish time.",
            file: file,
            line: line
        )
        let secondTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: second.id)
        XCTAssertTrue(
            secondTimeline.contains { event in
                guard case .movement = event.type else { return false }
                return event.details == "Working Finish Source → Working Finish Source Renamed"
            },
            "Source fallback keeps the original collected-from name as movement origin while using the renamed live source as the committed destination.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().completeSession(
                id: sessionID,
                assignments: [
                    WorkingQueueDestinationAssignment(queueItemID: firstQueue.id, destinationPastureID: destination.id),
                    WorkingQueueDestinationAssignment(queueItemID: secondQueue.id, destinationPastureID: nil)
                ]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .sessionAlreadyFinished, file: file, line: line)
        }

        try fixture.makeWorkingRepository().reopenSession(id: sessionID)
        let reopened = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertEqual(reopened.status, .active, file: file, line: line)
        XCTAssertEqual(reopened.queueItems.first { $0.id == firstQueue.id }?.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertEqual(reopened.queueItems.first { $0.id == secondQueue.id }?.status, .done, file: file, line: line)
        XCTAssertEqual(reopened.queueItems.first { $0.id == secondQueue.id }?.destinationPastureID, source.id, file: file, line: line)
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id)?.pastureID, destination.id, "Reopening is an editing lifecycle transition; it must not recollect animals that were already returned.", file: file, line: line)
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id)?.location, .pasture, file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().reopenSession(id: sessionID),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .sessionAlreadyActive, file: file, line: line)
        }
    }

    static func assertDeletingActiveSessionRestoresAnimalsAndRemovesSessionWorkData(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Delete Source", using: fixture)
        let provisionalDestination = try makePasture(
            named: "Working Delete Provisional Destination",
            using: fixture
        )
        let animal = try makeAnimal(name: "Delete Session Cow", tagNumber: "701", sex: .female, pastureID: source.id, using: fixture)
        let secondAnimal = try makeAnimal(
            name: "Delete Session Second Cow",
            tagNumber: "702",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let independentHealthDate = date(year: 2026, month: 9, day: 23, hour: 8)
        let independentPregnancyDate = date(year: 2026, month: 9, day: 24, hour: 8)
        let animalRepository = fixture.makeAnimalRepository()
        _ = try animalRepository.addHealthRecord(
            animalID: animal.id,
            input: HealthRecordInput(
                date: independentHealthDate,
                treatment: "Independent pre-session health",
                notes: "Must survive Working session deletion"
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
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 25),
                sourcePastureID: source.id,
                treatmentTemplateName: "Delete Contract",
                plannedTreatments: [WorkingTreatmentPlanItem(id: treatmentID, name: "Delete Vaccine")],
                animalIDs: [animal.id, secondAnimal.id]
            )
        )
        let startedDeleteSession = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let queueItemID = try XCTUnwrap(
            startedDeleteSession.queueItems.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        let secondQueueItemID = try XCTUnwrap(
            startedDeleteSession.queueItems.first { $0.animalID == secondAnimal.id }?.id,
            file: file,
            line: line
        )
        try repository.saveEdits(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: nil,
                destinationPastureID: provisionalDestination.id,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: date(year: 2026, month: 9, day: 25, hour: 9),
                        treatmentItemID: treatmentID,
                        itemName: "Delete Vaccine",
                        given: true,
                        dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                    )
                ],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: date(year: 2026, month: 9, day: 25, hour: 9, minute: 5),
                    result: .open,
                    estimatedDaysPregnant: nil,
                    dueDate: nil,
                    sireAnimalID: nil
                ),
                castrationPerformed: false,
                observationNotes: "Temporary session observation"
            )
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.id == queueItemID }?.destinationPastureID,
            provisionalDestination.id,
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().complete(
            queueItemID: secondQueueItemID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 9, day: 25, hour: 10),
                    treatmentItemID: treatmentID,
                    itemName: "Delete Vaccine",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 1, unit: .milliliter)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: date(year: 2026, month: 9, day: 25, hour: 10, minute: 5),
                result: .open,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            ),
            markCastrated: false,
            observationNotes: "Second queue Working observation"
        )

        let beforeDeleteTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(
            beforeDeleteTimeline.contains { event in
                guard case .health = event.type else { return false }
                return event.title == "Independent pre-session health"
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            beforeDeleteTimeline.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            beforeDeleteTimeline.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == independentPregnancyDate
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            beforeDeleteTimeline.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == date(year: 2026, month: 9, day: 25, hour: 9, minute: 5)
            },
            file: file,
            line: line
        )
        let secondBeforeDeleteTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: secondAnimal.id)
        XCTAssertTrue(
            secondBeforeDeleteTimeline.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
                    && event.details == "Second queue Working observation"
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            secondBeforeDeleteTimeline.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == date(year: 2026, month: 9, day: 25, hour: 10, minute: 5)
            },
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().deleteSession(id: sessionID)

        let reloadedWorking = fixture.makeWorkingRepository()
        XCTAssertNil(try reloadedWorking.fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertFalse(try reloadedWorking.fetchSessions().contains { $0.id == sessionID }, file: file, line: line)
        XCTAssertNil(
            try reloadedWorking.fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        XCTAssertNil(
            try reloadedWorking.fetchQueueItemEditor(sessionID: sessionID, queueItemID: secondQueueItemID),
            file: file,
            line: line
        )

        let restored = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id), file: file, line: line)
        XCTAssertEqual(
            restored.pastureID,
            source.id,
            "Deleting an active session must restore the collected/source pasture, not a provisional queue destination.",
            file: file,
            line: line
        )
        XCTAssertEqual(restored.pastureName, "Working Delete Source", file: file, line: line)
        XCTAssertNotEqual(restored.pastureID, provisionalDestination.id, file: file, line: line)
        XCTAssertEqual(restored.location, .pasture, file: file, line: line)

        let secondRestored = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: secondAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(secondRestored.pastureID, source.id, file: file, line: line)
        XCTAssertEqual(secondRestored.pastureName, "Working Delete Source", file: file, line: line)
        XCTAssertEqual(secondRestored.location, .pasture, file: file, line: line)

        let afterDeleteTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(
            afterDeleteTimeline.contains { event in
                guard case .health = event.type else { return false }
                return event.date == independentHealthDate
                    && event.title == "Independent pre-session health"
                    && event.details == "Must survive Working session deletion"
            },
            "Deleting an active Working session must preserve unrelated standalone health history.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            afterDeleteTimeline.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
            },
            "Deleting an active Working session must remove only its generated health records.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            afterDeleteTimeline.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == independentPregnancyDate
                    && event.title == "Pregnancy Check: Open"
            },
            "Deleting an active Working session must preserve unrelated standalone pregnancy history.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            afterDeleteTimeline.contains { event in
                guard case .pregnancy = event.type else { return false }
                return event.date == date(year: 2026, month: 9, day: 25, hour: 9, minute: 5)
            },
            "Deleting an active Working session must remove only its session-linked pregnancy checks.",
            file: file,
            line: line
        )
        let animalSummaryAfterDelete = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimals().first { $0.id == animal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(animalSummaryAfterDelete.lastPregnancyCheckDate, independentPregnancyDate, file: file, line: line)
        XCTAssertEqual(animalSummaryAfterDelete.lastPregnancyStatus, .open, file: file, line: line)

        let secondAfterDeleteTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: secondAnimal.id)
        XCTAssertFalse(
            secondAfterDeleteTimeline.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
            },
            "Deleting one Working session must clean generated health children for every queue Animal in that session.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            secondAfterDeleteTimeline.contains { event in
                if case .pregnancy = event.type { return true }
                return false
            },
            "Deleting one Working session must clean session-linked pregnancy children for every queue Animal in that session.",
            file: file,
            line: line
        )
    }
}


@MainActor
extension WorkingRepositoryContract {
    static func assertInvalidCompletionDestinationDoesNotMoveAnyAnimal(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Destination Validation Source", using: fixture)
        let validDestination = try makePasture(named: "Working Destination Validation Target", using: fixture)
        let first = try makeAnimal(name: "Destination Validation One", tagNumber: "DV101", sex: .female, pastureID: source.id, using: fixture)
        let second = try makeAnimal(name: "Destination Validation Two", tagNumber: "DV102", sex: .male, pastureID: source.id, using: fixture)
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 28),
                sourcePastureID: source.id,
                treatmentTemplateName: "Destination Validation",
                plannedTreatments: [],
                animalIDs: [first.id, second.id]
            )
        )
        let beforeSession = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let firstQueueID = try XCTUnwrap(beforeSession.queueItems.first { $0.animalID == first.id }?.id, file: file, line: line)
        let secondQueueID = try XCTUnwrap(beforeSession.queueItems.first { $0.animalID == second.id }?.id, file: file, line: line)
        let beforeFirst = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id), file: file, line: line)
        let beforeSecond = try XCTUnwrap(fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), file: file, line: line)
        let beforeFirstTimeline = Set(try fixture.makeAnimalRepository().fetchTimeline(id: first.id))
        let beforeSecondTimeline = Set(try fixture.makeAnimalRepository().fetchTimeline(id: second.id))

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().completeSession(
                id: sessionID,
                assignments: [
                    WorkingQueueDestinationAssignment(queueItemID: firstQueueID, destinationPastureID: validDestination.id),
                    WorkingQueueDestinationAssignment(queueItemID: secondQueueID, destinationPastureID: UUID())
                ]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .pastureNotFound, file: file, line: line)
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "Destination resolution must complete before any queue destination or movement is committed.",
            file: file,
            line: line
        )
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: first.id), beforeFirst, file: file, line: line)
        XCTAssertEqual(try fixture.makeAnimalRepository().fetchAnimalDetail(id: second.id), beforeSecond, file: file, line: line)
        XCTAssertEqual(Set(try fixture.makeAnimalRepository().fetchTimeline(id: first.id)), beforeFirstTimeline, file: file, line: line)
        XCTAssertEqual(Set(try fixture.makeAnimalRepository().fetchTimeline(id: second.id)), beforeSecondTimeline, file: file, line: line)
    }

    static func assertDeletingFinishedSessionLeavesReturnedAnimalsAtDestination(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Finished Delete Source", using: fixture)
        let destination = try makePasture(named: "Working Finished Delete Destination", using: fixture)
        let animal = try makeAnimal(name: "Finished Delete Cow", tagNumber: "FD201", sex: .female, pastureID: source.id, using: fixture)
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 29),
                sourcePastureID: source.id,
                treatmentTemplateName: "Finished Delete",
                plannedTreatments: [WorkingTreatmentPlanItem(id: treatmentID, name: "Finished Delete Treatment")],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id, file: file, line: line)
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 9, day: 29, hour: 9),
                    treatmentItemID: treatmentID,
                    itemName: "Finished Delete Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: date(year: 2026, month: 9, day: 29, hour: 9, minute: 5),
                result: .open,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            ),
            markCastrated: false,
            observationNotes: "Finished delete observation"
        )
        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(queueItemID: queueItemID, destinationPastureID: destination.id)
            ]
        )

        let finishedAnimal = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(finishedAnimal.pastureID, destination.id, file: file, line: line)
        XCTAssertEqual(finishedAnimal.location, .pasture, file: file, line: line)
        let timelineBeforeDelete = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(timelineBeforeDelete.contains { event in
            if case .movement = event.type { return true }
            return false
        }, file: file, line: line)
        XCTAssertTrue(timelineBeforeDelete.contains { event in
            if case .health = event.type { return true }
            return false
        }, file: file, line: line)
        XCTAssertTrue(timelineBeforeDelete.contains { event in
            if case .pregnancy = event.type { return true }
            return false
        }, file: file, line: line)

        try fixture.makeWorkingRepository().deleteSession(id: sessionID)

        XCTAssertNil(try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        let afterDelete = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(afterDelete.pastureID, destination.id, "Deleting historical Working data must not move an animal that was already returned from the working pen.", file: file, line: line)
        XCTAssertEqual(afterDelete.location, .pasture, file: file, line: line)

        let timelineAfterDelete = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(timelineAfterDelete.contains { event in
            if case .movement = event.type { return true }
            return false
        }, "Deleting a finished session must not erase the independent animal movement history.", file: file, line: line)
        XCTAssertFalse(timelineAfterDelete.contains { event in
            if case .health = event.type { return true }
            return false
        }, "Session-linked generated health records are deleted with the finished session.", file: file, line: line)
        XCTAssertFalse(timelineAfterDelete.contains { event in
            if case .pregnancy = event.type { return true }
            return false
        }, "Session-linked pregnancy checks are deleted with the finished session.", file: file, line: line)
    }
}


@MainActor
extension WorkingRepositoryContract {
    static func assertFinishedSessionLocksWorkingMutationsUntilReopened(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Lock Source", using: fixture)
        let animal = try makeAnimal(name: "Locked Session Cow", tagNumber: "L901", sex: .female, pastureID: source.id, using: fixture)
        let collectionCandidate = try makeAnimal(name: "Locked Candidate", tagNumber: "L902", sex: .female, pastureID: source.id, using: fixture)
        let treatment = WorkingTreatmentPlanItem(id: UUID(), name: "Lock Treatment")
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 27),
                sourcePastureID: source.id,
                treatmentTemplateName: "Lifecycle Lock",
                plannedTreatments: [treatment],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id, file: file, line: line)
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )
        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(queueItemID: queueItemID, destinationPastureID: source.id)
            ]
        )

        let finished = try XCTUnwrap(fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID), file: file, line: line)
        XCTAssertEqual(finished.status, .finished, file: file, line: line)
        let editor = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )

        try assertSessionAlreadyFinished(file: file, line: line) {
            try fixture.makeWorkingRepository().collectAnimals(
                sessionID: sessionID,
                animalIDs: [collectionCandidate.id]
            )
        }
        try assertSessionAlreadyFinished(file: file, line: line) {
            try fixture.makeWorkingRepository().complete(
                queueItemID: queueItemID,
                inSessionID: sessionID,
                treatmentEntries: [],
                pregnancyCheck: nil,
                markCastrated: false,
                observationNotes: "Should not persist"
            )
        }
        try assertSessionAlreadyFinished(file: file, line: line) {
            try fixture.makeWorkingRepository().saveEdits(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .queued,
                    completedAt: nil,
                    destinationPastureID: nil,
                    treatmentEntries: [],
                    pregnancyCheck: nil,
                    castrationPerformed: false,
                    observationNotes: "Should not persist"
                )
            )
        }
        try assertSessionAlreadyFinished(file: file, line: line) {
            try fixture.makeWorkingRepository().deleteWorkData(
                forQueueItemID: queueItemID,
                inSessionID: sessionID
            )
        }
        try assertSessionAlreadyFinished(file: file, line: line) {
            try fixture.makeWorkingRepository().updateSessionTreatments(
                id: sessionID,
                plannedTreatments: [WorkingTreatmentPlanItem(id: treatment.id, name: "Should Not Persist")]
            )
        }
        try assertSessionAlreadyFinished(file: file, line: line) {
            _ = try fixture.makeWorkingRepository().replacePrimaryTag(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingTagReplacementInput(number: "L999", colorID: nil)
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            finished,
            "Finished-session mutation failures must not modify session state.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            editor,
            file: file,
            line: line
        )
        let untouchedCandidate = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: collectionCandidate.id),
            file: file,
            line: line
        )
        XCTAssertEqual(untouchedCandidate.pastureID, source.id, file: file, line: line)
        XCTAssertEqual(untouchedCandidate.location, .pasture, file: file, line: line)

        try fixture.makeWorkingRepository().reopenSession(id: sessionID)
        let reopenedTreatment = WorkingTreatmentPlanItem(id: treatment.id, name: "Editable After Reopen")
        try fixture.makeWorkingRepository().updateSessionTreatments(
            id: sessionID,
            plannedTreatments: [reopenedTreatment]
        )
        let reopened = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(reopened.status, .active, file: file, line: line)
        XCTAssertEqual(reopened.plannedTreatments, [reopenedTreatment], "Reopening restores the active editing lifecycle without recollecting animals.", file: file, line: line)
    }

    private static func assertSessionAlreadyFinished(
        file: StaticString,
        line: UInt,
        operation: () throws -> Void
    ) throws {
        XCTAssertThrowsError(
            try operation(),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .sessionAlreadyFinished, file: file, line: line)
        }
    }
}

@MainActor
extension WorkingRepositoryContract {
    /// Target Core Data transaction behavior for selections that became stale after the collection
    /// screen loaded. The current SwiftData implementation does not enforce these repository-level
    /// eligibility checks and intentionally has no runner for this permanent target contract.
    static func assertCollectionRejectsStaleBatchWithoutPartialMutation(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Stale Collection Source", using: fixture)
        let other = try makePasture(named: "Working Stale Collection Other", using: fixture)
        let existing = try makeAnimal(
            name: "Stale Collection Existing",
            tagNumber: "SC100",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let validCandidate = try makeAnimal(
            name: "Stale Collection Valid",
            tagNumber: "SC101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let staleCandidate = try makeAnimal(
            name: "Stale Collection Moved",
            tagNumber: "SC102",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let archivedCandidate = try makeAnimal(
            name: "Stale Collection Archived",
            tagNumber: "SC103",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let reownedCandidate = try makeAnimal(
            name: "Stale Collection Reowned",
            tagNumber: "SC104",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 12),
                sourcePastureID: source.id,
                treatmentTemplateName: "Stale Collection",
                plannedTreatments: [],
                animalIDs: [existing.id]
            )
        )
        let otherSessionID = try fixture.makeWorkingRepository().startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 12),
                sourcePastureID: source.id,
                treatmentTemplateName: "Stale Collection Other Session",
                plannedTreatments: [],
                animalIDs: [reownedCandidate.id]
            )
        )

        try fixture.makeAnimalRepository().move(
            ids: [staleCandidate.id],
            toPastureID: other.id
        )
        try fixture.makeAnimalRepository().archive(ids: [archivedCandidate.id])

        let beforeSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeValid = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: validCandidate.id),
            file: file,
            line: line
        )
        let beforeStale = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: staleCandidate.id),
            file: file,
            line: line
        )
        let beforeArchived = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: archivedCandidate.id),
            file: file,
            line: line
        )
        let beforeReowned = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: reownedCandidate.id),
            file: file,
            line: line
        )
        let otherSessionBeforeConflict = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: otherSessionID),
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().collectAnimals(
                sessionID: sessionID,
                animalIDs: [validCandidate.id, reownedCandidate.id]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .animalAlreadyInAnotherSession,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "A collection batch containing an Animal claimed by another Working session must reject before collecting any valid sibling.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: otherSessionID),
            otherSessionBeforeConflict,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: validCandidate.id),
            beforeValid,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: reownedCandidate.id),
            beforeReowned,
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().collectAnimals(
                sessionID: sessionID,
                animalIDs: [validCandidate.id, staleCandidate.id]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .animalNotEligibleForCollection,
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "A stale collection selection must fail as one transaction before any valid sibling is collected.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: validCandidate.id),
            beforeValid,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: staleCandidate.id),
            beforeStale,
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().collectAnimals(
                sessionID: sessionID,
                animalIDs: [validCandidate.id, archivedCandidate.id]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .animalNotEligibleForCollection,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "An archived stale selection must fail before collecting any still-valid sibling.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: validCandidate.id),
            beforeValid,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: archivedCandidate.id),
            beforeArchived,
            file: file,
            line: line
        )

        let missingAnimalID = UUID()
        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().collectAnimals(
                sessionID: sessionID,
                animalIDs: [validCandidate.id, missingAnimalID]
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
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            beforeSession,
            "A mixed valid/missing collection batch must not partially collect the valid animal.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: validCandidate.id),
            beforeValid,
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertStaleSessionCannotStealAnimalFromNewerWorkingSession(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let firstSource = try makePasture(named: "Working Ownership First Source", using: fixture)
        let secondSource = try makePasture(named: "Working Ownership Second Source", using: fixture)
        let finalDestination = try makePasture(named: "Working Ownership Final Destination", using: fixture)
        let animal = try makeAnimal(
            name: "Working Reowned Cow",
            tagNumber: "OW101",
            sex: .female,
            pastureID: firstSource.id,
            using: fixture
        )

        let firstRepository = fixture.makeWorkingRepository()
        let firstSessionID = try firstRepository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 19),
                sourcePastureID: firstSource.id,
                treatmentTemplateName: "First Ownership",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let firstQueueItemID = try XCTUnwrap(
            firstRepository.fetchSessionDetail(id: firstSessionID)?
                .queueItems.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )

        // Normal herd movement releases the animal from the first active Working ownership.
        try fixture.makeAnimalRepository().move(
            ids: [animal.id],
            toPastureID: secondSource.id
        )

        let secondRepository = fixture.makeWorkingRepository()
        let secondSessionID = try secondRepository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 20),
                sourcePastureID: secondSource.id,
                treatmentTemplateName: "Second Ownership",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let secondBeforeConflict = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: secondSessionID),
            file: file,
            line: line
        )
        let animalBeforeConflict = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        let timelineBeforeConflict = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        )
        XCTAssertEqual(animalBeforeConflict.location, .workingPen, file: file, line: line)
        XCTAssertNil(animalBeforeConflict.pastureID, file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().completeSession(
                id: firstSessionID,
                assignments: [
                    WorkingQueueDestinationAssignment(
                        queueItemID: firstQueueItemID,
                        destinationPastureID: finalDestination.id
                    )
                ]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .animalAlreadyInAnotherSession,
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: secondSessionID),
            secondBeforeConflict,
            "A stale session completion attempt must not mutate the newer Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            animalBeforeConflict,
            "A stale session completion attempt must not move an animal owned by another Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            timelineBeforeConflict,
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().deleteSession(id: firstSessionID)

        XCTAssertNil(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: secondSessionID),
            secondBeforeConflict,
            "Deleting the stale first session must not delete or rewrite the newer session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            animalBeforeConflict,
            "Deleting the stale first session must not restore or relocate an animal currently owned by a newer Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)),
            timelineBeforeConflict,
            "Deleting the stale session must not write a movement for an animal it no longer owns.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertCompletionUsesCurrentPastureWhenAnimalWasReleasedFromWorkingOwnership(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Released Source", using: fixture)
        let interim = try makePasture(named: "Working Released Interim", using: fixture)
        let destination = try makePasture(named: "Working Released Destination", using: fixture)
        let animal = try makeAnimal(
            name: "Working Released Cow",
            tagNumber: "RL101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 21),
                sourcePastureID: source.id,
                treatmentTemplateName: "Released Ownership Completion",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )

        try fixture.makeAnimalRepository().move(
            ids: [animal.id],
            toPastureID: interim.id
        )
        let released = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(released.location, .pasture, file: file, line: line)
        XCTAssertEqual(released.pastureID, interim.id, file: file, line: line)
        let timelineBeforeFinish = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        )

        try fixture.makeWorkingRepository().completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItemID,
                    destinationPastureID: destination.id
                )
            ]
        )

        let finished = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(finished.status, .finished, file: file, line: line)
        XCTAssertEqual(
            finished.queueItems.first { $0.id == queueItemID }?.destinationPastureID,
            destination.id,
            file: file,
            line: line
        )

        let moved = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(moved.location, .pasture, file: file, line: line)
        XCTAssertEqual(moved.pastureID, destination.id, file: file, line: line)
        XCTAssertEqual(moved.pastureName, "Working Released Destination", file: file, line: line)

        let timelineAfterFinish = Set(
            try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        )
        XCTAssertTrue(
            timelineBeforeFinish.isSubset(of: timelineAfterFinish),
            "Finishing after external release must preserve the earlier movement out of Working ownership.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            timelineAfterFinish.contains { event in
                guard case .movement = event.type else { return false }
                return event.details.contains("Working Released Interim")
                    && event.details.contains("Working Released Destination")
            },
            "When an animal is no longer in the working pen and has no conflicting Working owner, completion must move from its current pasture to the assigned destination.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    /// Target Core Data behavior for an active queue item whose live Animal was permanently deleted.
    /// Session detail/finish still expose the historical row from captured queue snapshots and allow
    /// the session to finish, while the animal-work editor is unavailable because no live Animal remains.
    static func assertFinishPersistsMissingAnimalQueueHistory(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Missing Animal Source", using: fixture)
        let destination = try makePasture(named: "Working Missing Animal Destination", using: fixture)
        let animal = try makeAnimal(
            name: "Working Missing Animal Cow",
            tagNumber: "MA101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 22),
                sourcePastureID: source.id,
                treatmentTemplateName: "Missing Animal Finish",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let beforeDelete = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let queueItem = try XCTUnwrap(beforeDelete.queueItems.first, file: file, line: line)
        XCTAssertEqual(queueItem.status, .queued, file: file, line: line)
        XCTAssertEqual(queueItem.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(queueItem.animalName, "Working Missing Animal Cow", file: file, line: line)
        XCTAssertEqual(queueItem.collectedFromPastureID, source.id, file: file, line: line)

        let animalRepository = fixture.makeAnimalRepository()
        try animalRepository.archive(ids: [animal.id])
        try animalRepository.delete(ids: [animal.id])
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )

        let orphaned = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            "Hard deletion must not remove the captured Working queue history needed to finish the session.",
            file: file,
            line: line
        )
        let orphanedQueue = try XCTUnwrap(
            orphaned.queueItems.first { $0.id == queueItem.id },
            file: file,
            line: line
        )
        XCTAssertNil(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItem.id
            ),
            "A historical queue row with no live Animal remains finishable/readable through session detail but must not expose a writable animal-work editor.",
            file: file,
            line: line
        )
        XCTAssertEqual(orphanedQueue.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(orphanedQueue.animalName, "Working Missing Animal Cow", file: file, line: line)
        XCTAssertEqual(orphanedQueue.animalDisplayTagNumber, "MA101", file: file, line: line)
        XCTAssertEqual(orphanedQueue.animalSex, .female, file: file, line: line)
        XCTAssertEqual(orphanedQueue.collectedFromPastureID, source.id, file: file, line: line)
        XCTAssertEqual(orphanedQueue.collectedFromPastureName, "Working Missing Animal Source", file: file, line: line)

        try fixture.makeWorkingRepository().completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItem.id,
                    destinationPastureID: destination.id
                )
            ]
        )

        let finished = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(finished.status, .finished, file: file, line: line)
        let finishedQueue = try XCTUnwrap(
            finished.queueItems.first { $0.id == queueItem.id },
            file: file,
            line: line
        )
        XCTAssertEqual(
            finishedQueue.status,
            .queued,
            "Finishing with an unworked/missing animal must preserve its queue work status.",
            file: file,
            line: line
        )
        XCTAssertNil(finishedQueue.completedAt, file: file, line: line)
        XCTAssertEqual(finishedQueue.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(finishedQueue.animalName, "Working Missing Animal Cow", file: file, line: line)
        XCTAssertEqual(finishedQueue.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertEqual(
            finishedQueue.destinationPastureName,
            "Working Missing Animal Destination",
            "Destination history must persist even though there is no live Animal to move.",
            file: file,
            line: line
        )

        let summary = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.status, .finished, file: file, line: line)
        XCTAssertEqual(summary.totalQueueItems, 1, file: file, line: line)
        XCTAssertEqual(summary.completedQueueItems, 0, file: file, line: line)
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertFinishAllowsUnworkedAnimalsAndPreservesQueueStatus(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Unworked Finish Source", using: fixture)
        let destination = try makePasture(named: "Working Unworked Finish Destination", using: fixture)
        let workedAnimal = try makeAnimal(
            name: "Worked Finish Cow",
            tagNumber: "UF101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let unworkedAnimal = try makeAnimal(
            name: "Unworked Finish Cow",
            tagNumber: "UF102",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 23),
                sourcePastureID: source.id,
                treatmentTemplateName: "Finish With Unworked",
                plannedTreatments: [],
                animalIDs: [workedAnimal.id, unworkedAnimal.id]
            )
        )
        let started = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let workedQueueID = try XCTUnwrap(
            started.queueItems.first { $0.animalID == workedAnimal.id }?.id,
            file: file,
            line: line
        )
        let unworkedQueueID = try XCTUnwrap(
            started.queueItems.first { $0.animalID == unworkedAnimal.id }?.id,
            file: file,
            line: line
        )

        try repository.complete(
            queueItemID: workedQueueID,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )

        try fixture.makeWorkingRepository().completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: workedQueueID,
                    destinationPastureID: destination.id
                ),
                WorkingQueueDestinationAssignment(
                    queueItemID: unworkedQueueID,
                    destinationPastureID: nil
                )
            ]
        )

        let finished = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(finished.status, .finished, file: file, line: line)

        let workedQueue = try XCTUnwrap(
            finished.queueItems.first { $0.id == workedQueueID },
            file: file,
            line: line
        )
        XCTAssertEqual(workedQueue.status, .done, file: file, line: line)
        XCTAssertNotNil(workedQueue.completedAt, file: file, line: line)
        XCTAssertEqual(workedQueue.destinationPastureID, destination.id, file: file, line: line)

        let unworkedQueue = try XCTUnwrap(
            finished.queueItems.first { $0.id == unworkedQueueID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            unworkedQueue.status,
            .queued,
            "Finishing a session with an unworked animal must preserve the historical Not Worked state.",
            file: file,
            line: line
        )
        XCTAssertNil(unworkedQueue.completedAt, file: file, line: line)
        XCTAssertEqual(
            unworkedQueue.destinationPastureID,
            source.id,
            "A nil finish assignment still returns an unworked live animal to the source pasture.",
            file: file,
            line: line
        )

        let workedDetail = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: workedAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(workedDetail.pastureID, destination.id, file: file, line: line)

        let unworkedDetail = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: unworkedAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(unworkedDetail.pastureID, source.id, file: file, line: line)
        XCTAssertEqual(unworkedDetail.location, .pasture, file: file, line: line)

        let summary = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.totalQueueItems, 2, file: file, line: line)
        XCTAssertEqual(
            summary.completedQueueItems,
            1,
            "Finished session summaries count worked queue items, not all returned animals.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertAnimalStateChangesDoNotImplicitlyEndWorkingOwnership(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working State Change Source", using: fixture)
        let destination = try makePasture(named: "Working State Change Destination", using: fixture)
        let archivedAnimal = try makeAnimal(
            name: "Working Archived Cow",
            tagNumber: "WS101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let soldAnimal = try makeAnimal(
            name: "Working Sold Cow",
            tagNumber: "WS102",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 24),
                sourcePastureID: source.id,
                treatmentTemplateName: "Animal State Change While Working",
                plannedTreatments: [],
                animalIDs: [archivedAnimal.id, soldAnimal.id]
            )
        )

        try fixture.makeAnimalRepository().archive(ids: [archivedAnimal.id])

        let soldBeforeUpdate = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: soldAnimal.id),
            file: file,
            line: line
        )
        let saleDate = date(year: 2026, month: 10, day: 24, hour: 12)
        _ = try fixture.makeAnimalRepository().update(
            id: soldAnimal.id,
            input: AnimalInput(
                name: soldBeforeUpdate.name,
                tagNumber: soldBeforeUpdate.displayTagNumber,
                tagColorID: soldBeforeUpdate.displayTagColorID,
                sex: soldBeforeUpdate.sex,
                birthDate: soldBeforeUpdate.birthDate,
                status: .sold,
                pastureID: soldBeforeUpdate.pastureID,
                sireID: soldBeforeUpdate.sireID,
                damID: soldBeforeUpdate.damID,
                distinguishingFeatures: soldBeforeUpdate.distinguishingFeatures,
                saleDate: saleDate,
                salePrice: 1_250,
                reasonSold: "Working state contract",
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            )
        )

        let sessionAfterAnimalChanges = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(sessionAfterAnimalChanges.status, .active, file: file, line: line)
        XCTAssertEqual(
            Set(sessionAfterAnimalChanges.queueItems.compactMap(\.animalID)),
            Set([archivedAnimal.id, soldAnimal.id]),
            "Archiving or changing herd status must not silently remove a live animal from its active Working queue.",
            file: file,
            line: line
        )

        let archivedWhileWorking = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: archivedAnimal.id),
            file: file,
            line: line
        )
        XCTAssertTrue(archivedWhileWorking.isArchived, file: file, line: line)
        XCTAssertEqual(archivedWhileWorking.status, .active, file: file, line: line)
        XCTAssertEqual(archivedWhileWorking.location, .workingPen, file: file, line: line)
        XCTAssertNil(archivedWhileWorking.pastureID, file: file, line: line)

        let soldWhileWorking = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: soldAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(soldWhileWorking.status, .sold, file: file, line: line)
        XCTAssertEqual(soldWhileWorking.saleDate, saleDate, file: file, line: line)
        XCTAssertEqual(soldWhileWorking.salePrice, 1_250, file: file, line: line)
        XCTAssertEqual(soldWhileWorking.reasonSold, "Working state contract", file: file, line: line)
        XCTAssertEqual(soldWhileWorking.location, .workingPen, file: file, line: line)
        XCTAssertNil(soldWhileWorking.pastureID, file: file, line: line)

        let archivedQueueID = try XCTUnwrap(
            sessionAfterAnimalChanges.queueItems.first { $0.animalID == archivedAnimal.id }?.id,
            file: file,
            line: line
        )
        let soldQueueID = try XCTUnwrap(
            sessionAfterAnimalChanges.queueItems.first { $0.animalID == soldAnimal.id }?.id,
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: archivedQueueID,
                    destinationPastureID: destination.id
                ),
                WorkingQueueDestinationAssignment(
                    queueItemID: soldQueueID,
                    destinationPastureID: destination.id
                )
            ]
        )

        let finished = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(finished.status, .finished, file: file, line: line)

        let archivedAfterFinish = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: archivedAnimal.id),
            file: file,
            line: line
        )
        XCTAssertTrue(
            archivedAfterFinish.isArchived,
            "Finishing Working must not restore an Animal record that was archived through the Animal feature.",
            file: file,
            line: line
        )
        XCTAssertEqual(archivedAfterFinish.status, .active, file: file, line: line)
        XCTAssertEqual(archivedAfterFinish.location, .pasture, file: file, line: line)
        XCTAssertEqual(archivedAfterFinish.pastureID, destination.id, file: file, line: line)

        let soldAfterFinish = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: soldAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            soldAfterFinish.status,
            .sold,
            "Finishing Working must not rewrite an off-herd Animal status selected through the Animal feature.",
            file: file,
            line: line
        )
        XCTAssertEqual(soldAfterFinish.saleDate, saleDate, file: file, line: line)
        XCTAssertEqual(soldAfterFinish.salePrice, 1_250, file: file, line: line)
        XCTAssertEqual(soldAfterFinish.reasonSold, "Working state contract", file: file, line: line)
        XCTAssertEqual(soldAfterFinish.location, .pasture, file: file, line: line)
        XCTAssertEqual(soldAfterFinish.pastureID, destination.id, file: file, line: line)
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertDeletingStaleSessionDoesNotUndoExternalAnimalMovement(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Delete External Source", using: fixture)
        let interim = try makePasture(named: "Working Delete External Interim", using: fixture)
        let animal = try makeAnimal(
            name: "Working Externally Moved Cow",
            tagNumber: "EMD101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 25),
                sourcePastureID: source.id,
                treatmentTemplateName: "External Move Then Delete",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.animalID == animal.id }?.id,
            file: file,
            line: line
        )
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: "Temporary Working observation"
        )

        try fixture.makeAnimalRepository().move(
            ids: [animal.id],
            toPastureID: interim.id
        )

        let beforeDelete = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(beforeDelete.location, .pasture, file: file, line: line)
        XCTAssertEqual(beforeDelete.pastureID, interim.id, file: file, line: line)

        let timelineBeforeDelete = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(
            timelineBeforeDelete.contains { event in
                guard case .movement = event.type else { return false }
                return event.details.contains("Working Delete External Interim")
            },
            file: file,
            line: line
        )
        XCTAssertTrue(
            timelineBeforeDelete.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
            },
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().deleteSession(id: sessionID)

        XCTAssertNil(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let afterDelete = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterDelete.pastureID,
            interim.id,
            "Deleting a stale Working session must not undo a normal herd movement that already released the Animal from Working ownership.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDelete.location, .pasture, file: file, line: line)

        let timelineAfterDelete = try fixture.makeAnimalRepository().fetchTimeline(id: animal.id)
        XCTAssertTrue(
            timelineAfterDelete.contains { event in
                guard case .movement = event.type else { return false }
                return event.details.contains("Working Delete External Interim")
            },
            "Deleting the stale session must preserve the independent movement history.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            timelineAfterDelete.contains { event in
                guard case .health = event.type else { return false }
                return event.title == WorkingGeneratedHealthRecord.observation.treatmentName
            },
            "Deleting the session still removes its generated Working health history even though the live Animal is no longer owned by the session.",
            file: file,
            line: line
        )
    }
}

/// Target-only persistence hook for legacy/read-compatible Working status values that have no
/// current production mutation path. The future Core Data runner may set these raw persisted
/// states directly without adding a production API solely for test setup.
@MainActor
struct WorkingHistoricalStatusInjection {
    let setPersistedStatuses: (
        _ sessionID: UUID,
        _ queueItemID: UUID,
        _ sessionStatus: WorkingSessionStatus,
        _ queueStatus: WorkingQueueStatus
    ) throws -> Void
}

@MainActor
extension WorkingRepositoryContract {
    static func assertPersistedCancelledAndSkippedStatusesRemainReadableAndLocked(
        using fixture: WorkingRepositoryContractFixture,
        historicalStatusInjection: WorkingHistoricalStatusInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Historical Status Source", using: fixture)
        let animal = try makeAnimal(
            name: "Working Historical Status Cow",
            tagNumber: "HS101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 26),
                sourcePastureID: source.id,
                treatmentTemplateName: "Historical Status",
                plannedTreatments: [],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id,
            file: file,
            line: line
        )

        try historicalStatusInjection.setPersistedStatuses(
            sessionID,
            queueItemID,
            .cancelled,
            .skipped
        )

        let freshWorking = fixture.makeWorkingRepository()
        let detail = try XCTUnwrap(
            freshWorking.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(detail.status, .cancelled, file: file, line: line)
        let queue = try XCTUnwrap(
            detail.queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(queue.status, .skipped, file: file, line: line)
        XCTAssertNil(queue.completedAt, file: file, line: line)
        XCTAssertEqual(detail.doneCount, 0, file: file, line: line)
        XCTAssertEqual(detail.queuedCount, 0, file: file, line: line)

        let summary = try XCTUnwrap(
            freshWorking.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summary.status, .cancelled, file: file, line: line)
        XCTAssertEqual(summary.totalQueueItems, 1, file: file, line: line)
        XCTAssertEqual(
            summary.completedQueueItems,
            0,
            "Skipped queue rows remain Not Worked history and are not counted as completed.",
            file: file,
            line: line
        )

        let editor = try XCTUnwrap(
            freshWorking.fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(editor.sessionStatus, .cancelled, file: file, line: line)
        XCTAssertEqual(editor.status, .skipped, file: file, line: line)

        XCTAssertThrowsError(
            try freshWorking.reopenSession(id: sessionID),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .sessionCannotBeReopened,
                file: file,
                line: line
            )
        }
        XCTAssertThrowsError(
            try freshWorking.saveEdits(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingSessionAnimalEditInput(
                    status: .done,
                    completedAt: nil,
                    destinationPastureID: nil,
                    treatmentEntries: [],
                    pregnancyCheck: nil,
                    castrationPerformed: false,
                    observationNotes: "Must remain locked"
                )
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .sessionAlreadyFinished,
                file: file,
                line: line
            )
        }

        let afterFailures = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterFailures,
            detail,
            "Read-compatible cancelled/skipped history must remain unchanged after rejected mutations.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertAnimalHardDeletionPreservesSessionOwnedTreatmentRows(
        using fixture: WorkingRepositoryContractFixture,
        historicalInspection: WorkingHistoricalPersistenceInspection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Child Ownership Source", using: fixture)
        let animal = try makeAnimal(
            name: "Working Child Ownership Cow",
            tagNumber: "CO101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )
        let treatmentID = UUID()
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 28),
                sourcePastureID: source.id,
                treatmentTemplateName: "Child Ownership",
                plannedTreatments: [
                    WorkingTreatmentPlanItem(id: treatmentID, name: "Historical Treatment")
                ],
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
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: date(year: 2026, month: 10, day: 28, hour: 9),
                    treatmentItemID: treatmentID,
                    itemName: "Historical Treatment",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter)
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: date(year: 2026, month: 10, day: 28, hour: 9, minute: 5),
                result: .open,
                estimatedDaysPregnant: nil,
                dueDate: nil,
                sireAnimalID: nil
            ),
            markCastrated: false,
            observationNotes: "Generated observation before Animal deletion"
        )

        let beforeDelete = try historicalInspection.persistedWorkDataIDs(
            sessionID,
            animal.id
        )
        XCTAssertEqual(beforeDelete.treatmentRecordIDs.count, 1, file: file, line: line)
        XCTAssertEqual(beforeDelete.pregnancyCheckIDs.count, 1, file: file, line: line)
        XCTAssertEqual(beforeDelete.healthRecordIDs.count, 1, file: file, line: line)

        let animalRepository = fixture.makeAnimalRepository()
        try animalRepository.archive(ids: [animal.id])
        try animalRepository.delete(ids: [animal.id])

        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        let orphanedSession = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertNotNil(
            orphanedSession.queueItems.first { $0.id == queueItemID },
            "Animal hard deletion must not cascade the owning Working queue/session history.",
            file: file,
            line: line
        )
        XCTAssertNil(
            try fixture.makeWorkingRepository().fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItemID
            ),
            file: file,
            line: line
        )

        let afterAnimalDelete = try historicalInspection.persistedWorkDataIDs(
            sessionID,
            animal.id
        )
        XCTAssertEqual(
            afterAnimalDelete.treatmentRecordIDs,
            beforeDelete.treatmentRecordIDs,
            "Session-owned Working treatment rows must survive live Animal deletion and retain the captured Animal UUID for historical diagnostics.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            afterAnimalDelete.pregnancyCheckIDs.isEmpty,
            "Working-generated pregnancy checks remain Animal-owned history and cascade when that Animal is hard-deleted.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            afterAnimalDelete.healthRecordIDs.isEmpty,
            "Working-generated health records remain Animal-owned history and cascade when that Animal is hard-deleted.",
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().deleteSession(id: sessionID)

        let afterSessionDelete = try historicalInspection.persistedWorkDataIDs(
            sessionID,
            animal.id
        )
        XCTAssertTrue(
            afterSessionDelete.treatmentRecordIDs.isEmpty,
            "The preserved treatment history is still session-owned and must cascade when the Working session itself is deleted.",
            file: file,
            line: line
        )
        XCTAssertTrue(afterSessionDelete.pregnancyCheckIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(afterSessionDelete.healthRecordIDs.isEmpty, file: file, line: line)
    }
}

