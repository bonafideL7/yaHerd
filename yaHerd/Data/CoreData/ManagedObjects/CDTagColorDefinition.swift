import CoreData
import Foundation

@objc(CDTagColorDefinition)
final class CDTagColorDefinition: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var prefix: String
    @NSManaged var red: Double
    @NSManaged var green: Double
    @NSManaged var blue: Double
    @NSManaged var alpha: Double
    @NSManaged var sortOrder: Int64
    @NSManaged var isHidden: Bool
    @NSManaged var isDefault: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var herd: CDHerd
    @NSManaged var tags: NSSet?
}
