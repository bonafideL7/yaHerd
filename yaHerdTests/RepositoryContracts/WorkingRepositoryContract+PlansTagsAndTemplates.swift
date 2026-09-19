import Foundation
import XCTest
@testable import yaHerd

@MainActor
extension WorkingRepositoryContract {
    static func assertSessionTreatmentPlanAndPrimaryTagReplacementPersist(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Plan Source", using: fixture)
        let replacementColor = TagColorSnapshot(
            name: "Working Replacement Tag Color",
            prefix: "WRT",
            rgba: RGBAColor(r: 0.3, g: 0.6, b: 0.9)
        )
        try fixture.makeTagColorRepository().upsert(replacementColor)
        let animal = try makeAnimal(name: "Plan Tag Cow", tagNumber: "801", sex: .female, pastureID: source.id, using: fixture)
        let originalTagID = try XCTUnwrap(animal.activeTags.first { $0.isPrimary }?.id, file: file, line: line)
        let originalTreatment = WorkingTreatmentPlanItem(id: UUID(), name: "Original Vaccine")
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 9, day: 26),
                sourcePastureID: source.id,
                treatmentTemplateName: "Plan Contract",
                plannedTreatments: [originalTreatment],
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id, file: file, line: line)

        let updatedTreatments = [
            WorkingTreatmentPlanItem(
                id: originalTreatment.id,
                name: "Original Vaccine Renamed",
                suggestedDose: WorkingTreatmentDose(amount: 3, unit: .milliliter, route: .subcutaneous)
            ),
            WorkingTreatmentPlanItem(
                id: UUID(),
                name: "Added Treatment",
                suggestedDose: WorkingTreatmentDose(amount: 1, unit: .dose, route: .oral)
            )
        ]
        try repository.updateSessionTreatments(id: sessionID, plannedTreatments: updatedTreatments)

        let afterPlanReload = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(afterPlanReload.plannedTreatments, updatedTreatments, file: file, line: line)
        let editorAfterPlan = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        XCTAssertEqual(editorAfterPlan.plannedTreatments, updatedTreatments, file: file, line: line)

        let duplicateID = UUID()
        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().updateSessionTreatments(
                id: sessionID,
                plannedTreatments: [
                    WorkingTreatmentPlanItem(id: duplicateID, name: "Duplicate One"),
                    WorkingTreatmentPlanItem(id: duplicateID, name: "Duplicate Two")
                ]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateTreatmentItemIdentifiers, file: file, line: line)
        }
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?.plannedTreatments,
            updatedTreatments,
            "Invalid treatment-plan replacement must leave the durable plan unchanged.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().updateSessionTreatments(
                id: sessionID,
                plannedTreatments: [
                    WorkingTreatmentPlanItem(
                        id: UUID(),
                        name: "Negative Dose Plan",
                        suggestedDose: WorkingTreatmentDose(
                            amount: -1,
                            unit: .milliliter
                        )
                    )
                ]
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
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?.plannedTreatments,
            updatedTreatments,
            "Invalid suggested doses must fail before replacing the active session plan.",
            file: file,
            line: line
        )

        let replacement = try fixture.makeWorkingRepository().replacePrimaryTag(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: WorkingTagReplacementInput(number: "  901  ", colorID: replacementColor.id)
        )
        XCTAssertEqual(replacement.animalDisplayTagNumber, "901", file: file, line: line)
        XCTAssertEqual(replacement.animalDisplayTagColorID, replacementColor.id, file: file, line: line)

        let animalAfterReplacement = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        let replacementTag = try XCTUnwrap(
            animalAfterReplacement.activeTags.first { $0.isPrimary },
            file: file,
            line: line
        )
        XCTAssertEqual(replacementTag.number, "901", file: file, line: line)
        XCTAssertEqual(replacementTag.colorID, replacementColor.id, file: file, line: line)
        XCTAssertNotEqual(replacementTag.id, originalTagID, "Tag replacement must create a new application identity.", file: file, line: line)
        let retiredOriginal = try XCTUnwrap(
            animalAfterReplacement.inactiveTags.first { $0.id == originalTagID },
            file: file,
            line: line
        )
        XCTAssertEqual(retiredOriginal.number, "801", file: file, line: line)
        XCTAssertFalse(retiredOriginal.isActive, file: file, line: line)
        XCTAssertNotNil(retiredOriginal.removedAt, file: file, line: line)

        let queueAfterReplacement = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?.queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(queueAfterReplacement.animalDisplayTagNumber, "901", file: file, line: line)
        XCTAssertEqual(
            queueAfterReplacement.animalDisplayTagColorID,
            replacementColor.id,
            "Working tag replacement updates the queue's captured tag display state for this session.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().replacePrimaryTag(
                forQueueItemID: queueItemID,
                inSessionID: sessionID,
                input: WorkingTagReplacementInput(number: "   ", colorID: nil)
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .invalidTagNumber, file: file, line: line)
        }
        let afterInvalidReplacement = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(afterInvalidReplacement.activeTags, animalAfterReplacement.activeTags, file: file, line: line)
        XCTAssertEqual(afterInvalidReplacement.inactiveTags, animalAfterReplacement.inactiveTags, file: file, line: line)

        try fixture.makeWorkingRepository().completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItemID,
                    destinationPastureID: source.id
                )
            ]
        )

        _ = try fixture.makeAnimalRepository().updateTag(
            animalID: animal.id,
            tagID: replacementTag.id,
            input: AnimalTagInput(
                number: "902",
                colorID: nil,
                isPrimary: true
            )
        )
        let liveAfterLaterEdit = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(liveAfterLaterEdit.displayTagNumber, "902", file: file, line: line)

        let historicalAfterLaterEdit = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            historicalAfterLaterEdit.animalDisplayTagNumber,
            "901",
            "After Working captures a replacement tag, later unrelated Animal tag edits must not rewrite the finished Working history.",
            file: file,
            line: line
        )
        XCTAssertEqual(historicalAfterLaterEdit.animalDisplayTagColorID, replacementColor.id, file: file, line: line)
    }

    static func assertTreatmentTemplateCRUDAndOrdering(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeWorkingRepository()
        let firstItems = [
            WorkingTreatmentPlanItem(
                id: UUID(),
                name: "Template Vaccine",
                suggestedDose: WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous)
            )
        ]
        let zuluID = try repository.createTemplate(name: "  Zulu Template  ", items: firstItems)
        let alphaID = try repository.createTemplate(name: "Alpha Template", items: [])

        let reloaded = fixture.makeWorkingRepository()
        let summaries = try reloaded.fetchTemplates()
        let contractSummaries = summaries.filter { $0.id == zuluID || $0.id == alphaID }
        XCTAssertEqual(contractSummaries.map(\.id), [alphaID, zuluID], "Template list projection should be sorted by name.", file: file, line: line)
        XCTAssertEqual(contractSummaries.first { $0.id == zuluID }?.name, "Zulu Template", file: file, line: line)
        XCTAssertEqual(contractSummaries.first { $0.id == zuluID }?.treatmentCount, 1, file: file, line: line)

        let zuluDetail = try XCTUnwrap(reloaded.fetchTemplateDetail(id: zuluID), file: file, line: line)
        XCTAssertEqual(zuluDetail.id, zuluID, file: file, line: line)
        XCTAssertEqual(zuluDetail.name, "Zulu Template", file: file, line: line)
        XCTAssertEqual(zuluDetail.plannedTreatments, firstItems, file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().createTemplate(name: " alpha template ", items: []),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateTemplateName("alpha template"), file: file, line: line)
        }

        let updatedItems = [
            WorkingTreatmentPlanItem(id: firstItems[0].id, name: "Template Vaccine Updated"),
            WorkingTreatmentPlanItem(id: UUID(), name: "Template Dewormer")
        ]
        try fixture.makeWorkingRepository().updateTemplate(
            id: zuluID,
            name: "  Aardvark Template  ",
            items: updatedItems
        )
        let updated = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchTemplateDetail(id: zuluID),
            file: file,
            line: line
        )
        XCTAssertEqual(updated.id, zuluID, "Updating a template must preserve its application UUID.", file: file, line: line)
        XCTAssertEqual(updated.name, "Aardvark Template", file: file, line: line)
        XCTAssertEqual(updated.plannedTreatments, updatedItems, file: file, line: line)

        let reorderedAfterRename = try fixture.makeWorkingRepository().fetchTemplates()
            .filter { $0.id == zuluID || $0.id == alphaID }
        XCTAssertEqual(
            reorderedAfterRename.map(\.id),
            [zuluID, alphaID],
            "Renaming a template must affect the persisted name-sorted list projection on the next read.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().updateTemplate(id: zuluID, name: "ALPHA TEMPLATE", items: updatedItems),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .duplicateTemplateName("ALPHA TEMPLATE"), file: file, line: line)
        }
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchTemplateDetail(id: zuluID)?.name,
            "Aardvark Template",
            file: file,
            line: line
        )

        let missingTemplateID = UUID()
        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().deleteTemplates(
                ids: [alphaID, missingTemplateID]
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .templateNotFound,
                file: file,
                line: line
            )
        }
        XCTAssertNotNil(
            try fixture.makeWorkingRepository().fetchTemplateDetail(id: alphaID),
            "A mixed valid/missing template-delete request must fail before deleting the valid template.",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            try fixture.makeWorkingRepository().fetchTemplateDetail(id: zuluID),
            file: file,
            line: line
        )

        try fixture.makeWorkingRepository().deleteTemplates(ids: [alphaID, zuluID, alphaID])
        XCTAssertNil(try fixture.makeWorkingRepository().fetchTemplateDetail(id: alphaID), file: file, line: line)
        XCTAssertNil(try fixture.makeWorkingRepository().fetchTemplateDetail(id: zuluID), file: file, line: line)
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertTemplateChangesDoNotRewriteExistingSessionSnapshot(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Template Snapshot Source", using: fixture)
        let animal = try makeAnimal(name: "Template Snapshot Cow", tagNumber: "TS101", sex: .female, pastureID: source.id, using: fixture)
        let repository = fixture.makeWorkingRepository()
        let originalItems = [
            WorkingTreatmentPlanItem(
                id: UUID(),
                name: "Snapshot Vaccine",
                suggestedDose: WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous)
            )
        ]
        let templateID = try repository.createTemplate(name: "Snapshot Template", items: originalItems)
        let template = try XCTUnwrap(repository.fetchTemplateDetail(id: templateID), file: file, line: line)
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 7),
                sourcePastureID: source.id,
                treatmentTemplateName: template.name,
                plannedTreatments: template.plannedTreatments,
                animalIDs: [animal.id]
            )
        )
        let beforeTemplateChange = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(beforeTemplateChange.treatmentTemplateName, "Snapshot Template", file: file, line: line)
        XCTAssertEqual(beforeTemplateChange.plannedTreatments, originalItems, file: file, line: line)

        let replacementItems = [
            WorkingTreatmentPlanItem(id: UUID(), name: "Replacement Template Treatment")
        ]
        try fixture.makeWorkingRepository().updateTemplate(
            id: templateID,
            name: "Renamed Snapshot Template",
            items: replacementItems
        )
        try fixture.makeWorkingRepository().deleteTemplates(ids: [templateID])

        let afterTemplateDeletion = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterTemplateDeletion.treatmentTemplateName,
            "Snapshot Template",
            "A session keeps the template name captured when it started; later template edits are not historical rewrites.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterTemplateDeletion.plannedTreatments,
            originalItems,
            "A session keeps its copied treatment plan even after the reusable template is edited or deleted.",
            file: file,
            line: line
        )
        XCTAssertNil(try fixture.makeWorkingRepository().fetchTemplateDetail(id: templateID), file: file, line: line)

        let savedFromSessionTemplateID = try fixture.makeWorkingRepository().createTemplate(
            name: "Saved Session Plan",
            items: afterTemplateDeletion.plannedTreatments
        )
        let savedFromSessionBeforePlanEdit = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchTemplateDetail(id: savedFromSessionTemplateID),
            file: file,
            line: line
        )
        XCTAssertEqual(savedFromSessionBeforePlanEdit.plannedTreatments, originalItems, file: file, line: line)

        let laterSessionPlan = [
            WorkingTreatmentPlanItem(id: UUID(), name: "Later Session-Only Treatment")
        ]
        try fixture.makeWorkingRepository().updateSessionTreatments(
            id: sessionID,
            plannedTreatments: laterSessionPlan
        )

        let savedFromSessionAfterPlanEdit = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchTemplateDetail(id: savedFromSessionTemplateID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            savedFromSessionAfterPlanEdit.plannedTreatments,
            originalItems,
            "Saving the current session plan as a reusable template copies value snapshots; later session-plan edits must not rewrite that template.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?.plannedTreatments,
            laterSessionPlan,
            file: file,
            line: line
        )
    }

    static func assertSessionPlanChangesDoNotDeleteRecordedTreatmentHistory(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Treatment History Source", using: fixture)
        let animal = try makeAnimal(name: "Treatment History Cow", tagNumber: "TH201", sex: .female, pastureID: source.id, using: fixture)
        let originalTreatmentID = UUID()
        let originalPlan = [
            WorkingTreatmentPlanItem(id: originalTreatmentID, name: "Historical Vaccine")
        ]
        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 8),
                sourcePastureID: source.id,
                treatmentTemplateName: "History Plan",
                plannedTreatments: originalPlan,
                animalIDs: [animal.id]
            )
        )
        let queueItemID = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID)?.queueItems.first?.id, file: file, line: line)
        let recordDate = date(year: 2026, month: 10, day: 8, hour: 9)
        try repository.complete(
            queueItemID: queueItemID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: recordDate,
                    treatmentItemID: originalTreatmentID,
                    itemName: "Historical Vaccine",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous)
                )
            ],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )
        let recorded = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        let historicalRecord = try XCTUnwrap(recorded.treatmentRecords.first, file: file, line: line)
        XCTAssertEqual(historicalRecord.treatmentItemID, originalTreatmentID, file: file, line: line)

        let replacementPlan = [
            WorkingTreatmentPlanItem(id: UUID(), name: "Current Plan Treatment")
        ]
        try fixture.makeWorkingRepository().updateSessionTreatments(
            id: sessionID,
            plannedTreatments: replacementPlan
        )

        let afterPlanChange = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID),
            file: file,
            line: line
        )
        XCTAssertEqual(afterPlanChange.plannedTreatments, replacementPlan, file: file, line: line)
        let preservedRecord = try XCTUnwrap(
            afterPlanChange.treatmentRecords.first { $0.treatmentItemID == originalTreatmentID },
            file: file,
            line: line
        )
        XCTAssertEqual(preservedRecord.id, historicalRecord.id, "Editing the plan must not recreate or replace an already-recorded treatment event.", file: file, line: line)
        XCTAssertEqual(preservedRecord.date, recordDate, file: file, line: line)
        XCTAssertEqual(preservedRecord.itemName, "Historical Vaccine", file: file, line: line)
        XCTAssertEqual(
            preservedRecord.dose,
            WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous),
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertCompletedQueueHistorySurvivesLiveAnimalDeletion(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Historical Animal Source", using: fixture)
        let tagColorRepository = fixture.makeTagColorRepository()
        let calfColor = TagColorSnapshot(
            name: "Working Historical Calf Color",
            prefix: "HC",
            rgba: RGBAColor(r: 0.2, g: 0.6, b: 0.8)
        )
        let damColor = TagColorSnapshot(
            name: "Working Historical Dam Color",
            prefix: "HD",
            rgba: RGBAColor(r: 0.8, g: 0.5, b: 0.2)
        )
        try tagColorRepository.upsert(calfColor)
        try tagColorRepository.upsert(damColor)

        let dam = try makeAnimal(
            name: "Working Historical Dam",
            tagNumber: "D501",
            sex: .female,
            pastureID: source.id,
            tagColorID: damColor.id,
            using: fixture
        )
        let calf = try makeAnimal(
            name: "Working Historical Calf",
            tagNumber: "501",
            sex: .male,
            pastureID: source.id,
            tagColorID: calfColor.id,
            damID: dam.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 11),
                sourcePastureID: source.id,
                treatmentTemplateName: "Historical Animal Snapshot",
                plannedTreatments: [],
                animalIDs: [calf.id]
            )
        )
        let started = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let queueItem = try XCTUnwrap(started.queueItems.first, file: file, line: line)

        try repository.saveEdits(
            forQueueItemID: queueItem.id,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: nil,
                destinationPastureID: source.id,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: ""
            )
        )
        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItem.id,
                    destinationPastureID: source.id
                )
            ]
        )

        let beforeDeletion = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let historicalBeforeDeletion = try XCTUnwrap(
            beforeDeletion.queueItems.first { $0.id == queueItem.id },
            file: file,
            line: line
        )
        XCTAssertEqual(historicalBeforeDeletion.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(historicalBeforeDeletion.animalName, "Working Historical Calf", file: file, line: line)
        XCTAssertEqual(historicalBeforeDeletion.animalDisplayTagNumber, "501", file: file, line: line)
        XCTAssertEqual(historicalBeforeDeletion.animalDisplayTagColorID, calfColor.id, file: file, line: line)
        XCTAssertEqual(historicalBeforeDeletion.animalDamDisplayTagNumber, "D501", file: file, line: line)
        XCTAssertEqual(historicalBeforeDeletion.animalDamDisplayTagColorID, damColor.id, file: file, line: line)
        XCTAssertEqual(historicalBeforeDeletion.animalSex, .male, file: file, line: line)
        XCTAssertEqual(historicalBeforeDeletion.collectedFromPastureID, source.id, file: file, line: line)

        let animalRepository = fixture.makeAnimalRepository()
        try animalRepository.archive(ids: [calf.id, dam.id])
        try animalRepository.delete(ids: [calf.id, dam.id])
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: calf.id),
            file: file,
            line: line
        )
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: dam.id),
            file: file,
            line: line
        )

        let afterDeletion = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            "Completed Working history must survive hard deletion of its live Animal relationship.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDeletion.status, .finished, file: file, line: line)
        let historicalAfterDeletion = try XCTUnwrap(
            afterDeletion.queueItems.first { $0.id == queueItem.id },
            "Hard-deleting an Animal must not delete its completed Working queue history.",
            file: file,
            line: line
        )
        XCTAssertEqual(historicalAfterDeletion.id, historicalBeforeDeletion.id, file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.animalName, "Working Historical Calf", file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.animalDisplayTagNumber, "501", file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.animalDisplayTagColorID, calfColor.id, file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.animalDamDisplayTagNumber, "D501", file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.animalDamDisplayTagColorID, damColor.id, file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.animalSex, .male, file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.collectedFromPastureID, source.id, file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.collectedFromPastureName, "Working Historical Animal Source", file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.destinationPastureID, source.id, file: file, line: line)
        XCTAssertEqual(historicalAfterDeletion.destinationPastureName, "Working Historical Animal Source", file: file, line: line)

        let summaryAfterDeletion = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessions().first { $0.id == sessionID },
            "Hard-deleting the live Animal must not remove the completed Working session from the list projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterDeletion.status, .finished, file: file, line: line)
        XCTAssertEqual(summaryAfterDeletion.totalQueueItems, 1, file: file, line: line)
        XCTAssertEqual(summaryAfterDeletion.completedQueueItems, 1, file: file, line: line)
    }
}

