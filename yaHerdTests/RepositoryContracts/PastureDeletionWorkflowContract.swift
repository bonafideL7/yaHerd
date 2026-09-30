import XCTest
@testable import yaHerd

/// Permanent behavioral contract for the user-facing pasture-deletion workflow.
///
/// This characterizes the durable outcome users rely on today while the stronger atomic transaction
/// semantics remain a target for the production Core Data implementation.
@MainActor
struct PastureDeletionWorkflowContractFixture {
    let makePastureRepository: () -> any PastureRepository
    let makeAnimalRepository: () -> any AnimalRepository
    let makeTagColorRepository: () -> any TagColorRepository
    let makeFieldCheckRepository: () -> any FieldCheckRepository
    let makeWorkingRepository: () -> any WorkingRepository
    let deletePastures: ([UUID], Date) throws -> Void
}

@MainActor
enum PastureDeletionWorkflowContract {
    private struct ExpectedAnimalCheck {
        let animalID: UUID
        let displayTagNumber: String
        let displayTagColorID: UUID?
        let damDisplayTagNumber: String?
        let damDisplayTagColorID: UUID?
        let animalName: String
        let animalSex: Sex
        let animalType: AnimalType
        let wasExpectedAtStart: Bool
        let wasCounted: Bool
        let needsAttention: Bool
        let isMissing: Bool
    }

    private struct MovementSnapshot: Hashable {
        let date: Date
        let details: String
    }

