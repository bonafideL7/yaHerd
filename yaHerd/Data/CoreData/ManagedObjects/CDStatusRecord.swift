import CoreData
import Foundation

@objc(CDStatusRecord)
final class CDStatusRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var oldStatusRawValue: String
    @NSManaged var newStatusRawValue: String
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
}