@MainActor
extension WorkingRepositoryContract {
    static func assertTreatmentTemplatePlanValidationDoesNotPartiallyWrite(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeWorkingRepository()
        let originalItems = [
            WorkingTreatmentPlanItem(
                id: UUID(),
                name: "Template Validation Baseline",
                suggestedDose: WorkingTreatmentDose(
                    amount: 2,
                    unit: .milliliter
                )
            )
        ]
        let templateID = try repository.createTemplate(
            name: "Template Validation",
            items: originalItems
        )
        let beforeTemplate = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchTemplateDetail(id: templateID),
            file: file,
            line: line
        )
        let beforeList = try fixture.makeWorkingRepository().fetchTemplates()

        let duplicateID = UUID()
        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().createTemplate(
                name: "Invalid Duplicate Item Template",
                items: [
                    WorkingTreatmentPlanItem(id: duplicateID, name: "Duplicate One"),
                    WorkingTreatmentPlanItem(id: duplicateID, name: "Duplicate Two")
                ]
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
        XCTAssertEqual(
            try fixture.makeWorkingRepository().fetchTemplates(),
            beforeList,
            "Invalid template creation must not append a partially-created template.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeWorkingRepository().updateTemplate(
                id: templateID,
                name: "Template Validation Mutated",
                items: [
                    WorkingTreatmentPlanItem(
                        id: originalItems[0].id,
                        name: "Invalid Negative Template Dose",
                        suggestedDose: WorkingTreatmentDose(
                            amount: -1,
                            unit: .milliliter
                        )
                    )
                ]
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
            try fixture.makeWorkingRepository().fetchTemplateDetail(id: templateID),
            beforeTemplate,
            "Invalid template updates must preserve the existing durable name and item payload.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    /// Target Core Data historical-snapshot behavior. After a session is finished, later edits to
    /// live Animal/Dam tag display state must not rewrite the queue snapshots captured for history.
    static func assertCompletedQueueHistoryIgnoresLaterAnimalDisplayChanges(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working Immutable Display Source", using: fixture)
        let tagColorRepository = fixture.makeTagColorRepository()
        let originalCalfColor = TagColorSnapshot(
            name: "Working Immutable Calf Original",
            prefix: "ICO",
            rgba: RGBAColor(r: 0.1, g: 0.4, b: 0.8)
        )
        let replacementCalfColor = TagColorSnapshot(
            name: "Working Immutable Calf Replacement",
            prefix: "ICR",
            rgba: RGBAColor(r: 0.8, g: 0.2, b: 0.4)
        )
        let originalDamColor = TagColorSnapshot(
            name: "Working Immutable Dam Original",
            prefix: "IDO",
            rgba: RGBAColor(r: 0.2, g: 0.7, b: 0.3)
        )
        let replacementDamColor = TagColorSnapshot(
            name: "Working Immutable Dam Replacement",
            prefix: "IDR",
            rgba: RGBAColor(r: 0.7, g: 0.3, b: 0.7)
        )
        for color in [
            originalCalfColor,
            replacementCalfColor,
            originalDamColor,
            replacementDamColor
        ] {
            try tagColorRepository.upsert(color)
        }

        let dam = try makeAnimal(
            name: "Working Immutable Dam",
            tagNumber: "D601",
            sex: .female,
            pastureID: source.id,
            tagColorID: originalDamColor.id,
            using: fixture
        )
        let calf = try makeAnimal(
            name: "Working Immutable Calf",
            tagNumber: "601",
            sex: .male,
            pastureID: source.id,
            tagColorID: originalCalfColor.id,
            damID: dam.id,
            using: fixture
        )
        let calfPrimaryTagID = try XCTUnwrap(
            calf.activeTags.first { $0.isPrimary }?.id,
            file: file,
            line: line
        )
        let damPrimaryTagID = try XCTUnwrap(
            dam.activeTags.first { $0.isPrimary }?.id,
            file: file,
            line: line
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 16),
                sourcePastureID: source.id,
                treatmentTemplateName: "Immutable Display History",
                plannedTreatments: [],
                animalIDs: [calf.id]
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
                destinationPastureID: source.id,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: ""
            )
        )
        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItemID,
                    destinationPastureID: source.id
                )
            ]
        )

        let beforeChange = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(beforeChange.animalName, "Working Immutable Calf", file: file, line: line)
        XCTAssertEqual(beforeChange.animalDisplayTagNumber, "601", file: file, line: line)
        XCTAssertEqual(beforeChange.animalDisplayTagColorID, originalCalfColor.id, file: file, line: line)
        XCTAssertEqual(beforeChange.animalDamDisplayTagNumber, "D601", file: file, line: line)
        XCTAssertEqual(beforeChange.animalDamDisplayTagColorID, originalDamColor.id, file: file, line: line)
        XCTAssertEqual(beforeChange.collectedFromPastureID, source.id, file: file, line: line)

        let animalRepository = fixture.makeAnimalRepository()
        _ = try animalRepository.updateTag(
            animalID: calf.id,
            tagID: calfPrimaryTagID,
            input: AnimalTagInput(
                number: "699",
                colorID: replacementCalfColor.id,
                isPrimary: true
            )
        )
        _ = try animalRepository.updateTag(
            animalID: dam.id,
            tagID: damPrimaryTagID,
            input: AnimalTagInput(
                number: "D699",
                colorID: replacementDamColor.id,
                isPrimary: true
            )
        )

        let renamedCalf = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: calf.id),
            file: file,
            line: line
        )
        _ = try animalRepository.update(
            id: calf.id,
            input: AnimalInput(
                name: "Working Immutable Calf Renamed",
                tagNumber: renamedCalf.displayTagNumber,
                tagColorID: renamedCalf.displayTagColorID,
                sex: .female,
                birthDate: renamedCalf.birthDate,
                status: renamedCalf.status,
                pastureID: renamedCalf.pastureID,
                sireID: renamedCalf.sireID,
                damID: renamedCalf.damID,
                distinguishingFeatures: renamedCalf.distinguishingFeatures,
                saleDate: renamedCalf.saleDate,
                salePrice: renamedCalf.salePrice,
                reasonSold: renamedCalf.reasonSold,
                deathDate: renamedCalf.deathDate,
                causeOfDeath: renamedCalf.causeOfDeath,
                statusReferenceID: renamedCalf.statusReferenceID
            )
        )

        let liveCalf = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimals().first { $0.id == calf.id },
            file: file,
            line: line
        )
        XCTAssertEqual(liveCalf.name, "Working Immutable Calf Renamed", file: file, line: line)
        XCTAssertEqual(liveCalf.sex, .female, file: file, line: line)
        XCTAssertEqual(liveCalf.displayTagNumber, "699", file: file, line: line)
        XCTAssertEqual(liveCalf.displayTagColorID, replacementCalfColor.id, file: file, line: line)
        XCTAssertEqual(liveCalf.damDisplayTagNumber, "D699", file: file, line: line)
        XCTAssertEqual(liveCalf.damDisplayTagColorID, replacementDamColor.id, file: file, line: line)

        let afterChange = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(afterChange.id, beforeChange.id, file: file, line: line)
        XCTAssertEqual(afterChange.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(
            afterChange.animalName,
            "Working Immutable Calf",
            "Completed Working history must not follow later live Animal name edits.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterChange.animalDisplayTagNumber,
            "601",
            "Completed Working history must not follow later live Animal tag-number edits.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterChange.animalDisplayTagColorID, originalCalfColor.id, file: file, line: line)
        XCTAssertEqual(afterChange.animalDamDisplayTagNumber, "D601", file: file, line: line)
        XCTAssertEqual(afterChange.animalDamDisplayTagColorID, originalDamColor.id, file: file, line: line)
        XCTAssertEqual(afterChange.animalSex, .male, file: file, line: line)
        XCTAssertEqual(afterChange.collectedFromPastureID, source.id, file: file, line: line)

        try animalRepository.archive(ids: [dam.id])
        try animalRepository.delete(ids: [dam.id])

        let liveCalfAfterDamDeletion = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimals().first { $0.id == calf.id },
            file: file,
            line: line
        )
        XCTAssertNil(
            liveCalfAfterDamDeletion.damDisplayTagNumber,
            "The live Animal projection should reflect that its Dam relationship was deleted.",
            file: file,
            line: line
        )
        XCTAssertNil(liveCalfAfterDamDeletion.damDisplayTagColorID, file: file, line: line)

        let afterDamDeletion = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID)?
                .queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(afterDamDeletion.animalID, calf.id, file: file, line: line)
        XCTAssertEqual(afterDamDeletion.animalName, "Working Immutable Calf", file: file, line: line)
        XCTAssertEqual(afterDamDeletion.animalDamDisplayTagNumber, "D601", file: file, line: line)
        XCTAssertEqual(
            afterDamDeletion.animalDamDisplayTagColorID,
            originalDamColor.id,
            "Deleting only the live Dam must not erase the Working queue's captured dam-tag history while the queue Animal remains live.",
            file: file,
            line: line
        )
    }
}

