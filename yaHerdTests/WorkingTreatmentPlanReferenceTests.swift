import XCTest
@testable import yaHerd

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
}
