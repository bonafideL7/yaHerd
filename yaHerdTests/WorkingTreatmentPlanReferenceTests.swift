import XCTest
@testable import yaHerd

@MainActor
final class WorkingTreatmentPlanReferenceTests: XCTestCase {
    func testAllowsOneOffTreatmentOutsideSessionPlan() throws {
        let plannedTreatment = WorkingTreatmentPlanItem(name: "Vaccine A")
        let oneOffEntry = WorkingTreatmentEntryInput(
            date: .now,
            treatmentItemID: UUID(),
            itemName: "Antibiotic",
            given: true,
            dose: WorkingTreatmentDose(
                amount: 8,
                unit: .milliliter,
                route: .intramuscular
            )
        )

        XCTAssertNoThrow(
            try WorkingTreatmentPlanRules.validate(
                [oneOffEntry],
                against: [plannedTreatment]
            )
        )
    }

    func testBuildsRepeatedSessionUpdatesFromCurrentPlannedEntries() {
        let firstID = UUID()
        let secondID = UUID()
        var entries = [
            WorkingAnimalTreatmentEntry(
                id: firstID,
                name: "First Vaccine",
                given: true,
                dose: WorkingTreatmentDose(amount: 2, unit: .milliliter),
                isPlanned: false
            ),
            WorkingAnimalTreatmentEntry(
                id: secondID,
                name: "Second Vaccine",
                given: true,
                dose: WorkingTreatmentDose(amount: 3, unit: .milliliter),
                isPlanned: false
            )
        ]

        let firstUpdate = WorkingSessionTreatmentPlanBuilder.items(
            preserving: [],
            from: entries,
            including: firstID
        )
        XCTAssertEqual(firstUpdate.map(\.id), [firstID])

        entries[0].isPlanned = true
        let secondUpdate = WorkingSessionTreatmentPlanBuilder.items(
            preserving: [],
            from: entries,
            including: secondID
        )

        XCTAssertEqual(secondUpdate.map(\.id), [firstID, secondID])
        XCTAssertEqual(secondUpdate.map(\.name), ["First Vaccine", "Second Vaccine"])
    }

    func testPromotingOneOffPreservesExistingSessionSuggestedDose() {
        let existingID = UUID()
        let oneOffID = UUID()
        let sessionDose = WorkingTreatmentDose(
            amount: 5,
            unit: .milliliter,
            route: .intramuscular
        )
        let recordedAnimalDose = WorkingTreatmentDose(
            amount: 2,
            unit: .milliliter,
            route: .subcutaneous
        )
        let promotedDose = WorkingTreatmentDose(
            amount: 1.5,
            unit: .cubicCentimeter,
            route: .oral
        )
        let existingItem = WorkingTreatmentPlanItem(
            id: existingID,
            name: "Session Vaccine",
            suggestedDose: sessionDose
        )
        let entries = [
            WorkingAnimalTreatmentEntry(
                id: existingID,
                name: "Session Vaccine",
                given: true,
                dose: recordedAnimalDose,
                isPlanned: true
            ),
            WorkingAnimalTreatmentEntry(
                id: oneOffID,
                name: "One-Off Treatment",
                given: true,
                dose: promotedDose,
                isPlanned: false
            )
        ]

        let updatedItems = WorkingSessionTreatmentPlanBuilder.items(
            preserving: [existingItem],
            from: entries,
            including: oneOffID
        )

        XCTAssertEqual(updatedItems.map(\.id), [existingID, oneOffID])
        XCTAssertEqual(updatedItems[0].suggestedDose, sessionDose)
        XCTAssertEqual(updatedItems[1].suggestedDose, promotedDose)
    }
}
