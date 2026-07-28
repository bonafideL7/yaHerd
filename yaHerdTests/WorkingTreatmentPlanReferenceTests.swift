import XCTest
@testable import yaHerd

final class WorkingTreatmentPlanReferenceTests: XCTestCase {
    func testRejectsTreatmentEntryOutsideSessionPlan() {
        let plannedTreatment = WorkingTreatmentPlanItem(name: "Vaccine A")
        let unrelatedEntry = WorkingTreatmentEntryInput(
            date: .now,
            treatmentItemID: UUID(),
            itemName: "Vaccine A",
            given: true,
            dose: WorkingTreatmentDose(amount: 2, unit: .milliliter, route: .subcutaneous)
        )

        XCTAssertThrowsError(
            try WorkingTreatmentPlanRules.validate(
                [unrelatedEntry],
                against: [plannedTreatment]
            )
        ) { error in
            XCTAssertEqual(error as? WorkingRepositoryError, .treatmentItemNotInSession)
        }
    }
}
