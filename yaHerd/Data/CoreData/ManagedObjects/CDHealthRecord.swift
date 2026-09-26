import CoreData
import Foundation

@objc(CDHealthRecord)
final class CDHealthRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var treatment: String
    @NSManaged var notes: String?
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
    @NSManaged var workingSession: CDWorkingSession?
}
