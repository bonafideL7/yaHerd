import CoreData
import Foundation

@objc(CDAnimalStatusReference)
final class CDAnimalStatusReference: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var baseStatusRawValue: String
    @NSManaged var herd: CDHerd
    @NSManaged var animals: NSSet?
}