    static func assertDeleteMovesResidentsAndArchivesFieldCheckHistory(
        using fixture: PastureDeletionWorkflowContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let firstPasture = try pastureRepository.create(
            input: PastureInput(
                name: "Delete Workflow North",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let secondPasture = try pastureRepository.create(
            input: PastureInput(
                name: "Delete Workflow South",
                acreage: 24,
                usableAcreage: 21,
                targetAcresPerHead: 1.75
            )
        )
        let controlPasture = try pastureRepository.create(
            input: PastureInput(
                name: "Delete Workflow Control",
                acreage: 28,
                usableAcreage: 25,
                targetAcresPerHead: 2
            )
        )
        let sharedGroup = try pastureRepository.createGroup(
            input: PastureGroupInput(
                name: "Delete Workflow Rotation",
                grazeDays: 5,
                restDays: 25
            )
        )
        try pastureRepository.assignPasture(id: firstPasture.id, toGroupID: sharedGroup.id)
        try pastureRepository.assignPasture(id: controlPasture.id, toGroupID: sharedGroup.id)

        let tagColorRepository = fixture.makeTagColorRepository()
        let animalTagColor = TagColorSnapshot(
            name: "Deletion Contract Animal Color",
            prefix: "A",
            rgba: RGBAColor(r: 0.2, g: 0.6, b: 0.8)
        )
        let damTagColor = TagColorSnapshot(
            name: "Deletion Contract Dam Color",
            prefix: "D",
            rgba: RGBAColor(r: 0.8, g: 0.5, b: 0.2)
        )
        try tagColorRepository.upsert(animalTagColor)
        try tagColorRepository.upsert(damTagColor)

        let animalRepository = fixture.makeAnimalRepository()
        let dam = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Dam",
                tagNumber: "D700",
                pastureID: nil,
                tagColorID: damTagColor.id
            )
        )
        let firstAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Cow North",
                tagNumber: "701",
                pastureID: firstPasture.id,
                tagColorID: animalTagColor.id,
                damID: dam.id
            )
        )
        let firstPastureSecondAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Bull North",
                tagNumber: "706",
                pastureID: firstPasture.id,
                sex: .male
            )
        )
        let secondAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Cow South",
                tagNumber: "702",
                pastureID: secondPasture.id,
                tagColorID: animalTagColor.id
            )
        )
        let trackedAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Tracked Bull",
                tagNumber: "707",
                pastureID: secondPasture.id,
                sex: .male
            )
        )
        let controlAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Control Cow",
                tagNumber: "708",
                pastureID: controlPasture.id,
                tagColorID: animalTagColor.id
            )
        )
        let workingAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Working Cow",
                tagNumber: "709",
                pastureID: firstPasture.id,
                tagColorID: animalTagColor.id,
                damID: dam.id
            )
        )
        let finishedWorkingAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Finished Working Bull",
                tagNumber: "710",
                pastureID: secondPasture.id,
                tagColorID: animalTagColor.id,
                sex: .male
            )
        )
        let controlWorkingAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Control Working Cow",
                tagNumber: "711",
                pastureID: controlPasture.id,
                tagColorID: animalTagColor.id
            )
        )

        let soldAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Sold Cow",
                tagNumber: "703",
                pastureID: firstPasture.id,
                status: .sold,
                saleDate: Date(timeIntervalSince1970: 1_779_000_000)
            )
        )
        let deadAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Dead Cow",
                tagNumber: "704",
                pastureID: secondPasture.id,
                status: .dead,
                deathDate: Date(timeIntervalSince1970: 1_779_100_000)
            )
        )
        let archivedAnimal = try animalRepository.create(
            input: makeAnimalInput(
                name: "Deletion Contract Archived Cow",
                tagNumber: "705",
                pastureID: secondPasture.id
            )
        )
        try animalRepository.archive(ids: [archivedAnimal.id])

        let workingStartedAt = Date(timeIntervalSince1970: 1_779_900_000)
        let workingPregnancyCheckedAt = Date(timeIntervalSince1970: 1_779_905_000)
        let workingPregnancyDueDate = Date(timeIntervalSince1970: 1_793_988_200)
        let workingTreatmentRecordedAt = Date(timeIntervalSince1970: 1_779_910_000)
        let finishedWorkingStartedAt = Date(timeIntervalSince1970: 1_779_920_000)
        let controlWorkingStartedAt = Date(timeIntervalSince1970: 1_779_930_000)
        let workingTreatment = WorkingTreatmentPlanItem(
            id: UUID(),
            name: "Deletion Contract Vaccine",
            suggestedDose: WorkingTreatmentDose(
                amount: 2,
                unit: .milliliter,
                route: .subcutaneous
            )
        )
        let workingRepository = fixture.makeWorkingRepository()
        let workingSessionID = try workingRepository.startSession(
            input: WorkingSessionStartInput(
                date: workingStartedAt,
                sourcePastureID: firstPasture.id,
                treatmentTemplateName: "Deletion Contract Work",
                plannedTreatments: [workingTreatment],
                animalIDs: [workingAnimal.id]
            )
        )
        let workingSessionAtStart = try XCTUnwrap(
            workingRepository.fetchSessionDetail(id: workingSessionID),
            "The Working deletion fixture must create its session before pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingSessionAtStart.queueItems.count, 1, file: file, line: line)
        let workingQueueItemID = try XCTUnwrap(
            workingSessionAtStart.queueItems.first?.id,
            "The Working deletion fixture must contain exactly one queue item.",
            file: file,
            line: line
        )
        try workingRepository.complete(
            queueItemID: workingQueueItemID,
            inSessionID: workingSessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: workingTreatmentRecordedAt,
                    treatmentItemID: workingTreatment.id,
                    itemName: workingTreatment.name,
                    given: true,
                    dose: WorkingTreatmentDose(
                        amount: 2.5,
                        unit: .milliliter,
                        route: .intramuscular
                    )
                )
            ],
            pregnancyCheck: WorkingPregnancyCheckInput(
                date: workingPregnancyCheckedAt,
                result: .pregnant,
                estimatedDaysPregnant: 120,
                dueDate: workingPregnancyDueDate,
                sireAnimalID: firstPastureSecondAnimal.id
            ),
            markCastrated: false,
            observationNotes: "Deletion workflow working history"
        )
        let workingSessionBeforeDeletion = try XCTUnwrap(
            workingRepository.fetchSessionDetail(id: workingSessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(workingSessionBeforeDeletion.queueItems.count, 1, file: file, line: line)
        let workingQueueItemBeforeDeletion = try XCTUnwrap(
            workingSessionBeforeDeletion.queueItems.first,
            file: file,
            line: line
        )
        let workingCompletedAt = try XCTUnwrap(
            workingQueueItemBeforeDeletion.completedAt,
            "The Working queue fixture must be completed before pasture deletion.",
            file: file,
            line: line
        )
        let workingEditorBeforeDeletion = try XCTUnwrap(
            workingRepository.fetchQueueItemEditor(
                sessionID: workingSessionID,
                queueItemID: workingQueueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(workingEditorBeforeDeletion.treatmentRecords.count, 1, file: file, line: line)
        XCTAssertNotNil(workingEditorBeforeDeletion.pregnancyCheck, file: file, line: line)
        let workingAnimalAgeInMonthsBeforeDeletion = workingEditorBeforeDeletion.animalAgeInMonths

        try workingRepository.saveEdits(
            forQueueItemID: workingQueueItemID,
            inSessionID: workingSessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: workingCompletedAt,
                destinationPastureID: secondPasture.id,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: workingTreatmentRecordedAt,
                        treatmentItemID: workingTreatment.id,
                        itemName: workingTreatment.name,
                        given: true,
                        dose: WorkingTreatmentDose(
                            amount: 2.5,
                            unit: .milliliter,
                            route: .intramuscular
                        )
                    )
                ],
                pregnancyCheck: WorkingPregnancyCheckInput(
                    date: workingPregnancyCheckedAt,
                    result: .pregnant,
                    estimatedDaysPregnant: 120,
                    dueDate: workingPregnancyDueDate,
                    sireAnimalID: firstPastureSecondAnimal.id
                ),
                castrationPerformed: false,
                observationNotes: "Deletion workflow working history"
            )
        )
        let workingSessionWithDestination = try XCTUnwrap(
            workingRepository.fetchSessionDetail(id: workingSessionID),
            file: file,
            line: line
        )
        let workingQueueItemWithDestination = try XCTUnwrap(
            workingSessionWithDestination.queueItems.first,
            file: file,
            line: line
        )
        XCTAssertEqual(workingQueueItemWithDestination.destinationPastureID, secondPasture.id, file: file, line: line)
        XCTAssertEqual(workingQueueItemWithDestination.destinationPastureName, "Delete Workflow South", file: file, line: line)
        let workingEditorWithDestination = try XCTUnwrap(
            workingRepository.fetchQueueItemEditor(
                sessionID: workingSessionID,
                queueItemID: workingQueueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(workingEditorWithDestination.destinationPastureID, secondPasture.id, file: file, line: line)
        XCTAssertEqual(workingEditorWithDestination.treatmentRecords.count, 1, file: file, line: line)
        let workingTreatmentRecordIDBeforeDeletion = try XCTUnwrap(
            workingEditorWithDestination.treatmentRecords.first?.id,
            "The Working treatment fixture must persist its treatment-record identity before pasture deletion.",
            file: file,
            line: line
        )

        let finishedWorkingSessionID = try workingRepository.startSession(
            input: WorkingSessionStartInput(
                date: finishedWorkingStartedAt,
                sourcePastureID: secondPasture.id,
                treatmentTemplateName: "Deletion Contract Finished Work",
                plannedTreatments: [],
                animalIDs: [finishedWorkingAnimal.id]
            )
        )
        let finishedWorkingSessionAtStart = try XCTUnwrap(
            workingRepository.fetchSessionDetail(id: finishedWorkingSessionID),
            "The finished Working fixture must create its session before pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(finishedWorkingSessionAtStart.queueItems.count, 1, file: file, line: line)
        let finishedWorkingQueueItemID = try XCTUnwrap(
            finishedWorkingSessionAtStart.queueItems.first?.id,
            "The finished Working fixture must contain exactly one queue item.",
            file: file,
            line: line
        )
        try workingRepository.complete(
            queueItemID: finishedWorkingQueueItemID,
            inSessionID: finishedWorkingSessionID,
            treatmentEntries: [],
            pregnancyCheck: nil,
            markCastrated: true,
            observationNotes: "Deletion workflow finished working history"
        )
        let finishedWorkingBeforeFinish = try XCTUnwrap(
            workingRepository.fetchSessionDetail(id: finishedWorkingSessionID),
            file: file,
            line: line
        )
        let finishedWorkingQueueBeforeFinish = try XCTUnwrap(
            finishedWorkingBeforeFinish.queueItems.first,
            file: file,
            line: line
        )
        let finishedWorkingCompletedAt = try XCTUnwrap(
            finishedWorkingQueueBeforeFinish.completedAt,
            "The finished Working queue item must be completed before the session is finished.",
            file: file,
            line: line
        )
        let finishedWorkingEditorBeforeDeletion = try XCTUnwrap(
            workingRepository.fetchQueueItemEditor(
                sessionID: finishedWorkingSessionID,
                queueItemID: finishedWorkingQueueItemID
            ),
            file: file,
            line: line
        )
        XCTAssertTrue(finishedWorkingEditorBeforeDeletion.castrationPerformedInSession, file: file, line: line)
        try workingRepository.completeSession(
            id: finishedWorkingSessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: finishedWorkingQueueItemID,
                    destinationPastureID: nil
                )
            ]
        )
        let finishedWorkingSessionBeforeDeletion = try XCTUnwrap(
            workingRepository.fetchSessionDetail(id: finishedWorkingSessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(finishedWorkingSessionBeforeDeletion.status, .finished, file: file, line: line)

        let controlWorkingSessionID = try workingRepository.startSession(
            input: WorkingSessionStartInput(
                date: controlWorkingStartedAt,
                sourcePastureID: controlPasture.id,
                treatmentTemplateName: "Deletion Contract Control Work",
                plannedTreatments: [],
                animalIDs: [controlWorkingAnimal.id]
            )
        )
        let controlWorkingSessionBeforeDeletion = try XCTUnwrap(
            workingRepository.fetchSessionDetail(id: controlWorkingSessionID),
            "The unrelated Working fixture must exist before deleting other pastures.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlWorkingSessionBeforeDeletion.status, .active, file: file, line: line)
        XCTAssertEqual(controlWorkingSessionBeforeDeletion.sourcePastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(controlWorkingSessionBeforeDeletion.sourcePastureName, "Delete Workflow Control", file: file, line: line)
        XCTAssertTrue(controlWorkingSessionBeforeDeletion.isSourcePastureAvailable, file: file, line: line)
        XCTAssertEqual(controlWorkingSessionBeforeDeletion.queueItems.count, 1, file: file, line: line)
        let controlWorkingQueueItemID = try XCTUnwrap(
            controlWorkingSessionBeforeDeletion.queueItems.first?.id,
            "The unrelated Working fixture must contain one queued animal.",
            file: file,
            line: line
        )
        let controlWorkingEditorBeforeDeletion = try XCTUnwrap(
            workingRepository.fetchQueueItemEditor(
                sessionID: controlWorkingSessionID,
                queueItemID: controlWorkingQueueItemID
            ),
            file: file,
            line: line
        )
        let controlWorkingSummaryBeforeDeletion = try XCTUnwrap(
            workingRepository.fetchSessions().first { $0.id == controlWorkingSessionID },
            "The unrelated Working fixture must appear in the list reader before deletion.",
            file: file,
            line: line
        )

        let firstStartedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let secondStartedAt = Date(timeIntervalSince1970: 1_780_043_200)
        let controlStartedAt = Date(timeIntervalSince1970: 1_780_064_000)
        let findingRecordedAt = Date(timeIntervalSince1970: 1_780_050_000)
        let trackedAt = Date(timeIntervalSince1970: 1_780_060_000)
        let archivedAt = Date(timeIntervalSince1970: 1_780_086_400)
        let firstNotes = "Deletion workflow contract north"
        let secondNotes = "Deletion workflow contract south"
        let controlNotes = "Deletion workflow contract control"
        let fieldCheckRepository = fixture.makeFieldCheckRepository()
        let firstSessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: firstPasture.id,
                startedAt: firstStartedAt,
                notes: firstNotes
            )
        )
        let secondSessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: secondPasture.id,
                startedAt: secondStartedAt,
                notes: secondNotes
            )
        )
        let controlSessionID = try fieldCheckRepository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: controlPasture.id,
                startedAt: controlStartedAt,
                notes: controlNotes
            )
        )

        let firstSessionBeforeStateChanges = try XCTUnwrap(
            fieldCheckRepository.fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        let countedCheck = try XCTUnwrap(
            firstSessionBeforeStateChanges.animalChecks.first { $0.animalID == firstAnimal.id },
            "The first resident must be present in the Field Check roster.",
            file: file,
            line: line
        )
        let missingCheck = try XCTUnwrap(
            firstSessionBeforeStateChanges.animalChecks.first { $0.animalID == firstPastureSecondAnimal.id },
            "The second resident must be present in the Field Check roster.",
            file: file,
            line: line
        )
        try fieldCheckRepository.setAnimalCheckCounted(
            sessionID: firstSessionID,
            animalCheckID: countedCheck.id,
            isCounted: true
        )
        try fieldCheckRepository.setAnimalCheckMissing(
            sessionID: firstSessionID,
            animalCheckID: missingCheck.id,
            isMissing: true
        )
        try fieldCheckRepository.addTrackedAnimalToSession(
            sessionID: firstSessionID,
            animalID: trackedAnimal.id,
            checkedAt: trackedAt
        )
        try fieldCheckRepository.updateQuickAnimalTypeCounts(
            sessionID: secondSessionID,
            counts: [.heifer: 1]
        )

        let findingInput = FieldCheckFindingInput(
            recordedAt: findingRecordedAt,
            type: .pinkEye,
            severity: .critical,
            status: .monitoring,
            note: "Deletion workflow finding",
            animalID: secondAnimal.id
        )
        try fieldCheckRepository.addFinding(sessionID: secondSessionID, input: findingInput)

        try fieldCheckRepository.completeSession(id: firstSessionID)
        let completedFirstSession = try XCTUnwrap(
            fieldCheckRepository.fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        let firstCompletedAt = try XCTUnwrap(
            completedFirstSession.completedAt,
            "The completed-session fixture must persist its completion timestamp before deletion.",
            file: file,
            line: line
        )
        let firstAnimalCheckIDsBeforeDeletion = animalCheckIDs(completedFirstSession.animalChecks)
        let secondSessionBeforeDeletion = try XCTUnwrap(
            fieldCheckRepository.fetchSessionDetail(id: secondSessionID),
            file: file,
            line: line
        )
        let secondAnimalCheckIDsBeforeDeletion = animalCheckIDs(secondSessionBeforeDeletion.animalChecks)
        XCTAssertEqual(secondSessionBeforeDeletion.findings.count, 1, file: file, line: line)
        let secondFindingBeforeDeletion = try XCTUnwrap(
            secondSessionBeforeDeletion.findings.first,
            "The second Field Check fixture must persist its finding before pasture deletion.",
            file: file,
            line: line
        )

        let preDeletionAnimals = fixture.makeAnimalRepository()
        let firstAnimalDetailBeforeDeletion = try XCTUnwrap(
            preDeletionAnimals.fetchAnimalDetail(id: firstAnimal.id),
            "The moved-animal fixture must be readable before pasture deletion.",
            file: file,
            line: line
        )
        let firstAnimalSummaryBeforeDeletion = try XCTUnwrap(
            preDeletionAnimals.fetchAnimals().first { $0.id == firstAnimal.id },
            "The moved-animal fixture must appear in the list projection before pasture deletion.",
            file: file,
            line: line
        )
        let finishedWorkingAnimalDetailBeforeDeletion = try XCTUnwrap(
            preDeletionAnimals.fetchAnimalDetail(id: finishedWorkingAnimal.id),
            "The finished Working animal must remain readable after completing its session.",
            file: file,
            line: line
        )
        let finishedWorkingAnimalSummaryBeforeDeletion = try XCTUnwrap(
            preDeletionAnimals.fetchAnimals().first { $0.id == finishedWorkingAnimal.id },
            "The finished Working animal must remain visible after completing its session.",
            file: file,
            line: line
        )
        XCTAssertEqual(finishedWorkingAnimalDetailBeforeDeletion.status, .active, file: file, line: line)
        XCTAssertEqual(finishedWorkingAnimalDetailBeforeDeletion.location, .pasture, file: file, line: line)
        XCTAssertNil(finishedWorkingAnimalDetailBeforeDeletion.pastureID, file: file, line: line)
        XCTAssertNil(finishedWorkingAnimalDetailBeforeDeletion.pastureName, file: file, line: line)
        XCTAssertEqual(finishedWorkingAnimalSummaryBeforeDeletion.status, .active, file: file, line: line)
        XCTAssertEqual(finishedWorkingAnimalSummaryBeforeDeletion.location, .pasture, file: file, line: line)
        XCTAssertNil(finishedWorkingAnimalSummaryBeforeDeletion.pastureID, file: file, line: line)
        XCTAssertNil(finishedWorkingAnimalSummaryBeforeDeletion.pastureName, file: file, line: line)
        let finishedWorkingMovementDetailsBeforeDeletion = try movementDetails(
            animalID: finishedWorkingAnimal.id,
            repository: preDeletionAnimals
        )
        XCTAssertTrue(
            finishedWorkingMovementDetailsBeforeDeletion.contains("Delete Workflow South → —"),
            "Completing the finished Working session must record the animal's move out of South before pasture deletion.",
            file: file,
            line: line
        )
        let controlWorkingAnimalDetailBeforeDeletion = try XCTUnwrap(
            preDeletionAnimals.fetchAnimalDetail(id: controlWorkingAnimal.id),
            "The unrelated Working animal must remain readable while its session is active.",
            file: file,
            line: line
        )
        let controlWorkingAnimalSummaryBeforeDeletion = try XCTUnwrap(
            preDeletionAnimals.fetchAnimals().first { $0.id == controlWorkingAnimal.id },
            "The unrelated Working animal must remain visible through the animal-list reader.",
            file: file,
            line: line
        )
        let firstAnimalMovementsBeforeDeletion = try movementSnapshots(
            animalID: firstAnimal.id,
            repository: preDeletionAnimals
        )
        let firstPastureSecondAnimalMovementsBeforeDeletion = try movementSnapshots(
            animalID: firstPastureSecondAnimal.id,
            repository: preDeletionAnimals
        )
        let secondAnimalMovementsBeforeDeletion = try movementSnapshots(
            animalID: secondAnimal.id,
            repository: preDeletionAnimals
        )
        let trackedAnimalMovementsBeforeDeletion = try movementSnapshots(
            animalID: trackedAnimal.id,
            repository: preDeletionAnimals
        )
        let controlMovementDetailsBeforeDeletion = try movementDetails(
            animalID: controlAnimal.id,
            repository: preDeletionAnimals
        )
        let controlWorkingMovementDetailsBeforeDeletion = try movementDetails(
            animalID: controlWorkingAnimal.id,
            repository: preDeletionAnimals
        )
        let workingMovementDetailsBeforeDeletion = try movementDetails(
            animalID: workingAnimal.id,
            repository: preDeletionAnimals
        )
        let soldMovementDetailsBeforeDeletion = try movementDetails(
            animalID: soldAnimal.id,
            repository: preDeletionAnimals
        )
        let deadMovementDetailsBeforeDeletion = try movementDetails(
            animalID: deadAnimal.id,
            repository: preDeletionAnimals
        )
        let archivedMovementDetailsBeforeDeletion = try movementDetails(
            animalID: archivedAnimal.id,
            repository: preDeletionAnimals
        )

        try fixture.deletePastures([firstPasture.id, secondPasture.id], archivedAt)

        let reloadedPastures = fixture.makePastureRepository()
        XCTAssertNil(
            try reloadedPastures.fetchPastureDetail(id: firstPasture.id),
            "Every requested pasture must be deleted, including the first item in a batch.",
            file: file,
            line: line
        )
        XCTAssertNil(
            try reloadedPastures.fetchPastureDetail(id: secondPasture.id),
            "Every requested pasture must be deleted, including later items in a batch.",
            file: file,
            line: line
        )

        let controlDetail = try XCTUnwrap(
            reloadedPastures.fetchPastureDetail(id: controlPasture.id),
            "Deleting a selected subset must preserve unselected pastures.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlDetail.name, "Delete Workflow Control", file: file, line: line)
        XCTAssertEqual(controlDetail.acreage, 28, file: file, line: line)
        XCTAssertEqual(controlDetail.usableAcreage, 25, file: file, line: line)
        XCTAssertEqual(controlDetail.targetAcresPerHead, 2, file: file, line: line)
        XCTAssertEqual(controlDetail.activeAnimalCount, 1, file: file, line: line)
        XCTAssertEqual(controlDetail.groupID, sharedGroup.id, file: file, line: line)
        XCTAssertEqual(controlDetail.groupName, "Delete Workflow Rotation", file: file, line: line)

        let sharedGroupDetail = try XCTUnwrap(
            reloadedPastures.fetchPastureGroupDetail(id: sharedGroup.id),
            "Deleting one member pasture must not cascade-delete its pasture group.",
            file: file,
            line: line
        )
        XCTAssertEqual(sharedGroupDetail.name, "Delete Workflow Rotation", file: file, line: line)
        XCTAssertEqual(sharedGroupDetail.grazeDays, 5, file: file, line: line)
        XCTAssertEqual(sharedGroupDetail.restDays, 25, file: file, line: line)
        XCTAssertEqual(sharedGroupDetail.pastures.map(\.id), [controlPasture.id], file: file, line: line)

        let groupSummaries = try reloadedPastures.fetchPastureGroups()
        let sharedGroupSummary = try XCTUnwrap(
            groupSummaries.first { $0.id == sharedGroup.id },
            "The pasture-group list projection must retain a group after one member pasture is deleted.",
            file: file,
            line: line
        )
        XCTAssertEqual(sharedGroupSummary.name, "Delete Workflow Rotation", file: file, line: line)
        XCTAssertEqual(sharedGroupSummary.grazeDays, 5, file: file, line: line)
        XCTAssertEqual(sharedGroupSummary.restDays, 25, file: file, line: line)
        XCTAssertEqual(sharedGroupSummary.pastureCount, 1, file: file, line: line)

        let pastureSummaries = try reloadedPastures.fetchPastures()
        XCTAssertFalse(pastureSummaries.contains { $0.id == firstPasture.id }, file: file, line: line)
        XCTAssertFalse(pastureSummaries.contains { $0.id == secondPasture.id }, file: file, line: line)
        let controlSummary = try XCTUnwrap(
            pastureSummaries.first { $0.id == controlPasture.id },
            "The pasture list must retain an unselected pasture after a batch deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlSummary.name, "Delete Workflow Control", file: file, line: line)
        XCTAssertEqual(controlSummary.acreage, 28, file: file, line: line)
        XCTAssertEqual(controlSummary.usableAcreage, 25, file: file, line: line)
        XCTAssertEqual(controlSummary.targetAcresPerHead, 2, file: file, line: line)
        XCTAssertEqual(controlSummary.activeAnimalCount, 1, file: file, line: line)
        XCTAssertEqual(controlSummary.groupID, sharedGroup.id, file: file, line: line)
        XCTAssertEqual(controlSummary.groupName, "Delete Workflow Rotation", file: file, line: line)
        XCTAssertEqual(controlSummary.restDays, 25, file: file, line: line)
        let pastureOptions = try reloadedPastures.fetchPastureOptions()
        XCTAssertFalse(pastureOptions.contains { $0.id == firstPasture.id }, file: file, line: line)
        XCTAssertFalse(pastureOptions.contains { $0.id == secondPasture.id }, file: file, line: line)
        let controlOption = try XCTUnwrap(
            pastureOptions.first { $0.id == controlPasture.id },
            "The pasture option projection must retain an unselected pasture after deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlOption.name, "Delete Workflow Control", file: file, line: line)

        let reloadedAnimals = fixture.makeAnimalRepository()
        let animalSummaries = try reloadedAnimals.fetchAnimals()
        for movedAnimalID in [
            firstAnimal.id,
            firstPastureSecondAnimal.id,
            secondAnimal.id,
            trackedAnimal.id
        ] {
            let summary = try XCTUnwrap(
                animalSummaries.first { $0.id == movedAnimalID },
                "Animals moved out of deleted pastures must remain visible through the animal-list reader.",
                file: file,
                line: line
            )
            XCTAssertEqual(summary.location, .pasture, file: file, line: line)
            XCTAssertNil(summary.pastureID, file: file, line: line)
            XCTAssertNil(summary.pastureName, file: file, line: line)
        }
        let firstAnimalSummaryAfterDeletion = try XCTUnwrap(
            animalSummaries.first { $0.id == firstAnimal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.name, firstAnimalSummaryBeforeDeletion.name, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.displayTagNumber, firstAnimalSummaryBeforeDeletion.displayTagNumber, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.displayTagColorID, firstAnimalSummaryBeforeDeletion.displayTagColorID, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.damDisplayTagNumber, firstAnimalSummaryBeforeDeletion.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.damDisplayTagColorID, firstAnimalSummaryBeforeDeletion.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.sex, firstAnimalSummaryBeforeDeletion.sex, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.animalType, firstAnimalSummaryBeforeDeletion.animalType, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.firstDistinguishingFeature, firstAnimalSummaryBeforeDeletion.firstDistinguishingFeature, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.birthDate, firstAnimalSummaryBeforeDeletion.birthDate, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.status, firstAnimalSummaryBeforeDeletion.status, file: file, line: line)
        XCTAssertEqual(firstAnimalSummaryAfterDeletion.isArchived, firstAnimalSummaryBeforeDeletion.isArchived, file: file, line: line)
        let workingAnimalSummaryAfterDeletion = try XCTUnwrap(
            animalSummaries.first { $0.id == workingAnimal.id },
            "The animal from the active Working session must remain visible after its source pasture is deleted.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingAnimalSummaryAfterDeletion.location, .workingPen, file: file, line: line)
        XCTAssertNil(workingAnimalSummaryAfterDeletion.pastureID, file: file, line: line)
        XCTAssertNil(workingAnimalSummaryAfterDeletion.pastureName, file: file, line: line)
        let finishedWorkingAnimalSummaryAfterDeletion = try XCTUnwrap(
            animalSummaries.first { $0.id == finishedWorkingAnimal.id },
            "The animal from a finished Working session must remain visible after its source pasture is deleted.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            finishedWorkingAnimalSummaryAfterDeletion,
            finishedWorkingAnimalSummaryBeforeDeletion,
            "Pasture deletion must not rewrite the finished Working animal's list state.",
            file: file,
            line: line
        )
        let controlAnimalSummary = try XCTUnwrap(
            animalSummaries.first { $0.id == controlAnimal.id },
            "Residents of an unselected pasture must remain visible through the animal-list reader.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlAnimalSummary.location, .pasture, file: file, line: line)
        XCTAssertEqual(controlAnimalSummary.pastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(controlAnimalSummary.pastureName, "Delete Workflow Control", file: file, line: line)
        let controlWorkingAnimalSummaryAfterDeletion = try XCTUnwrap(
            animalSummaries.first { $0.id == controlWorkingAnimal.id },
            "An animal active in an unrelated Working session must remain in the animal-list projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlWorkingAnimalSummaryAfterDeletion,
            controlWorkingAnimalSummaryBeforeDeletion,
            "Deleting other pastures must not rewrite the unrelated Working animal's list state.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlWorkingAnimalSummaryAfterDeletion.location, .workingPen, file: file, line: line)
        XCTAssertNil(controlWorkingAnimalSummaryAfterDeletion.pastureID, file: file, line: line)
        XCTAssertNil(controlWorkingAnimalSummaryAfterDeletion.pastureName, file: file, line: line)

        for (animalID, expectedStatus, expectedArchived) in [
            (soldAnimal.id, AnimalStatus.sold, false),
            (deadAnimal.id, AnimalStatus.dead, false),
            (archivedAnimal.id, AnimalStatus.active, true)
        ] {
            let summary = try XCTUnwrap(
                animalSummaries.first { $0.id == animalID },
                "Inactive animals must remain visible through the animal-list reader after pasture deletion.",
                file: file,
                line: line
            )
            XCTAssertEqual(summary.status, expectedStatus, file: file, line: line)
            XCTAssertEqual(summary.isArchived, expectedArchived, file: file, line: line)
            XCTAssertEqual(summary.location, .pasture, file: file, line: line)
            XCTAssertNil(summary.pastureID, file: file, line: line)
            XCTAssertNil(summary.pastureName, file: file, line: line)
        }

        try assertAnimalMovedToUnassigned(
            animalID: firstAnimal.id,
            pastureName: "Delete Workflow North",
            expectedMovementsBeforeDeletion: firstAnimalMovementsBeforeDeletion,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        let firstAnimalDetailAfterDeletion = try XCTUnwrap(
            reloadedAnimals.fetchAnimalDetail(id: firstAnimal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(firstAnimalDetailAfterDeletion.name, firstAnimalDetailBeforeDeletion.name, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.displayTagNumber, firstAnimalDetailBeforeDeletion.displayTagNumber, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.displayTagColorID, firstAnimalDetailBeforeDeletion.displayTagColorID, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.sex, firstAnimalDetailBeforeDeletion.sex, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.animalType, firstAnimalDetailBeforeDeletion.animalType, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.birthDate, firstAnimalDetailBeforeDeletion.birthDate, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.status, firstAnimalDetailBeforeDeletion.status, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.sireID, firstAnimalDetailBeforeDeletion.sireID, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.sire, firstAnimalDetailBeforeDeletion.sire, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.damID, firstAnimalDetailBeforeDeletion.damID, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.dam, firstAnimalDetailBeforeDeletion.dam, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.distinguishingFeatures, firstAnimalDetailBeforeDeletion.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.statusReferenceID, firstAnimalDetailBeforeDeletion.statusReferenceID, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.statusReferenceName, firstAnimalDetailBeforeDeletion.statusReferenceName, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.isArchived, firstAnimalDetailBeforeDeletion.isArchived, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.activeTags, firstAnimalDetailBeforeDeletion.activeTags, file: file, line: line)
        XCTAssertEqual(firstAnimalDetailAfterDeletion.inactiveTags, firstAnimalDetailBeforeDeletion.inactiveTags, file: file, line: line)
        try assertAnimalMovedToUnassigned(
            animalID: firstPastureSecondAnimal.id,
            pastureName: "Delete Workflow North",
            expectedMovementsBeforeDeletion: firstPastureSecondAnimalMovementsBeforeDeletion,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        try assertAnimalMovedToUnassigned(
            animalID: secondAnimal.id,
            pastureName: "Delete Workflow South",
            expectedMovementsBeforeDeletion: secondAnimalMovementsBeforeDeletion,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        try assertAnimalMovedToUnassigned(
            animalID: trackedAnimal.id,
            pastureName: "Delete Workflow North",
            expectedMovementsBeforeDeletion: trackedAnimalMovementsBeforeDeletion,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        let reloadedFinishedWorkingAnimal = try XCTUnwrap(
            reloadedAnimals.fetchAnimalDetail(id: finishedWorkingAnimal.id),
            "Deleting a finished Working session's source pasture must preserve its animal.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedFinishedWorkingAnimal,
            finishedWorkingAnimalDetailBeforeDeletion,
            "Pasture deletion must not rewrite the finished Working animal's post-completion state.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try movementDetails(animalID: finishedWorkingAnimal.id, repository: reloadedAnimals),
            finishedWorkingMovementDetailsBeforeDeletion,
            "Pasture deletion must preserve the finished Working animal's existing movement history.",
            file: file,
            line: line
        )
        let reloadedControlAnimal = try XCTUnwrap(
            reloadedAnimals.fetchAnimalDetail(id: controlAnimal.id),
            "Deleting other pastures must preserve residents of an unselected pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedControlAnimal.pastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(reloadedControlAnimal.pastureName, "Delete Workflow Control", file: file, line: line)
        let controlMovementDetailsAfterDeletion = try movementDetails(
            animalID: controlAnimal.id,
            repository: reloadedAnimals
        )
        XCTAssertEqual(
            controlMovementDetailsAfterDeletion,
            controlMovementDetailsBeforeDeletion,
            "Deleting a selected subset must not move residents of an unselected pasture.",
            file: file,
            line: line
        )
        let reloadedControlWorkingAnimal = try XCTUnwrap(
            reloadedAnimals.fetchAnimalDetail(id: controlWorkingAnimal.id),
            "Deleting other pastures must preserve the animal active in an unrelated Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedControlWorkingAnimal,
            controlWorkingAnimalDetailBeforeDeletion,
            "Deleting other pastures must not rewrite the unrelated Working animal's detail state.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedControlWorkingAnimal.location, .workingPen, file: file, line: line)
        XCTAssertNil(reloadedControlWorkingAnimal.pastureID, file: file, line: line)
        XCTAssertNil(reloadedControlWorkingAnimal.pastureName, file: file, line: line)
        XCTAssertEqual(
            try movementDetails(animalID: controlWorkingAnimal.id, repository: reloadedAnimals),
            controlWorkingMovementDetailsBeforeDeletion,
            "Deleting other pastures must not alter movement history for an unrelated Working animal.",
            file: file,
            line: line
        )

        let reloadedWorkingAnimal = try XCTUnwrap(
            reloadedAnimals.fetchAnimalDetail(id: workingAnimal.id),
            "Deleting a Working session's source pasture must preserve the actively worked animal.",
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedWorkingAnimal.location, .workingPen, file: file, line: line)
        XCTAssertNil(reloadedWorkingAnimal.pastureID, file: file, line: line)
        XCTAssertNil(reloadedWorkingAnimal.pastureName, file: file, line: line)
        XCTAssertEqual(
            try movementDetails(animalID: workingAnimal.id, repository: reloadedAnimals),
            workingMovementDetailsBeforeDeletion,
            "Deleting a Working session's source pasture must not change the active Working animal's movement history.",
            file: file,
            line: line
        )

        try assertInactiveAnimalSurvivesPastureDeletion(
            animalID: soldAnimal.id,
            expectedStatus: .sold,
            expectedArchived: false,
            expectedSaleDate: Date(timeIntervalSince1970: 1_779_000_000),
            expectedSalePrice: 1_250,
            expectedReasonSold: "Deletion workflow contract",
            expectedMovementDetails: soldMovementDetailsBeforeDeletion,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        try assertInactiveAnimalSurvivesPastureDeletion(
            animalID: deadAnimal.id,
            expectedStatus: .dead,
            expectedArchived: false,
            expectedDeathDate: Date(timeIntervalSince1970: 1_779_100_000),
            expectedCauseOfDeath: "Deletion workflow contract",
            expectedMovementDetails: deadMovementDetailsBeforeDeletion,
            repository: reloadedAnimals,
            file: file,
            line: line
        )
        try assertInactiveAnimalSurvivesPastureDeletion(
            animalID: archivedAnimal.id,
            expectedStatus: .active,
            expectedArchived: true,
            expectedMovementDetails: archivedMovementDetailsBeforeDeletion,
            repository: reloadedAnimals,
            file: file,
            line: line
        )

        let reloadedWorking = fixture.makeWorkingRepository()
        let controlWorkingDetailAfterDeletion = try XCTUnwrap(
            reloadedWorking.fetchSessionDetail(id: controlWorkingSessionID),
            "Deleting other pastures must preserve an unrelated Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlWorkingDetailAfterDeletion,
            controlWorkingSessionBeforeDeletion,
            "An unrelated Working session's detail projection must remain unchanged.",
            file: file,
            line: line
        )

        let workingDetail = try XCTUnwrap(
            reloadedWorking.fetchSessionDetail(id: workingSessionID),
            "Working sessions must survive deletion of their source pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingDetail.date, workingSessionBeforeDeletion.date, file: file, line: line)
        XCTAssertEqual(workingDetail.status, .active, file: file, line: line)
        XCTAssertEqual(workingDetail.sourcePastureID, firstPasture.id, file: file, line: line)
        XCTAssertEqual(workingDetail.sourcePastureName, "Delete Workflow North", file: file, line: line)
        XCTAssertFalse(
            workingDetail.isSourcePastureAvailable,
            "Historical Working source identity remains readable after deletion but must no longer be treated as a live Pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingDetail.treatmentTemplateName, "Deletion Contract Work", file: file, line: line)
        XCTAssertEqual(workingDetail.plannedTreatments, [workingTreatment], file: file, line: line)
        XCTAssertEqual(workingDetail.queueItems.count, 1, file: file, line: line)
        let workingQueueItem = try XCTUnwrap(workingDetail.queueItems.first, file: file, line: line)
        XCTAssertEqual(workingQueueItem.id, workingQueueItemID, file: file, line: line)
        XCTAssertEqual(workingQueueItem.status, .done, file: file, line: line)
        XCTAssertEqual(workingQueueItem.completedAt, workingCompletedAt, file: file, line: line)
        XCTAssertEqual(workingQueueItem.animalID, workingAnimal.id, file: file, line: line)
        XCTAssertEqual(workingQueueItem.animalName, "Deletion Contract Working Cow", file: file, line: line)
        XCTAssertEqual(workingQueueItem.animalDisplayTagNumber, "709", file: file, line: line)
        XCTAssertEqual(workingQueueItem.animalDisplayTagColorID, animalTagColor.id, file: file, line: line)
        XCTAssertEqual(workingQueueItem.animalDamDisplayTagNumber, "D700", file: file, line: line)
        XCTAssertEqual(workingQueueItem.animalDamDisplayTagColorID, damTagColor.id, file: file, line: line)
        XCTAssertEqual(workingQueueItem.animalSex, .female, file: file, line: line)
        XCTAssertEqual(workingQueueItem.collectedFromPastureID, firstPasture.id, file: file, line: line)
        XCTAssertEqual(workingQueueItem.collectedFromPastureName, "Delete Workflow North", file: file, line: line)
        XCTAssertEqual(workingQueueItem.destinationPastureID, secondPasture.id, file: file, line: line)
        XCTAssertEqual(workingQueueItem.destinationPastureName, "Delete Workflow South", file: file, line: line)

        let workingSummaries = try reloadedWorking.fetchSessions()
        let controlWorkingSummaryAfterDeletion = try XCTUnwrap(
            workingSummaries.first { $0.id == controlWorkingSessionID },
            "The Working list reader must preserve an unrelated session after deleting other pastures.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlWorkingSummaryAfterDeletion,
            controlWorkingSummaryBeforeDeletion,
            "An unrelated Working session's list projection must remain unchanged.",
            file: file,
            line: line
        )
        let workingSummary = try XCTUnwrap(
            workingSummaries.first { $0.id == workingSessionID },
            "Working sessions must remain visible through the list reader after source-pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingSummary.date, workingSessionBeforeDeletion.date, file: file, line: line)
        XCTAssertEqual(workingSummary.status, .active, file: file, line: line)
        XCTAssertEqual(workingSummary.sourcePastureName, "Delete Workflow North", file: file, line: line)
        XCTAssertEqual(workingSummary.treatmentTemplateName, "Deletion Contract Work", file: file, line: line)
        XCTAssertEqual(workingSummary.totalQueueItems, 1, file: file, line: line)
        XCTAssertEqual(workingSummary.completedQueueItems, 1, file: file, line: line)

        let controlWorkingEditorAfterDeletion = try XCTUnwrap(
            reloadedWorking.fetchQueueItemEditor(
                sessionID: controlWorkingSessionID,
                queueItemID: controlWorkingQueueItemID
            ),
            "The Working editor must preserve an unrelated queued animal after deleting other pastures.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            controlWorkingEditorAfterDeletion,
            controlWorkingEditorBeforeDeletion,
            "An unrelated Working queue-editor projection must remain unchanged.",
            file: file,
            line: line
        )

        let workingEditor = try XCTUnwrap(
            reloadedWorking.fetchQueueItemEditor(
                sessionID: workingSessionID,
                queueItemID: workingQueueItemID
            ),
            "Working queue/treatment history must survive source-pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingEditor.id, workingQueueItemID, file: file, line: line)
        XCTAssertEqual(workingEditor.sessionID, workingSessionID, file: file, line: line)
        XCTAssertEqual(workingEditor.sessionDate, workingSessionBeforeDeletion.date, file: file, line: line)
        XCTAssertEqual(workingEditor.sessionStatus, .active, file: file, line: line)
        XCTAssertEqual(workingEditor.sessionSourcePastureName, "Delete Workflow North", file: file, line: line)
        XCTAssertEqual(workingEditor.plannedTreatments, [workingTreatment], file: file, line: line)
        XCTAssertEqual(workingEditor.status, .done, file: file, line: line)
        XCTAssertEqual(workingEditor.completedAt, workingCompletedAt, file: file, line: line)
        XCTAssertEqual(workingEditor.collectedFromPastureName, "Delete Workflow North", file: file, line: line)
        XCTAssertEqual(workingEditor.destinationPastureID, secondPasture.id, file: file, line: line)
        XCTAssertEqual(workingEditor.animalID, workingAnimal.id, file: file, line: line)
        XCTAssertEqual(workingEditor.animalDisplayTagNumber, "709", file: file, line: line)
        XCTAssertEqual(workingEditor.animalDisplayTagColorID, animalTagColor.id, file: file, line: line)
        XCTAssertEqual(workingEditor.animalDamDisplayTagNumber, "D700", file: file, line: line)
        XCTAssertEqual(workingEditor.animalDamDisplayTagColorID, damTagColor.id, file: file, line: line)
        XCTAssertEqual(workingEditor.animalSex, .female, file: file, line: line)
        XCTAssertEqual(
            workingEditor.animalAgeInMonths,
            workingAnimalAgeInMonthsBeforeDeletion,
            "Pasture deletion must preserve the Working animal age used for pregnancy eligibility.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingEditor.observationNotes, "Deletion workflow working history", file: file, line: line)
        XCTAssertEqual(workingEditor.treatmentRecords.count, 1, file: file, line: line)
        let workingTreatmentRecord = try XCTUnwrap(workingEditor.treatmentRecords.first, file: file, line: line)
        XCTAssertEqual(
            workingTreatmentRecord.id,
            workingTreatmentRecordIDBeforeDeletion,
            "Pasture deletion must preserve the Working treatment-record application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingTreatmentRecord.date, workingTreatmentRecordedAt, file: file, line: line)
        XCTAssertEqual(workingTreatmentRecord.treatmentItemID, workingTreatment.id, file: file, line: line)
        XCTAssertEqual(workingTreatmentRecord.itemName, workingTreatment.name, file: file, line: line)
        XCTAssertTrue(workingTreatmentRecord.given, file: file, line: line)
        XCTAssertEqual(workingTreatmentRecord.dose.amount, 2.5, file: file, line: line)
        XCTAssertEqual(workingTreatmentRecord.dose.unit, .milliliter, file: file, line: line)
        XCTAssertEqual(workingTreatmentRecord.dose.route, .intramuscular, file: file, line: line)
        let workingPregnancyCheck = try XCTUnwrap(
            workingEditor.pregnancyCheck,
            "Working pregnancy history must survive source-pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingPregnancyCheck.date, workingPregnancyCheckedAt, file: file, line: line)
        XCTAssertEqual(workingPregnancyCheck.result, .pregnant, file: file, line: line)
        XCTAssertEqual(workingPregnancyCheck.estimatedDaysPregnant, 120, file: file, line: line)
        XCTAssertEqual(workingPregnancyCheck.dueDate, workingPregnancyDueDate, file: file, line: line)
        let workingPregnancySire = try XCTUnwrap(
            workingPregnancyCheck.sire,
            "The persisted Working pregnancy snapshot must retain its sire.",
            file: file,
            line: line
        )
        XCTAssertEqual(workingPregnancySire.id, firstPastureSecondAnimal.id, file: file, line: line)
        XCTAssertEqual(workingPregnancySire.name, "Deletion Contract Bull North", file: file, line: line)
        XCTAssertEqual(workingPregnancySire.displayTagNumber, "706", file: file, line: line)
        XCTAssertNil(workingPregnancySire.displayTagColorID, file: file, line: line)
        XCTAssertEqual(workingPregnancySire.sex, .male, file: file, line: line)
        XCTAssertFalse(workingPregnancySire.isArchived, file: file, line: line)

        let finishedWorkingDetail = try XCTUnwrap(
            reloadedWorking.fetchSessionDetail(id: finishedWorkingSessionID),
            "Finished Working sessions must survive deletion of their source pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(finishedWorkingDetail.date, finishedWorkingStartedAt, file: file, line: line)
        XCTAssertEqual(finishedWorkingDetail.status, .finished, file: file, line: line)
        XCTAssertEqual(finishedWorkingDetail.sourcePastureID, secondPasture.id, file: file, line: line)
        XCTAssertEqual(finishedWorkingDetail.sourcePastureName, "Delete Workflow South", file: file, line: line)
        XCTAssertFalse(finishedWorkingDetail.isSourcePastureAvailable, file: file, line: line)
        XCTAssertEqual(finishedWorkingDetail.treatmentTemplateName, "Deletion Contract Finished Work", file: file, line: line)
        XCTAssertTrue(finishedWorkingDetail.plannedTreatments.isEmpty, file: file, line: line)
        XCTAssertEqual(finishedWorkingDetail.queueItems.count, 1, file: file, line: line)
        let finishedWorkingQueueItem = try XCTUnwrap(finishedWorkingDetail.queueItems.first, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.id, finishedWorkingQueueItemID, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.status, .done, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.completedAt, finishedWorkingCompletedAt, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.animalID, finishedWorkingAnimal.id, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.animalName, "Deletion Contract Finished Working Bull", file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.animalDisplayTagNumber, "710", file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.animalDisplayTagColorID, animalTagColor.id, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.animalSex, .male, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.collectedFromPastureID, secondPasture.id, file: file, line: line)
        XCTAssertEqual(finishedWorkingQueueItem.collectedFromPastureName, "Delete Workflow South", file: file, line: line)
        XCTAssertEqual(
            finishedWorkingQueueItem.destinationPastureID,
            secondPasture.id,
            "A nil finish assignment falls back to source and that destination snapshot must survive source-pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(finishedWorkingQueueItem.destinationPastureName, "Delete Workflow South", file: file, line: line)

        let finishedWorkingSummary = try XCTUnwrap(
            workingSummaries.first { $0.id == finishedWorkingSessionID },
            "Finished Working sessions must remain visible through the list reader after source-pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(finishedWorkingSummary.date, finishedWorkingStartedAt, file: file, line: line)
        XCTAssertEqual(finishedWorkingSummary.status, .finished, file: file, line: line)
        XCTAssertEqual(finishedWorkingSummary.sourcePastureName, "Delete Workflow South", file: file, line: line)
        XCTAssertEqual(finishedWorkingSummary.treatmentTemplateName, "Deletion Contract Finished Work", file: file, line: line)
        XCTAssertEqual(finishedWorkingSummary.totalQueueItems, 1, file: file, line: line)
        XCTAssertEqual(finishedWorkingSummary.completedQueueItems, 1, file: file, line: line)

        let finishedWorkingEditor = try XCTUnwrap(
            reloadedWorking.fetchQueueItemEditor(
                sessionID: finishedWorkingSessionID,
                queueItemID: finishedWorkingQueueItemID
            ),
            "Finished Working queue history must survive source-pasture deletion.",
            file: file,
            line: line
        )
        XCTAssertEqual(finishedWorkingEditor.sessionDate, finishedWorkingStartedAt, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.sessionStatus, .finished, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.sessionSourcePastureName, "Delete Workflow South", file: file, line: line)
        XCTAssertTrue(finishedWorkingEditor.plannedTreatments.isEmpty, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.status, .done, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.completedAt, finishedWorkingCompletedAt, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.collectedFromPastureName, "Delete Workflow South", file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.destinationPastureID, secondPasture.id, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.animalID, finishedWorkingAnimal.id, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.animalDisplayTagNumber, "710", file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.animalDisplayTagColorID, animalTagColor.id, file: file, line: line)
        XCTAssertEqual(finishedWorkingEditor.animalSex, .male, file: file, line: line)
        XCTAssertTrue(finishedWorkingEditor.castrationPerformedInSession, file: file, line: line)
        XCTAssertEqual(
            finishedWorkingEditor.observationNotes,
            "Deletion workflow finished working history",
            file: file,
            line: line
        )
        XCTAssertTrue(finishedWorkingEditor.treatmentRecords.isEmpty, file: file, line: line)
        XCTAssertNil(finishedWorkingEditor.pregnancyCheck, file: file, line: line)

        let reloadedFieldChecks = fixture.makeFieldCheckRepository()
        let archivedFirstSessionForIdentity = try XCTUnwrap(
            reloadedFieldChecks.fetchSessionDetail(id: firstSessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            animalCheckIDs(archivedFirstSessionForIdentity.animalChecks),
            firstAnimalCheckIDsBeforeDeletion,
            "Pasture deletion must preserve Field Check animal-check UUIDs in the detail reader.",
            file: file,
            line: line
        )
        let archivedSecondSessionForIdentity = try XCTUnwrap(
            reloadedFieldChecks.fetchSessionDetail(id: secondSessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            animalCheckIDs(archivedSecondSessionForIdentity.animalChecks),
            secondAnimalCheckIDsBeforeDeletion,
            "Pasture deletion must preserve Field Check animal-check UUIDs in the detail reader.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            archivedSecondSessionForIdentity.findings.first?.id,
            secondFindingBeforeDeletion.id,
            "Pasture deletion must preserve Field Check finding UUIDs in the detail reader.",
            file: file,
            line: line
        )

        let firstExpectedAnimals = [
            ExpectedAnimalCheck(
                animalID: firstAnimal.id,
                displayTagNumber: "701",
                displayTagColorID: animalTagColor.id,
                damDisplayTagNumber: "D700",
                damDisplayTagColorID: damTagColor.id,
                animalName: "Deletion Contract Cow North",
                animalSex: .female,
                animalType: .heifer,
                wasExpectedAtStart: true,
                wasCounted: true,
                needsAttention: false,
                isMissing: false
            ),
            ExpectedAnimalCheck(
                animalID: firstPastureSecondAnimal.id,
                displayTagNumber: "706",
                displayTagColorID: nil,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Bull North",
                animalSex: .male,
                animalType: .bull,
                wasExpectedAtStart: true,
                wasCounted: false,
                needsAttention: false,
                isMissing: true
            ),
            ExpectedAnimalCheck(
                animalID: trackedAnimal.id,
                displayTagNumber: "707",
                displayTagColorID: nil,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Tracked Bull",
                animalSex: .male,
                animalType: .bull,
                wasExpectedAtStart: false,
                wasCounted: true,
                needsAttention: false,
                isMissing: false
            )
        ]
        let secondExpectedAnimals = [
            ExpectedAnimalCheck(
                animalID: secondAnimal.id,
                displayTagNumber: "702",
                displayTagColorID: animalTagColor.id,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Cow South",
                animalSex: .female,
                animalType: .heifer,
                wasExpectedAtStart: true,
                wasCounted: false,
                needsAttention: true,
                isMissing: false
            ),
            ExpectedAnimalCheck(
                animalID: trackedAnimal.id,
                displayTagNumber: "707",
                displayTagColorID: nil,
                damDisplayTagNumber: nil,
                damDisplayTagColorID: nil,
                animalName: "Deletion Contract Tracked Bull",
                animalSex: .male,
                animalType: .bull,
                wasExpectedAtStart: true,
                wasCounted: false,
                needsAttention: false,
                isMissing: false
            )
        ]

        try assertArchivedFieldCheckSession(
            sessionID: firstSessionID,
            startedAt: firstStartedAt,
            expectedCompletedAt: firstCompletedAt,
            expectedNotes: firstNotes,
            pastureID: firstPasture.id,
            pastureName: "Delete Workflow North",
            expectedAnimals: firstExpectedAnimals,
            expectedQuickCounts: [:],
            expectedFinding: nil,
            archivedAt: archivedAt,
            repository: reloadedFieldChecks,
            file: file,
            line: line
        )
        try assertArchivedFieldCheckSession(
            sessionID: secondSessionID,
            startedAt: secondStartedAt,
            expectedCompletedAt: nil,
            expectedNotes: secondNotes,
            pastureID: secondPasture.id,
            pastureName: "Delete Workflow South",
            expectedAnimals: secondExpectedAnimals,
            expectedQuickCounts: [.heifer: 1],
            expectedFinding: findingInput,
            archivedAt: archivedAt,
            repository: reloadedFieldChecks,
            file: file,
            line: line
        )

        let controlSession = try XCTUnwrap(
            reloadedFieldChecks.fetchSessionDetail(id: controlSessionID),
            "Field Checks for an unselected pasture must remain current after deleting other pastures.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlSession.startedAt, controlStartedAt, file: file, line: line)
        XCTAssertNil(controlSession.completedAt, file: file, line: line)
        XCTAssertEqual(controlSession.notes, controlNotes, file: file, line: line)
        XCTAssertEqual(controlSession.pastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(controlSession.pastureName, "Delete Workflow Control", file: file, line: line)
        XCTAssertNil(controlSession.pastureArchivedAt, file: file, line: line)
        XCTAssertFalse(controlSession.isPastureArchived, file: file, line: line)
        XCTAssertEqual(controlSession.expectedHeadCountSnapshot, 1, file: file, line: line)
        XCTAssertEqual(controlSession.animalChecks.count, 1, file: file, line: line)
        XCTAssertEqual(controlSession.animalChecks.first?.animalID, controlAnimal.id, file: file, line: line)

        let sessionSummaries = try reloadedFieldChecks.fetchSessions()
        let firstSummaryForIdentity = try XCTUnwrap(
            sessionSummaries.first { $0.id == firstSessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            animalCheckIDs(firstSummaryForIdentity.animalChecks),
            firstAnimalCheckIDsBeforeDeletion,
            "Pasture deletion must preserve Field Check animal-check UUIDs in the list reader.",
            file: file,
            line: line
        )
        let secondSummaryForIdentity = try XCTUnwrap(
            sessionSummaries.first { $0.id == secondSessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            animalCheckIDs(secondSummaryForIdentity.animalChecks),
            secondAnimalCheckIDsBeforeDeletion,
            "Pasture deletion must preserve Field Check animal-check UUIDs in the list reader.",
            file: file,
            line: line
        )

        try assertArchivedFieldCheckSummary(
            sessionID: firstSessionID,
            startedAt: firstStartedAt,
            expectedCompletedAt: firstCompletedAt,
            pastureID: firstPasture.id,
            pastureName: "Delete Workflow North",
            archivedAt: archivedAt,
            expectedAnimals: firstExpectedAnimals,
            expectedQuickCounts: [:],
            expectedOpenFindingsCount: 0,
            summaries: sessionSummaries,
            file: file,
            line: line
        )
        try assertArchivedFieldCheckSummary(
            sessionID: secondSessionID,
            startedAt: secondStartedAt,
            expectedCompletedAt: nil,
            pastureID: secondPasture.id,
            pastureName: "Delete Workflow South",
            archivedAt: archivedAt,
            expectedAnimals: secondExpectedAnimals,
            expectedQuickCounts: [.heifer: 1],
            expectedOpenFindingsCount: 1,
            summaries: sessionSummaries,
            file: file,
            line: line
        )
        let controlSummarySession = try XCTUnwrap(
            sessionSummaries.first { $0.id == controlSessionID },
            "The Field Check list reader must keep sessions for unselected pastures current.",
            file: file,
            line: line
        )
        XCTAssertEqual(controlSummarySession.startedAt, controlStartedAt, file: file, line: line)
        XCTAssertNil(controlSummarySession.completedAt, file: file, line: line)
        XCTAssertEqual(controlSummarySession.pastureID, controlPasture.id, file: file, line: line)
        XCTAssertEqual(controlSummarySession.pastureName, "Delete Workflow Control", file: file, line: line)
        XCTAssertNil(controlSummarySession.pastureArchivedAt, file: file, line: line)
        XCTAssertFalse(controlSummarySession.isPastureArchived, file: file, line: line)
        XCTAssertEqual(controlSummarySession.expectedHeadCountSnapshot, 1, file: file, line: line)
        XCTAssertEqual(controlSummarySession.animalChecks.count, 1, file: file, line: line)
        XCTAssertEqual(controlSummarySession.animalChecks.first?.animalID, controlAnimal.id, file: file, line: line)

        let openFindings = try reloadedFieldChecks.fetchOpenFindings(limit: 100)
        XCTAssertEqual(
            openFindings.count,
            1,
            "The unresolved finding must remain available through the open-findings projection after pasture deletion.",
            file: file,
            line: line
        )
        let openFinding = try XCTUnwrap(
            openFindings.first { $0.sessionID == secondSessionID && $0.animalID == secondAnimal.id },
            "The open-findings projection must retain the archived session's unresolved finding snapshots.",
            file: file,
            line: line
        )
        XCTAssertEqual(openFinding.id, secondFindingBeforeDeletion.id, file: file, line: line)
        XCTAssertEqual(openFinding.recordedAt, findingInput.recordedAt, file: file, line: line)
        XCTAssertEqual(openFinding.type, findingInput.type, file: file, line: line)
        XCTAssertEqual(openFinding.severity, findingInput.severity, file: file, line: line)
        XCTAssertEqual(openFinding.status, findingInput.status, file: file, line: line)
        XCTAssertEqual(openFinding.note, findingInput.note, file: file, line: line)
        XCTAssertEqual(openFinding.animalID, secondAnimal.id, file: file, line: line)
        XCTAssertEqual(openFinding.animalDisplayTagNumber, "702", file: file, line: line)
        XCTAssertEqual(openFinding.animalDisplayTagColorID, animalTagColor.id, file: file, line: line)
        XCTAssertEqual(openFinding.pastureName, "Delete Workflow South", file: file, line: line)
        XCTAssertEqual(openFinding.sessionID, secondSessionID, file: file, line: line)
    }

    private static func makeAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID?,
        tagColorID: UUID? = nil,
        sex: Sex = .female,
        damID: UUID? = nil,
        status: AnimalStatus = .active,
        saleDate: Date? = nil,
        deathDate: Date? = nil
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            sex: sex,
            birthDate: Date(timeIntervalSince1970: 1_577_836_800),
            status: status,
            pastureID: pastureID,
            sireID: nil,
            damID: damID,
            distinguishingFeatures: [],
            saleDate: saleDate,
            salePrice: status == .sold ? 1_250 : nil,
            reasonSold: status == .sold ? "Deletion workflow contract" : nil,
            deathDate: deathDate,
            causeOfDeath: status == .dead ? "Deletion workflow contract" : nil,
            statusReferenceID: nil
        )
    }

    private static func animalCheckIDs(
        _ checks: [FieldCheckAnimalCheckSnapshot]
    ) -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: checks.compactMap { check in
                guard let animalID = check.animalID else { return nil }
                return (animalID, check.id)
            }
        )
    }

    private static func movementDetails(
        animalID: UUID,
        repository: any AnimalRepository
    ) throws -> [String] {
        try repository.fetchTimeline(id: animalID).compactMap { event -> String? in
            guard case .movement = event.type else { return nil }
            return event.details
        }
    }

    private static func movementSnapshots(
        animalID: UUID,
        repository: any AnimalRepository
    ) throws -> [MovementSnapshot] {
        try repository.fetchTimeline(id: animalID).compactMap { event -> MovementSnapshot? in
            guard case .movement = event.type else { return nil }
            return MovementSnapshot(date: event.date, details: event.details)
        }
    }

    private static func assertAnimalMovedToUnassigned(
        animalID: UUID,
        pastureName: String,
        expectedMovementsBeforeDeletion: [MovementSnapshot],
        repository: any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let reloadedAnimal = try XCTUnwrap(
            repository.fetchAnimalDetail(id: animalID),
            file: file,
            line: line
        )
        XCTAssertNil(reloadedAnimal.pastureID, file: file, line: line)
        XCTAssertNil(reloadedAnimal.pastureName, file: file, line: line)

        let deletionMovement = "\(pastureName) → —"
        let movementsAfterDeletion = try movementSnapshots(
            animalID: animalID,
            repository: repository
        )

        XCTAssertEqual(
            movementsAfterDeletion.count,
            expectedMovementsBeforeDeletion.count + 1,
            "Deleting a populated pasture must append exactly one movement for each active resident.",
            file: file,
            line: line
        )

        var unmatchedMovements = movementsAfterDeletion
        for expectedMovement in expectedMovementsBeforeDeletion {
            guard let index = unmatchedMovements.firstIndex(of: expectedMovement) else {
                XCTFail(
                    "Pasture deletion must preserve each prior movement's timestamp and details.",
                    file: file,
                    line: line
                )
                return
            }
            unmatchedMovements.remove(at: index)
        }

        XCTAssertEqual(
            unmatchedMovements.count,
            1,
            "Pasture deletion must preserve prior movement history and append exactly one deletion movement.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            unmatchedMovements.first?.details,
            deletionMovement,
            "Pasture deletion must append the expected \(deletionMovement) transition.",
            file: file,
            line: line
        )
    }

    private static func assertInactiveAnimalSurvivesPastureDeletion(
        animalID: UUID,
        expectedStatus: AnimalStatus,
        expectedArchived: Bool,
        expectedSaleDate: Date? = nil,
        expectedSalePrice: Double? = nil,
        expectedReasonSold: String? = nil,
        expectedDeathDate: Date? = nil,
        expectedCauseOfDeath: String? = nil,
        expectedMovementDetails: [String],
        repository: any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let animal = try XCTUnwrap(
            repository.fetchAnimalDetail(id: animalID),
            "Deleting a pasture must not delete sold, dead, or archived animals that still reference it.",
            file: file,
            line: line
        )
        XCTAssertEqual(animal.status, expectedStatus, file: file, line: line)
        XCTAssertEqual(animal.isArchived, expectedArchived, file: file, line: line)
        XCTAssertEqual(animal.saleDate, expectedSaleDate, file: file, line: line)
        XCTAssertEqual(animal.salePrice, expectedSalePrice, file: file, line: line)
        XCTAssertEqual(animal.reasonSold, expectedReasonSold, file: file, line: line)
        XCTAssertEqual(animal.deathDate, expectedDeathDate, file: file, line: line)
        XCTAssertEqual(animal.causeOfDeath, expectedCauseOfDeath, file: file, line: line)
        XCTAssertNil(animal.pastureID, file: file, line: line)
        XCTAssertNil(animal.pastureName, file: file, line: line)
        XCTAssertEqual(
            try movementDetails(animalID: animalID, repository: repository),
            expectedMovementDetails,
            "Pasture deletion must not append movement events for inactive animals.",
            file: file,
            line: line
        )
    }

    private static func assertArchivedFieldCheckSession(
        sessionID: UUID,
        startedAt: Date,
        expectedCompletedAt: Date?,
        expectedNotes: String,
        pastureID: UUID,
        pastureName: String,
        expectedAnimals: [ExpectedAnimalCheck],
        expectedQuickCounts: [AnimalType: Int],
        expectedFinding: FieldCheckFindingInput?,
        archivedAt: Date,
        repository: any FieldCheckRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let archivedSession = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(archivedSession.startedAt, startedAt, file: file, line: line)
        XCTAssertEqual(archivedSession.completedAt, expectedCompletedAt, file: file, line: line)
        XCTAssertEqual(archivedSession.notes, expectedNotes, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureID, pastureID, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureName, pastureName, file: file, line: line)
        XCTAssertEqual(archivedSession.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(archivedSession.isPastureArchived, file: file, line: line)
        XCTAssertEqual(archivedSession.expectedHeadCountSnapshot, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(archivedSession.animalChecks.count, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(archivedSession.quickCowCount, expectedQuickCounts[.cow, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickHeiferCount, expectedQuickCounts[.heifer, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickCalfCount, expectedQuickCounts[.calf, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickBullCount, expectedQuickCounts[.bull, default: 0], file: file, line: line)
        XCTAssertEqual(archivedSession.quickSteerCount, expectedQuickCounts[.steer, default: 0], file: file, line: line)

        let actualAnimalIDs = archivedSession.animalChecks.compactMap(\.animalID)
        XCTAssertEqual(actualAnimalIDs.count, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(
            Set(actualAnimalIDs),
            Set(expectedAnimals.map(\.animalID)),
            "Deleting a pasture must preserve every Field Check animal snapshot, not only the first.",
            file: file,
            line: line
        )

        for expectedAnimal in expectedAnimals {
            let check = try XCTUnwrap(
                archivedSession.animalChecks.first { $0.animalID == expectedAnimal.animalID },
                file: file,
                line: line
            )
            assertAnimalCheck(check, matches: expectedAnimal, file: file, line: line)
        }

        if let expectedFinding {
            XCTAssertEqual(archivedSession.findings.count, 1, file: file, line: line)
            let finding = try XCTUnwrap(archivedSession.findings.first, file: file, line: line)
            XCTAssertEqual(finding.recordedAt, expectedFinding.recordedAt, file: file, line: line)
            XCTAssertEqual(finding.type, expectedFinding.type, file: file, line: line)
            XCTAssertEqual(finding.severity, expectedFinding.severity, file: file, line: line)
            XCTAssertEqual(finding.status, expectedFinding.status, file: file, line: line)
            XCTAssertEqual(finding.note, expectedFinding.note, file: file, line: line)
            XCTAssertEqual(finding.animalID, expectedFinding.animalID, file: file, line: line)
            XCTAssertEqual(finding.pastureName, pastureName, file: file, line: line)
            XCTAssertEqual(finding.sessionID, sessionID, file: file, line: line)

            if let animalID = expectedFinding.animalID,
               let expectedAnimal = expectedAnimals.first(where: { $0.animalID == animalID }) {
                XCTAssertEqual(
                    finding.animalDisplayTagNumber,
                    expectedAnimal.displayTagNumber,
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    finding.animalDisplayTagColorID,
                    expectedAnimal.displayTagColorID,
                    file: file,
                    line: line
                )
            }
        } else {
            XCTAssertTrue(archivedSession.findings.isEmpty, file: file, line: line)
        }
    }

    private static func assertArchivedFieldCheckSummary(
        sessionID: UUID,
        startedAt: Date,
        expectedCompletedAt: Date?,
        pastureID: UUID,
        pastureName: String,
        archivedAt: Date,
        expectedAnimals: [ExpectedAnimalCheck],
        expectedQuickCounts: [AnimalType: Int],
        expectedOpenFindingsCount: Int,
        summaries: [FieldCheckSessionSummary],
        file: StaticString,
        line: UInt
    ) throws {
        let summary = try XCTUnwrap(
            summaries.first { $0.id == sessionID },
            "Archived field-check sessions must remain visible through the list reader.",
            file: file,
            line: line
        )
        XCTAssertEqual(summary.startedAt, startedAt, file: file, line: line)
        XCTAssertEqual(summary.completedAt, expectedCompletedAt, file: file, line: line)
        XCTAssertEqual(summary.pastureID, pastureID, file: file, line: line)
        XCTAssertEqual(summary.pastureName, pastureName, file: file, line: line)
        XCTAssertEqual(summary.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(summary.isPastureArchived, file: file, line: line)
        XCTAssertEqual(summary.expectedHeadCountSnapshot, expectedAnimals.count, file: file, line: line)
        XCTAssertEqual(summary.quickCowCount, expectedQuickCounts[.cow, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickHeiferCount, expectedQuickCounts[.heifer, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickCalfCount, expectedQuickCounts[.calf, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickBullCount, expectedQuickCounts[.bull, default: 0], file: file, line: line)
        XCTAssertEqual(summary.quickSteerCount, expectedQuickCounts[.steer, default: 0], file: file, line: line)
        XCTAssertEqual(summary.openFindingsCount, expectedOpenFindingsCount, file: file, line: line)
        XCTAssertEqual(summary.animalChecks.count, expectedAnimals.count, file: file, line: line)

        for expectedAnimal in expectedAnimals {
            let check = try XCTUnwrap(
                summary.animalChecks.first { $0.animalID == expectedAnimal.animalID },
                file: file,
                line: line
            )
            assertAnimalCheck(check, matches: expectedAnimal, file: file, line: line)
        }
    }

    private static func assertAnimalCheck(
        _ check: FieldCheckAnimalCheckSnapshot,
        matches expected: ExpectedAnimalCheck,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(check.animalID, expected.animalID, file: file, line: line)
        XCTAssertEqual(check.displayTagNumber, expected.displayTagNumber, file: file, line: line)
        XCTAssertEqual(check.displayTagColorID, expected.displayTagColorID, file: file, line: line)
        XCTAssertEqual(check.damDisplayTagNumber, expected.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(check.damDisplayTagColorID, expected.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(check.animalName, expected.animalName, file: file, line: line)
        XCTAssertEqual(check.animalSex, expected.animalSex, file: file, line: line)
        XCTAssertEqual(check.animalType, expected.animalType, file: file, line: line)
        XCTAssertEqual(check.wasExpectedAtStart, expected.wasExpectedAtStart, file: file, line: line)
        XCTAssertEqual(check.wasCounted, expected.wasCounted, file: file, line: line)
        XCTAssertEqual(check.needsAttention, expected.needsAttention, file: file, line: line)
        XCTAssertEqual(check.isMissing, expected.isMissing, file: file, line: line)
    }
}
