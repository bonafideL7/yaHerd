import XCTest

@testable import yaHerd

@MainActor
final class CollaborationRevisionReviewCommentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CollaborationRevisionRegistry.resetForTesting()
        CollaborationIdentityProvider.resetForTesting()
    }

    override func tearDown() {
        CollaborationRevisionRegistry.resetForTesting()
        CollaborationIdentityProvider.resetForTesting()
        super.tearDown()
    }

    func testAnimalSnapshotIncludesParentLinks() {
        let sire = Animal(
            name: "Bull 7",
            tagNumber: "7",
            birthDate: .distantPast,
            status: .active,
            sex: .male
        )
        let dam = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        let calf = Animal(
            name: "Calf 21",
            tagNumber: "21",
            birthDate: .now,
            status: .active,
            sireAnimal: sire,
            damAnimal: dam,
            sex: .female
        )

        let snapshot = CollaborationFieldSnapshotProvider.snapshot(for: calf)

        XCTAssertEqual(
            snapshot["sireAnimalPublicID"],
            HerdSharingBridgeConflictValue(
                type: .uuid,
                encodedValue: sire.publicID.uuidString
            )
        )
        XCTAssertEqual(
            snapshot["damAnimalPublicID"],
            HerdSharingBridgeConflictValue(
                type: .uuid,
                encodedValue: dam.publicID.uuidString
            )
        )

        calf.sireAnimal = nil
        let updatedSnapshot = CollaborationFieldSnapshotProvider.snapshot(for: calf)
        XCTAssertEqual(updatedSnapshot["sireAnimalPublicID"], .null)
        XCTAssertNotEqual(snapshot, updatedSnapshot)
    }

    func testTreatmentSnapshotIncludesStableIdentityAndStructuredDoseFields() {
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        let session = WorkingSession(
            protocolName: "Treatment Snapshot",
            protocolItems: []
        )
        let treatmentItemID = UUID()
        let treatment = WorkingTreatmentRecord(
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

        XCTAssertEqual(
            snapshot["treatmentItemID"],
            HerdSharingBridgeConflictValue(
                type: .uuid,
                encodedValue: treatmentItemID.uuidString
            )
        )
        XCTAssertEqual(
            snapshot["doseAmount"],
            HerdSharingBridgeConflictValue(type: .double, encodedValue: "2.5")
        )
        XCTAssertEqual(
            snapshot["doseUnitRawValue"],
            HerdSharingBridgeConflictValue(
                type: .string,
                encodedValue: WorkingTreatmentDoseUnit.milliliter.rawValue
            )
        )
        XCTAssertEqual(
            snapshot["administrationRouteRawValue"],
            HerdSharingBridgeConflictValue(
                type: .string,
                encodedValue: WorkingTreatmentAdministrationRoute.intramuscular.rawValue
            )
        )
        XCTAssertNil(snapshot["quantity"])
    }

    func testSynthesizedDeletionAdvancesLiveRevisionOnce() {
        let publicID = UUID()
        let key = CollaborationAggregateKey(
            type: .workingTreatmentRecord,
            publicID: publicID
        )
        let fields: CollaborationFieldSnapshot = [
            "itemName": HerdSharingBridgeConflictValue(
                type: .string,
                encodedValue: "Vaccine A"
            )
        ]
        let liveMetadata = CollaborationRevisionMetadata(
            modifiedAt: Date(timeIntervalSince1970: 100),
            revision: 4,
            modifiedByParticipantID: "participant-before-delete",
            modifiedByDeviceID: "device-before-delete",
            baseRevision: 3,
            baseFieldValues: fields,
            currentFieldValues: fields,
            isDeleted: false
        )
        CollaborationRevisionRegistry.registerAuthoritativeLocal(
            liveMetadata,
            for: key
        )
        let deletionIdentity = CollaborationIdentityProvider.current()
        let deletedAt = Date(timeIntervalSince1970: 200)

        let deletionMetadata = HerdSharingCoreDataStore.deletionMetadata(
            publicID: publicID.uuidString,
            sourceEntityName: SharedWorkingTreatmentRecord.entityName,
            mirroredAt: deletedAt
        )

        XCTAssertTrue(deletionMetadata.isDeleted)
        XCTAssertEqual(deletionMetadata.revision, 5)
        XCTAssertEqual(deletionMetadata.baseRevision, 4)
        XCTAssertEqual(deletionMetadata.modifiedAt, deletedAt)
        XCTAssertEqual(
            deletionMetadata.modifiedByParticipantID,
            deletionIdentity.participantID
        )
        XCTAssertEqual(
            deletionMetadata.modifiedByDeviceID,
            deletionIdentity.deviceID
        )
        XCTAssertEqual(deletionMetadata.baseFieldValues, fields)
        XCTAssertEqual(deletionMetadata.currentFieldValues, fields)
        XCTAssertEqual(
            CollaborationRevisionRegistry.localMetadata(for: key),
            deletionMetadata
        )

        let repeatedMetadata = HerdSharingCoreDataStore.deletionMetadata(
            publicID: publicID.uuidString,
            sourceEntityName: SharedWorkingTreatmentRecord.entityName,
            mirroredAt: Date(timeIntervalSince1970: 300)
        )
        XCTAssertEqual(repeatedMetadata, deletionMetadata)
    }
}
