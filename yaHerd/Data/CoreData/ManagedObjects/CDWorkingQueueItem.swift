import CoreData
import Foundation

@objc(CDWorkingQueueItem)
final class CDWorkingQueueItem: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var statusRawValue: String
    @NSManaged var completedAt: Date?
    @NSManaged var animalIDSnapshot: UUID
    @NSManaged var animalTagNumberSnapshot: String
    @NSManaged var animalTagColorIDSnapshot: UUID?
    @NSManaged var animalNameSnapshot: String
    @NSManaged var animalSexRawValueSnapshot: String
    @NSManaged var animalDamDisplayTagNumberSnapshot: String?
    @NSManaged var animalDamDisplayTagColorIDSnapshot: UUID?
    @NSManaged var collectedFromPastureIDSnapshot: UUID?
    @NSManaged var collectedFromPastureNameSnapshot: String?
    @NSManaged var destinationPastureIDSnapshot: UUID?
    @NSManaged var destinationPastureNameSnapshot: String?
    @NSManaged var herd: CDHerd
    @NSManaged var session: CDWorkingSession
    @NSManaged var animal: CDAnimal?
    @NSManaged var collectedFromPasture: CDPasture?
    @NSManaged var destinationPasture: CDPasture?
}
