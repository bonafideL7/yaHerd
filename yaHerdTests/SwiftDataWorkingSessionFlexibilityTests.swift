import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataWorkingSessionFlexibilityTests: XCTestCase {
    func testActiveSessionCanAddTreatmentAfterStart() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)
        let fixture = try makeFixture(in: context)

        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: fixture.sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: [fixture.animal.publicID]
            )
        )
        let addedTreatment = WorkingTreatmentPlanItem(
            name: "Forgotten Vaccine",
            suggestedDose: WorkingTreatmentDose(
                amount: 2,
                unit: .milliliter,
                route: .subcutaneous
            )
        )

        try repository.updateSessionTreatments(
            id: sessionID,
            plannedTreatments: [addedTreatment]
        )

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(detail.plannedTreatments, [addedTreatment])
    }

    func testAnimalCanReceiveOneOffTreatmentNotInSessionPlan() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)
        let fixture = try makeFixture(in: context)

        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: fixture.sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: [fixture.animal.publicID]
            )
        )
        let queueItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingQueueItem>()).first
        )
        let oneOffID = UUID()

        try repository.saveEdits(
            forQueueItemID: queueItem.publicID,
            inSessionID: sessionID,
            input: WorkingSessionAnimalEditInput(
                status: .done,
                completedAt: .now,
                destinationPastureID: fixture.destinationPasture.publicID,
                treatmentEntries: [
                    WorkingTreatmentEntryInput(
                        date: .now,
                        treatmentItemID: oneOffID,
                        itemName: "One-Off Antibiotic",
                        given: true,
                        dose: WorkingTreatmentDose(
                            amount: 8,
                            unit: .milliliter,
                            route: .intramuscular
                        )
                    )
                ],
                pregnancyCheck: nil,
                castrationPerformed: false,
                observationNotes: ""
            )
        )

        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingTreatmentRecord>()).first
        )
        XCTAssertEqual(record.treatmentItemID, oneOffID)
        XCTAssertEqual(record.itemName, "One-Off Antibiotic")
        XCTAssertEqual(record.doseAmount, 8)

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(detail.queueItems.first?.destinationPastureID, fixture.destinationPasture.publicID)
    }

    func testSelectedDestinationMovesAnimalWhenSessionFinishes() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)
        let fixture = try makeFixture(in: context)

        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: fixture.sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: [fixture.animal.publicID]
            )
        )
        let queueItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingQueueItem>()).first
        )

        try repository.completeSession(
            id: sessionID,
            assignments: [
                WorkingQueueDestinationAssignment(
                    queueItemID: queueItem.publicID,
                    destinationPastureID: fixture.destinationPasture.publicID
                )
            ]
        )

        XCTAssertEqual(fixture.animal.pasture?.publicID, fixture.destinationPasture.publicID)
        XCTAssertEqual(fixture.animal.location, .pasture)
    }

    private func makeFixture(
        in context: ModelContext
    ) throws -> (
        sourcePasture: Pasture,
        destinationPasture: Pasture,
        animal: Animal
    ) {
        let sourcePasture = Pasture(name: "North")
        let destinationPasture = Pasture(name: "South")
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        animal.pasture = sourcePasture
        context.insert(sourcePasture)
        context.insert(destinationPasture)
        context.insert(animal)
        try context.save()
        return (sourcePasture, destinationPasture, animal)
    }
}
