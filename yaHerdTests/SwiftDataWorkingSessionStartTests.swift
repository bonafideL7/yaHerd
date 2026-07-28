import XCTest
import SwiftData
@testable import yaHerd

@MainActor
final class SwiftDataWorkingSessionStartTests: XCTestCase {
    func testStartSessionIncludesAllEligibleAnimalsByDefault() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let first = Animal(name: "Cow 1", tagNumber: "1", birthDate: .distantPast, status: .active, sex: .female)
        let second = Animal(name: "Cow 2", tagNumber: "2", birthDate: .distantPast, status: .active, sex: .female)
        let archived = Animal(name: "Cow 3", tagNumber: "3", birthDate: .distantPast, status: .sold, sex: .female)
        first.pasture = pasture
        second.pasture = pasture
        archived.pasture = pasture
        context.insert(pasture)
        context.insert(first)
        context.insert(second)
        context.insert(archived)
        try context.save()

        let inputDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 14)))
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: inputDate,
                sourcePastureID: pasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: nil
            )
        )

        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingSession>()).first { $0.publicID == sessionID }
        )
        XCTAssertEqual(session.queueItems.count, 2)
        XCTAssertEqual(session.date, Calendar.autoupdatingCurrent.startOfDay(for: inputDate))
        XCTAssertTrue(session.queueItems.allSatisfy { $0.queueOrder == 0 })
        XCTAssertEqual(session.currentQueueIndex, 0)
        XCTAssertEqual(first.location, .workingPen)
        XCTAssertEqual(second.location, .workingPen)
        XCTAssertEqual(archived.location, .pasture)
    }

    func testStartSessionUsesExplicitAnimalSelectionAndSnapshotsDoseIdentity() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataWorkingRepository(context: context)

        let pasture = Pasture(name: "North")
        let first = Animal(name: "Cow 1", tagNumber: "1", birthDate: .distantPast, status: .active, sex: .female)
        let second = Animal(name: "Cow 2", tagNumber: "2", birthDate: .distantPast, status: .active, sex: .female)
        first.pasture = pasture
        second.pasture = pasture
        context.insert(pasture)
        context.insert(first)
        context.insert(second)
        try context.save()

        let treatmentItemID = UUID()
        let plannedTreatment = WorkingTreatmentPlanItem(
            id: treatmentItemID,
            name: "7-way",
            suggestedDose: WorkingTreatmentDose(
                amount: 2,
                unit: .milliliter,
                route: .subcutaneous
            )
        )
        let sessionID = try repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: pasture.publicID,
                treatmentTemplateName: "Spring Vaccines",
                plannedTreatments: [plannedTreatment],
                animalIDs: [second.publicID]
            )
        )

        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingSession>()).first { $0.publicID == sessionID }
        )
        XCTAssertEqual(session.queueItems.map { $0.animal?.publicID }, [second.publicID])
        XCTAssertEqual(session.protocolName, "Spring Vaccines")
        XCTAssertEqual(session.protocolItems.first?.id, treatmentItemID)
        XCTAssertEqual(session.protocolItems.first?.suggestedDose.amount, 2)
        XCTAssertEqual(session.protocolItems.first?.suggestedDose.unit, .milliliter)
        XCTAssertEqual(session.protocolItems.first?.suggestedDose.route, .subcutaneous)
        XCTAssertEqual(session.currentQueueIndex, 0)
        XCTAssertEqual(session.queueItems.first?.queueOrder, 0)
        XCTAssertEqual(first.location, .pasture)
        XCTAssertEqual(second.location, .workingPen)
    }
}
