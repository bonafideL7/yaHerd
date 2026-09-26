import CoreData
import Foundation

@objc(CDFieldCheckAnimalCheck)
final class CDFieldCheckAnimalCheck: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var animalIDSnapshot: UUID
    @NSManaged var rosterTagNumberSnapshot: String
    @NSManaged var rosterTagColorIDSnapshot: UUID?
    @NSManaged var damRosterTagNumberSnapshot: String?
    @NSManaged var damRosterTagColorIDSnapshot: UUID?
    @NSManaged var animalNameSnapshot: String
    @NSManaged var animalSexRawValueSnapshot: String
    @NSManaged var animalTypeRawValueSnapshot: String
    @NSManaged var wasExpectedAtStart: Bool
    @NSManaged var countedAt: Date?
    @NSManaged var missingConfirmedAt: Date?
    @NSManaged var herd: CDHerd
    @NSManaged var session: CDFieldCheckSession
    @NSManaged var animal: CDAnimal?
}
