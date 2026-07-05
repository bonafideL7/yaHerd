//
//  SharedHealthRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedHealthRecord)
final class SharedHealthRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var animalPublicID: String?
    @NSManaged var date: Date?
    @NSManaged var treatment: String?
    @NSManaged var notes: String?
    @NSManaged var workingSessionPublicID: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedHealthRecord {
    static let entityName = "SharedHealthRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedHealthRecord> {
        NSFetchRequest<SharedHealthRecord>(entityName: entityName)
    }

    func mirror(_ healthRecord: HealthRecord, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = healthRecord.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        animalPublicID = healthRecord.animal?.publicID.uuidString
        date = healthRecord.date
        treatment = healthRecord.treatment
        notes = healthRecord.notes
        workingSessionPublicID = healthRecord.workingSession?.publicID.uuidString
        lastMirroredAt = mirroredAt
    }
}

extension SharedHealthRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedAnimalPublicID: UUID? {
        guard let animalPublicID else { return nil }
        return UUID(uuidString: animalPublicID)
    }

    var parsedWorkingSessionPublicID: UUID? {
        guard let workingSessionPublicID else { return nil }
        return UUID(uuidString: workingSessionPublicID)
    }
}
