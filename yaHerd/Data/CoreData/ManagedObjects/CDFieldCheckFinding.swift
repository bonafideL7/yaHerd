import CoreData
import Foundation

@objc(CDFieldCheckFinding)
final class CDFieldCheckFinding: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var recordedAt: Date
    @NSManaged var typeRawValue: String
    @NSManaged var severityRawValue: String
    @NSManaged var statusRawValue: String
    @NSManaged var note: String
    @NSManaged var animalIDSnapshot: UUID?
    @NSManaged var animalDisplayTagNumberSnapshot: String?
    @NSManaged var animalDisplayTagColorIDSnapshot: UUID?
    @NSManaged var animalNameSnapshot: String?
    @NSManaged var pastureNameSnapshot: String
    @NSManaged var herd: CDHerd
    @NSManaged var session: CDFieldCheckSession
    @NSManaged var animal: CDAnimal?
}
