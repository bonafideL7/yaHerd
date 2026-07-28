//
//  SharedWorkingTreatmentRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedWorkingTreatmentRecord)
final class SharedWorkingTreatmentRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var sessionPublicID: String?
    @NSManaged var animalPublicID: String?
    @NSManaged var date: Date?
    @NSManaged var treatmentItemID: String?
    @NSManaged var itemName: String?
    @NSManaged var given: NSNumber?
    @NSManaged var doseAmount: NSNumber?
    @NSManaged var doseUnitRawValue: String?
    @NSManaged var administrationRouteRawValue: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var session: SharedWorkingSessionRecord?
    @NSManaged var animal: SharedAnimalRecord?

    /// Transitional source compatibility for pre-release bridge code.
    var quantity: NSNumber? {
        get { doseAmount }
        set { doseAmount = newValue }
    }
}

extension SharedWorkingTreatmentRecord {
    static let entityName = "SharedWorkingTreatmentRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedWorkingTreatmentRecord> {
        NSFetchRequest<SharedWorkingTreatmentRecord>(entityName: entityName)
    }

    func mirror(
        _ treatmentRecord: WorkingTreatmentRecord,
        herdPublicID: UUID,
        mirroredAt: Date = Date.now
    ) {
        publicID = treatmentRecord.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        sessionPublicID = treatmentRecord.session?.publicID.uuidString
        animalPublicID = treatmentRecord.animal?.publicID.uuidString
        date = treatmentRecord.date
        treatmentItemID = treatmentRecord.treatmentItemID.uuidString
        itemName = treatmentRecord.itemName
        given = NSNumber(value: treatmentRecord.given)
        doseAmount = treatmentRecord.doseAmount.map { NSNumber(value: $0) }
        doseUnitRawValue = treatmentRecord.doseUnit?.rawValue
        administrationRouteRawValue = treatmentRecord.administrationRoute?.rawValue
        lastMirroredAt = mirroredAt
    }
}

extension SharedWorkingTreatmentRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedSessionPublicID: UUID? {
        guard let sessionPublicID else { return nil }
        return UUID(uuidString: sessionPublicID)
    }

    var parsedAnimalPublicID: UUID? {
        guard let animalPublicID else { return nil }
        return UUID(uuidString: animalPublicID)
    }

    var parsedTreatmentItemID: UUID? {
        guard let treatmentItemID else { return nil }
        return UUID(uuidString: treatmentItemID)
    }

    var parsedDose: WorkingTreatmentDose {
        WorkingTreatmentDose(
            amount: doseAmount?.doubleValue,
            unit: doseUnitRawValue.flatMap(WorkingTreatmentDoseUnit.init(rawValue:)),
            route: administrationRouteRawValue.flatMap(
                WorkingTreatmentAdministrationRoute.init(rawValue:)
            )
        )
    }
}
