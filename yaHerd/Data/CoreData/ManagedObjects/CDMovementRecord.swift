import CoreData
import Foundation

@objc(CDMovementRecord)
final class CDMovementRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var fromPastureIDSnapshot: UUID?
    @NSManaged var fromPastureNameSnapshot: String?
    @NSManaged var toPastureIDSnapshot: UUID?
    @NSManaged var toPastureNameSnapshot: String?
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
}
