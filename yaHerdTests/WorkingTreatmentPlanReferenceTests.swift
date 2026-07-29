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
            from: entries,
            including: firstID
        )
        XCTAssertEqual(firstUpdate.map(\.id), [firstID])

        entries[0].isPlanned = true
        let secondUpdate = WorkingSessionTreatmentPlanBuilder.items(
            from: entries,
            including: secondID
        )

        XCTAssertEqual(secondUpdate.map(\.id), [firstID, secondID])
        XCTAssertEqual(secondUpdate.map(\.name), ["First Vaccine", "Second Vaccine"])
    }
}
