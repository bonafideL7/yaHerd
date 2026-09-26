import CoreData
import Foundation

@objc(CDAnimal)
final class CDAnimal: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var editorRevision: UUID
    @NSManaged var name: String
    @NSManaged var sexRawValue: String
    @NSManaged var birthDate: Date
    @NSManaged var statusRawValue: String
    @NSManaged var saleDate: Date?
    @NSManaged var salePrice: NSNumber?
    @NSManaged var reasonSold: String?
    @NSManaged var deathDate: Date?
    @NSManaged var causeOfDeath: String?
    @NSManaged var isArchived: Bool
    @NSManaged var archivedAt: Date?
    @NSManaged var archiveReason: String?
    @NSManaged var distinguishingFeaturesData: Data
    @NSManaged var herd: CDHerd
    @NSManaged var statusReference: CDAnimalStatusReference?
    @NSManaged var currentPasture: CDPasture?
    @NSManaged var sire: CDAnimal?
    @NSManaged var dam: CDAnimal?
    @NSManaged var activeWorkingSession: CDWorkingSession?
    @NSManaged var tags: NSSet?
    @NSManaged var healthRecords: NSSet?
    @NSManaged var pregnancyChecks: NSSet?
    @NSManaged var movementRecords: NSSet?
    @NSManaged var statusRecords: NSSet?
    @NSManaged var sireOffspring: NSSet?
    @NSManaged var damOffspring: NSSet?
    @NSManaged var pregnancyChecksAsSire: NSSet?
    @NSManaged var fieldCheckAnimalChecks: NSSet?
    @NSManaged var fieldCheckFindings: NSSet?
    @NSManaged var workingQueueItems: NSSet?
    @NSManaged var workingTreatmentRecords: NSSet?
}
