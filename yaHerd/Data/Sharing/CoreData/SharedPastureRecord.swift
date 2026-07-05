//
//  SharedPastureRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedPastureRecord)
final class SharedPastureRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var name: String?
    @NSManaged var sortOrder: NSNumber?
    @NSManaged var acreage: NSNumber?
    @NSManaged var usableAcreage: NSNumber?
    @NSManaged var targetAcresPerHead: NSNumber?
    @NSManaged var lastGrazedDate: Date?
    @NSManaged var groupPublicID: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var group: SharedPastureGroupRecord?
}

extension SharedPastureRecord {
    static let entityName = "SharedPastureRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedPastureRecord> {
        NSFetchRequest<SharedPastureRecord>(entityName: entityName)
    }

    func mirror(_ pasture: Pasture, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = pasture.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        name = pasture.name
        sortOrder = NSNumber(value: pasture.sortOrder)
        acreage = pasture.acreage.map { NSNumber(value: $0) }
        usableAcreage = pasture.usableAcreage.map { NSNumber(value: $0) }
        targetAcresPerHead = pasture.targetAcresPerHead.map { NSNumber(value: $0) }
        lastGrazedDate = pasture.lastGrazedDate
        groupPublicID = pasture.group?.publicID.uuidString
        lastMirroredAt = mirroredAt
    }
}

extension SharedPastureRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedGroupPublicID: UUID? {
        guard let groupPublicID else { return nil }
        return UUID(uuidString: groupPublicID)
    }
}
