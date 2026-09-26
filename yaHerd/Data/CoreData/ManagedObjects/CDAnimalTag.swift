import CoreData
import Foundation

@objc(CDAnimalTag)
final class CDAnimalTag: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var number: String
    @NSManaged var isPrimary: Bool
    @NSManaged var isActive: Bool
    @NSManaged var assignedAt: Date
    @NSManaged var removedAt: Date?
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
    @NSManaged var color: CDTagColorDefinition?
}
