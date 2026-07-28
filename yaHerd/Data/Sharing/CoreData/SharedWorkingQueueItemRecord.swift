//
//  SharedWorkingQueueItemRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedWorkingQueueItemRecord)
final class SharedWorkingQueueItemRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var sessionPublicID: String?
    @NSManaged var animalPublicID: String?
    /// Deprecated V1 bridge storage. New exports leave this field unset.
    @NSManaged var queueOrder: NSNumber?
    @NSManaged var statusRawValue: String?
    @NSManaged var completedAt: Date?
    @NSManaged var collectedFromPasturePublicID: String?
    @NSManaged var destinationPasturePublicID: String?
    @NSManaged var workNotes: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var session: SharedWorkingSessionRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedWorkingQueueItemRecord {
    static let entityName = "SharedWorkingQueueItemRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedWorkingQueueItemRecord> {
        NSFetchRequest<SharedWorkingQueueItemRecord>(entityName: entityName)
    }

    func mirror(_ queueItem: WorkingQueueItem, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = queueItem.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        sessionPublicID = queueItem.session?.publicID.uuidString
        animalPublicID = queueItem.animal?.publicID.uuidString
        queueOrder = nil
        statusRawValue = queueItem.status.rawValue
        completedAt = queueItem.completedAt
        collectedFromPasturePublicID = queueItem.collectedFromPasture?.publicID.uuidString
        destinationPasturePublicID = queueItem.destinationPasture?.publicID.uuidString
        workNotes = queueItem.workNotes
        lastMirroredAt = mirroredAt
    }
}

extension SharedWorkingQueueItemRecord {
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

    var parsedCollectedFromPasturePublicID: UUID? {
        guard let collectedFromPasturePublicID else { return nil }
        return UUID(uuidString: collectedFromPasturePublicID)
    }

    var parsedDestinationPasturePublicID: UUID? {
        guard let destinationPasturePublicID else { return nil }
        return UUID(uuidString: destinationPasturePublicID)
    }

    var parsedStatus: WorkingQueueStatus {
        guard let statusRawValue else { return .queued }
        return WorkingQueueStatus(rawValue: statusRawValue) ?? .queued
    }
}
