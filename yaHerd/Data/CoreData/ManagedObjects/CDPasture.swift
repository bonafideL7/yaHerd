import CoreData
import Foundation

@objc(CDPasture)
final class CDPasture: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var sortOrder: Int64
    @NSManaged var acreage: NSNumber?
    @NSManaged var usableAcreage: NSNumber?
    @NSManaged var targetAcresPerHead: NSNumber?
    @NSManaged var lastGrazedDate: Date?
    @NSManaged var herd: CDHerd
    @NSManaged var group: CDPastureGroup?
    @NSManaged var animals: NSSet?
    @NSManaged var workingSourceSessions: NSSet?
    @NSManaged var workingCollectedQueueItems: NSSet?
    @NSManaged var workingDestinationQueueItems: NSSet?
    @NSManaged var fieldCheckSessions: NSSet?
}
