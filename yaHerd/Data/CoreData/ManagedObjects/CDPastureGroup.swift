import CoreData
import Foundation

@objc(CDPastureGroup)
final class CDPastureGroup: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var grazeDays: Int64
    @NSManaged var restDays: Int64
    @NSManaged var herd: CDHerd
    @NSManaged var pastures: NSSet?
}
