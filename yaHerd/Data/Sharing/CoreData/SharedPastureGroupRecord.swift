//
//  SharedPastureGroupRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedPastureGroupRecord)
final class SharedPastureGroupRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var name: String?
    @NSManaged var grazeDays: NSNumber?
    @NSManaged var restDays: NSNumber?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var pastures: Set<SharedPastureRecord>?
}

extension SharedPastureGroupRecord {
    static let entityName = "SharedPastureGroupRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedPastureGroupRecord> {
        NSFetchRequest<SharedPastureGroupRecord>(entityName: entityName)
    }

    func mirror(_ group: PastureGroup, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = group.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        name = group.name
        grazeDays = NSNumber(value: group.grazeDays)
        restDays = NSNumber(value: group.restDays)
        lastMirroredAt = mirroredAt
    }
}

extension SharedPastureGroupRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }
}
