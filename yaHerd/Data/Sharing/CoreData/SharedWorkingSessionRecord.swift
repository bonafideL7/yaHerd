//
//  SharedWorkingSessionRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedWorkingSessionRecord)
final class SharedWorkingSessionRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var date: Date?
    @NSManaged var statusRawValue: String?
    @NSManaged var sourcePasturePublicID: String?
    @NSManaged var protocolName: String?
    @NSManaged var protocolItemsJSON: Data?
    @NSManaged var currentQueueIndex: NSNumber?
    @NSManaged var notes: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var queueItems: Set<SharedWorkingQueueItemRecord>?
    @NSManaged var treatmentRecords: Set<SharedWorkingTreatmentRecord>?
}

extension SharedWorkingSessionRecord {
    static let entityName = "SharedWorkingSessionRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedWorkingSessionRecord> {
        NSFetchRequest<SharedWorkingSessionRecord>(entityName: entityName)
    }

    func mirror(_ session: WorkingSession, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = session.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        date = session.date
        statusRawValue = session.status.rawValue
        sourcePasturePublicID = session.sourcePasture?.publicID.uuidString
        protocolName = session.protocolName
        do {
            protocolItemsJSON = try JSONEncoder().encode(session.protocolItems)
        } catch {
            protocolItemsJSON = nil
            PersistenceLog.decodeFailure("SharedWorkingSessionRecord.protocolItemsJSON.encode", error: error)
        }
        currentQueueIndex = NSNumber(value: session.currentQueueIndex)
        notes = session.notes
        lastMirroredAt = mirroredAt
    }
}

extension SharedWorkingSessionRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedSourcePasturePublicID: UUID? {
        guard let sourcePasturePublicID else { return nil }
        return UUID(uuidString: sourcePasturePublicID)
    }

    var parsedStatus: WorkingSessionStatus {
        guard let statusRawValue else { return .active }
        return WorkingSessionStatus(rawValue: statusRawValue) ?? .active
    }

    var parsedProtocolItems: [WorkingProtocolItem] {
        guard let protocolItemsJSON else { return [] }
        do {
            return try JSONDecoder().decode([WorkingProtocolItem].self, from: protocolItemsJSON)
        } catch {
            PersistenceLog.decodeFailure("SharedWorkingSessionRecord.parsedProtocolItems.decode", error: error)
            return []
        }
    }
}
