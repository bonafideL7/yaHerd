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
    @NSManaged var itemName: String?
    @NSManaged var given: NSNumber?
    @NSManaged var quantity: NSNumber?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var session: SharedWorkingSessionRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedWorkingTreatmentRecord {
    static let entityName = "SharedWorkingTreatmentRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedWorkingTreatmentRecord> {
        NSFetchRequest<SharedWorkingTreatmentRecord>(entityName: entityName)
    }

    func mirror(_ treatmentRecord: WorkingTreatmentRecord, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = treatmentRecord.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        sessionPublicID = treatmentRecord.session?.publicID.uuidString
        animalPublicID = treatmentRecord.animal?.publicID.uuidString
        date = treatmentRecord.date
        itemName = treatmentRecord.itemName
        given = NSNumber(value: treatmentRecord.given)
        quantity = treatmentRecord.quantity.map { NSNumber(value: $0) }
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
}
