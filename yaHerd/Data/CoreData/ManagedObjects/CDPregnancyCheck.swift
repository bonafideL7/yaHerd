import CoreData
import Foundation

@objc(CDPregnancyCheck)
final class CDPregnancyCheck: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var resultRawValue: String
    @NSManaged var technician: String?
    @NSManaged var estimatedDaysPregnant: NSNumber?
    @NSManaged var dueDate: Date?
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
    @NSManaged var sire: CDAnimal?
    @NSManaged var workingSession: CDWorkingSession?
}
