//
//  SharedStatusRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedStatusRecord)
final class SharedStatusRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var animalPublicID: String?
    @NSManaged var date: Date?
    @NSManaged var oldStatusRawValue: String?
    @NSManaged var newStatusRawValue: String?
    @NSManaged var oldStatusReferenceID: String?
    @NSManaged var newStatusReferenceID: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedStatusRecord {
    static let entityName = "SharedStatusRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedStatusRecord> {
        NSFetchRequest<SharedStatusRecord>(entityName: entityName)
    }

    func mirror(_ statusRecord: StatusRecord, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = statusRecord.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        animalPublicID = statusRecord.animal?.publicID.uuidString
        date = statusRecord.date
        oldStatusRawValue = statusRecord.oldStatus.rawValue
        newStatusRawValue = statusRecord.newStatus.rawValue
        oldStatusReferenceID = statusRecord.oldStatusReferenceID?.uuidString
        newStatusReferenceID = statusRecord.newStatusReferenceID?.uuidString
        lastMirroredAt = mirroredAt
    }
}

extension SharedStatusRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedAnimalPublicID: UUID? {
        guard let animalPublicID else { return nil }
        return UUID(uuidString: animalPublicID)
    }

    var parsedOldStatus: AnimalStatus {
        guard let oldStatusRawValue else { return .active }
        return AnimalStatus(rawValue: oldStatusRawValue) ?? .active
    }

    var parsedNewStatus: AnimalStatus {
        guard let newStatusRawValue else { return .active }
        return AnimalStatus(rawValue: newStatusRawValue) ?? .active
    }

    var parsedOldStatusReferenceID: UUID? {
        guard let oldStatusReferenceID else { return nil }
        return UUID(uuidString: oldStatusReferenceID)
    }

    var parsedNewStatusReferenceID: UUID? {
        guard let newStatusReferenceID else { return nil }
        return UUID(uuidString: newStatusReferenceID)
    }
}
