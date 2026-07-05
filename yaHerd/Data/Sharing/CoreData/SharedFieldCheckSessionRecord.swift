//
//  SharedFieldCheckSessionRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedFieldCheckSessionRecord)
final class SharedFieldCheckSessionRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var startedAt: Date?
    @NSManaged var completedAt: Date?
    @NSManaged var notes: String?
    @NSManaged var expectedHeadCountSnapshot: NSNumber?
    @NSManaged var quickCowCount: NSNumber?
    @NSManaged var quickHeiferCount: NSNumber?
    @NSManaged var quickCalfCount: NSNumber?
    @NSManaged var quickBullCount: NSNumber?
    @NSManaged var quickSteerCount: NSNumber?
    @NSManaged var pastureNameSnapshot: String?
    @NSManaged var pastureArchivedAt: Date?
    @NSManaged var pasturePublicID: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var animalChecks: Set<SharedFieldCheckAnimalCheckRecord>?
    @NSManaged var findings: Set<SharedFieldCheckFindingRecord>?
}

extension SharedFieldCheckSessionRecord {
    static let entityName = "SharedFieldCheckSessionRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedFieldCheckSessionRecord> {
        NSFetchRequest<SharedFieldCheckSessionRecord>(entityName: entityName)
    }

    func mirror(_ session: FieldCheckSession, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = session.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        startedAt = session.startedAt
        completedAt = session.completedAt
        notes = session.notes
        expectedHeadCountSnapshot = NSNumber(value: session.expectedHeadCountSnapshot)
        quickCowCount = NSNumber(value: session.quickCowCount)
        quickHeiferCount = NSNumber(value: session.quickHeiferCount)
        quickCalfCount = NSNumber(value: session.quickCalfCount)
        quickBullCount = NSNumber(value: session.quickBullCount)
        quickSteerCount = NSNumber(value: session.quickSteerCount)
        pastureNameSnapshot = session.pastureNameSnapshot
        pastureArchivedAt = session.pastureArchivedAt
        pasturePublicID = session.pasture?.publicID.uuidString ?? session.pastureID?.uuidString
        lastMirroredAt = mirroredAt
    }
}

extension SharedFieldCheckSessionRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedPasturePublicID: UUID? {
        guard let pasturePublicID else { return nil }
        return UUID(uuidString: pasturePublicID)
    }
}
