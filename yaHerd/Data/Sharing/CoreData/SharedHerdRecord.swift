//
//  SharedHerdRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedHerdRecord)
final class SharedHerdRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var schemaVersion: NSNumber?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var animals: Set<SharedAnimalRecord>?
}

extension SharedHerdRecord {
    static let entityName = "SharedHerdRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedHerdRecord> {
        NSFetchRequest<SharedHerdRecord>(entityName: entityName)
    }

    func mirror(_ herd: HerdSummary, mirroredAt: Date = Date.now) {
        publicID = herd.publicID.uuidString
        name = herd.name
        createdAt = herd.createdAt
        updatedAt = herd.updatedAt
        schemaVersion = NSNumber(value: herd.schemaVersion)
        lastMirroredAt = mirroredAt
    }
}

extension SharedHerdRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }
}
