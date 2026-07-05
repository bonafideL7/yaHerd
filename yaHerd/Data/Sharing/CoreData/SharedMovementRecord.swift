//
//  SharedMovementRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedMovementRecord)
final class SharedMovementRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var animalPublicID: String?
    @NSManaged var date: Date?
    @NSManaged var fromPasture: String?
    @NSManaged var toPasture: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedMovementRecord {
    static let entityName = "SharedMovementRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedMovementRecord> {
        NSFetchRequest<SharedMovementRecord>(entityName: entityName)
    }

    func mirror(_ movement: MovementRecord, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = movement.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        animalPublicID = movement.animal?.publicID.uuidString
        date = movement.date
        fromPasture = movement.fromPasture
        toPasture = movement.toPasture
        lastMirroredAt = mirroredAt
    }
}

extension SharedMovementRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedAnimalPublicID: UUID? {
        guard let animalPublicID else { return nil }
        return UUID(uuidString: animalPublicID)
    }
}
