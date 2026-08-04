import XCTest

@testable import yaHerd

@MainActor
final class CollaborationFieldSnapshotProviderTests: XCTestCase {
    func testTreatmentSnapshotIncludesEveryExportedSemanticField() {
        let treatmentItemID = UUID()
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        let session = WorkingSession(
            protocolName: "Spring Working",
            protocolItems: []
        )
        let treatment = WorkingTreatmentRecord(
            date: Date(timeIntervalSince1970: 1_800_000_000.125),
            treatmentItemID: treatmentItemID,
            itemName: "Vaccine A",
            given: true,
            dose: WorkingTreatmentDose(
                amount: 2.5,
                unit: .milliliter,
                route: .intramuscular
            ),
            animal: animal,
            session: session
        )

        let snapshot = CollaborationFieldSnapshotProvider.snapshot(for: treatment)

        XCTAssertEqual(snapshot["treatmentItemID"]?.encodedValue, treatmentItemID.uuidString)
        XCTAssertEqual(snapshot["doseAmount"]?.encodedValue, "2.5")
        XCTAssertEqual(
            snapshot["doseUnitRawValue"]?.encodedValue,
            WorkingTreatmentDoseUnit.milliliter.rawValue
        )
        XCTAssertEqual(
            snapshot["administrationRouteRawValue"]?.encodedValue,
            WorkingTreatmentAdministrationRoute.intramuscular.rawValue
        )
        XCTAssertEqual(snapshot["sessionPublicID"]?.encodedValue, session.publicID.uuidString)
        XCTAssertEqual(snapshot["animalPublicID"]?.encodedValue, animal.publicID.uuidString)
        XCTAssertNil(snapshot["doseUnit"])
        XCTAssertNil(snapshot["administrationRoute"])
    }

    func testSnapshotDatesPreserveFractionalSeconds() {
        let herd = Herd(name: "Fractional Date Herd")
        herd.updatedAt = Date(timeIntervalSince1970: 1_800_000_000.125)
        let firstSnapshot = CollaborationFieldSnapshotProvider.snapshot(for: herd)

        herd.updatedAt = Date(timeIntervalSince1970: 1_800_000_000.875)
        let secondSnapshot = CollaborationFieldSnapshotProvider.snapshot(for: herd)

        let firstValue = firstSnapshot["updatedAt"]?.encodedValue
        let secondValue = secondSnapshot["updatedAt"]?.encodedValue
        XCTAssertNotEqual(firstValue, secondValue)
        XCTAssertTrue(firstValue?.contains(".125") == true)
        XCTAssertTrue(secondValue?.contains(".875") == true)
    }
}
