import CoreData
import Foundation

@objc(CDWorkingTreatmentTemplate)
final class CDWorkingTreatmentTemplate: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var itemsData: Data
    @NSManaged var herd: CDHerd
}
