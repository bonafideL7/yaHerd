import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class WorkingTreatmentDoseSchemaTests: XCTestCase {
    func testTreatmentRecordPersistsStableItemIdentityAndStructuredDose() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let treatmentItemID = UUID()
        let plannedTreatment = WorkingTreatmentPlanItem(
            id: treatmentItemID,
            name: "Vaccine A",
            suggestedDose: WorkingTreatmentDose(
                amount: 2,
                unit: .milliliter,
                route: .subcutaneous
            )
        )
        let sessionID = try repository.createSession(
            date: .now,
            sourcePastureID: pasture.publicID,
            protocolName: "Spring Work",
            protocolItems: [plannedTreatment]
        )
        try repository.collectAnimals(sessionID: sessionID, animalIDs: [animal.publicID])

        let queueItem = try XCTUnwrap(context.fetch(FetchDescriptor<WorkingQueueItem>()).first)
        try repository.complete(
            queueItemID: queueItem.publicID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: .now,
                    treatmentItemID: treatmentItemID,
                    itemName: "Vaccine A",
                    given: true,
                    dose: WorkingTreatmentDose(
                        amount: 2.5,
                        unit: .milliliter,
                        route: .intramuscular
                    )
                )
            ],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )

        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingTreatmentRecord>()).first
        )
        XCTAssertEqual(record.treatmentItemID, treatmentItemID)
        XCTAssertEqual(record.doseAmount, 2.5)
        XCTAssertEqual(record.doseUnit, .milliliter)
        XCTAssertEqual(record.administrationRoute, .intramuscular)

        let editor = try XCTUnwrap(
            repository.fetchQueueItemEditor(
                sessionID: sessionID,
                queueItemID: queueItem.publicID
            )
        )
        let snapshot = try XCTUnwrap(editor.treatmentRecords.first)
        XCTAssertEqual(snapshot.id, record.publicID)
        XCTAssertEqual(snapshot.treatmentItemID, treatmentItemID)
        XCTAssertEqual(snapshot.dose.amount, 2.5)
        XCTAssertEqual(snapshot.dose.unit, .milliliter)
        XCTAssertEqual(snapshot.dose.route, .intramuscular)
    }

    func testTreatmentRecordIdentitySurvivesPlanItemRename() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let treatmentItemID = UUID()
        let sessionID = try repository.createSession(
            date: .now,
            sourcePastureID: pasture.publicID,
            protocolName: "Spring Work",
            protocolItems: [
                WorkingTreatmentPlanItem(id: treatmentItemID, name: "Original Name")
            ]
        )
        try repository.collectAnimals(sessionID: sessionID, animalIDs: [animal.publicID])
        let queueItem = try XCTUnwrap(context.fetch(FetchDescriptor<WorkingQueueItem>()).first)

        try repository.complete(
            queueItemID: queueItem.publicID,
            inSessionID: sessionID,
            treatmentEntries: [
                WorkingTreatmentEntryInput(
                    date: .now,
                    treatmentItemID: treatmentItemID,
                    itemName: "Original Name",
                    given: true,
                    dose: WorkingTreatmentDose(amount: 1, unit: .dose, route: .oral)
                )
            ],
            pregnancyCheck: nil,
            markCastrated: false,
            observationNotes: ""
        )

        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingSession>()).first { $0.publicID == sessionID }
        )
        var renamedItems = session.protocolItems
        renamedItems[0].name = "Renamed Treatment"
        session.protocolItems = renamedItems
        try context.save()

        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingTreatmentRecord>()).first
        )
        XCTAssertEqual(session.protocolItems.first?.id, treatmentItemID)
        XCTAssertEqual(record.treatmentItemID, treatmentItemID)
        XCTAssertEqual(record.itemName, "Original Name")
    }

    func testTreatmentPlanRulesRejectDuplicateIdentifiersAndNegativeDose() {
        let duplicateID = UUID()
        XCTAssertThrowsError(
            try WorkingTreatmentPlanRules.validate([
                WorkingTreatmentPlanItem(id: duplicateID, name: "A"),
                WorkingTreatmentPlanItem(id: duplicateID, name: "B")
            ])
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .duplicateTreatmentItemIdentifiers
            )
        }

        XCTAssertThrowsError(
            try WorkingTreatmentPlanRules.validate([
                WorkingTreatmentPlanItem(
                    name: "A",
                    suggestedDose: WorkingTreatmentDose(
                        amount: -1,
                        unit: .milliliter,
                        route: .subcutaneous
                    )
                )
            ])
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .invalidTreatmentDose)
        }
    }

    func testCollectionNoLongerAssignsQueueOrdering() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let firstAnimal = Animal(
            name: "Cow 2",
            tagNumber: "2",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        let secondAnimal = Animal(
            name: "Cow 10",
            tagNumber: "10",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        firstAnimal.pasture = pasture
        secondAnimal.pasture = pasture
        context.insert(pasture)
        context.insert(firstAnimal)
        context.insert(secondAnimal)
        try context.save()

        let sessionID = try repository.createSession(
            date: .now,
            sourcePastureID: pasture.publicID,
            protocolName: "Working Session",
            protocolItems: []
        )
        try repository.collectAnimals(
            sessionID: sessionID,
            animalIDs: [secondAnimal.publicID, firstAnimal.publicID]
        )

        let items = try context.fetch(FetchDescriptor<WorkingQueueItem>())
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.queueOrder == 0 })

        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingSession>()).first { $0.publicID == sessionID }
        )
        XCTAssertEqual(session.currentQueueIndex, 0)
    }
}
