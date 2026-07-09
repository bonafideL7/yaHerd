//
//  SharedWorkingProtocolTemplateRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedWorkingProtocolTemplateRecord)
final class SharedWorkingProtocolTemplateRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var name: String?
    @NSManaged var itemsJSON: Data?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
}

extension SharedWorkingProtocolTemplateRecord {
    static let entityName = "SharedWorkingProtocolTemplateRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedWorkingProtocolTemplateRecord> {
        NSFetchRequest<SharedWorkingProtocolTemplateRecord>(entityName: entityName)
    }

    func mirror(_ template: WorkingProtocolTemplate, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = template.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        name = template.name
        do {
            itemsJSON = try JSONEncoder().encode(template.items)
        } catch {
            itemsJSON = nil
            PersistenceLog.decodeFailure("SharedWorkingProtocolTemplateRecord.itemsJSON.encode", error: error)
        }
        lastMirroredAt = mirroredAt
    }
}

extension SharedWorkingProtocolTemplateRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedItems: [WorkingProtocolItem] {
        guard let itemsJSON else { return [] }
        do {
            return try JSONDecoder().decode([WorkingProtocolItem].self, from: itemsJSON)
        } catch {
            PersistenceLog.decodeFailure("SharedWorkingProtocolTemplateRecord.parsedItems.decode", error: error)
            return []
        }
    }
}