@MainActor
extension WorkingRepositoryContract {
    /// Target Core Data history: later pasture renames must not rewrite completed Working snapshots.
    static func assertCompletedQueueHistoryIgnoresLaterPastureRenames(
        using fixture: WorkingRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try makePasture(named: "Working History Source Original", using: fixture)
        let destination = try makePasture(named: "Working History Destination Original", using: fixture)
        let animal = try makeAnimal(
            name: "Working History Pasture Cow",
            tagNumber: "HP101",
            sex: .female,
            pastureID: source.id,
            using: fixture
        )

        let repository = fixture.makeWorkingRepository()
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: date(year: 2026, month: 10, day: 18),
                sourcePastureID: source.id,
                treatmentTemplateName: "Pasture Snapshot History",
                plannedTreatments: [],
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
                destinationPastureID: destination.id,
                treatmentEntries: [],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: ""
            )
        )
        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItemID,
                    destinationPastureID: destination.id
                )
            ]
        )

        let beforeRename = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeQueue = try XCTUnwrap(
            beforeRename.queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(beforeRename.sourcePastureID, source.id, file: file, line: line)
        XCTAssertEqual(beforeRename.sourcePastureName, "Working History Source Original", file: file, line: line)
        XCTAssertEqual(beforeQueue.collectedFromPastureID, source.id, file: file, line: line)
        XCTAssertEqual(beforeQueue.collectedFromPastureName, "Working History Source Original", file: file, line: line)
        XCTAssertEqual(beforeQueue.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertEqual(beforeQueue.destinationPastureName, "Working History Destination Original", file: file, line: line)

        let pastureRepository = fixture.makePastureRepository()
        _ = try pastureRepository.update(
            id: source.id,
            input: PastureInput(
                name: "Working History Source Renamed",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try pastureRepository.update(
            id: destination.id,
            input: PastureInput(
                name: "Working History Destination Renamed",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )

        XCTAssertEqual(
            try fixture.makePastureRepository().fetchPastureDetail(id: source.id)?.name,
            "Working History Source Renamed",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makePastureRepository().fetchPastureDetail(id: destination.id)?.name,
            "Working History Destination Renamed",
            file: file,
            line: line
        )

        let afterRename = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let afterQueue = try XCTUnwrap(
            afterRename.queueItems.first { $0.id == queueItemID },
            file: file,
            line: line
        )
        XCTAssertEqual(afterRename.sourcePastureID, source.id, file: file, line: line)
        XCTAssertEqual(afterRename.sourcePastureName, "Working History Source Original", file: file, line: line)
        XCTAssertTrue(
            afterRename.isSourcePastureAvailable,
            "Renaming the live source pasture must not make the historical source identity unusable.",
            file: file,
            line: line
        )

        let summaryAfterRename = try XCTUnwrap(
            fixture.makeWorkingRepository().fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            summaryAfterRename.sourcePastureName,
            "Working History Source Original",
            "The Working list projection must use the captured source-pasture name rather than a later live rename.",
            file: file,
            line: line
        )

        XCTAssertEqual(afterQueue.collectedFromPastureID, source.id, file: file, line: line)
        XCTAssertEqual(afterQueue.collectedFromPastureName, "Working History Source Original", file: file, line: line)
        XCTAssertEqual(afterQueue.destinationPastureID, destination.id, file: file, line: line)
        XCTAssertEqual(afterQueue.destinationPastureName, "Working History Destination Original", file: file, line: line)
    }
}

