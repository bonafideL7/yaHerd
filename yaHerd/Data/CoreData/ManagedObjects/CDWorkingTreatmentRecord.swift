import CoreData
import Foundation

@objc(CDWorkingTreatmentRecord)
final class CDWorkingTreatmentRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var treatmentItemID: UUID
    @NSManaged var itemNameSnapshot: String
    @NSManaged var given: Bool
    @NSManaged var doseAmount: NSNumber?
    @NSManaged var doseUnitRawValue: String?
    @NSManaged var administrationRouteRawValue: String?
    @NSManaged var animalIDSnapshot: UUID
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal?
    @NSManaged var session: CDWorkingSession
}
