import CoreData
import Foundation

@objc(CDHerd)
final class CDHerd: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @NSManaged var tagColors: NSSet?
    @NSManaged var statusReferences: NSSet?
    @NSManaged var pastureGroups: NSSet?
    @NSManaged var pastures: NSSet?
    @NSManaged var animals: NSSet?
    @NSManaged var animalTags: NSSet?
    @NSManaged var movementRecords: NSSet?
    @NSManaged var statusRecords: NSSet?
    @NSManaged var healthRecords: NSSet?
    @NSManaged var pregnancyChecks: NSSet?
    @NSManaged var fieldCheckSessions: NSSet?
    @NSManaged var fieldCheckAnimalChecks: NSSet?
    @NSManaged var fieldCheckFindings: NSSet?
    @NSManaged var workingTreatmentTemplates: NSSet?
    @NSManaged var workingSessions: NSSet?
    @NSManaged var workingQueueItems: NSSet?
    @NSManaged var workingTreatmentRecords: NSSet?
}
