import CoreData
import Foundation

@objc(CDWorkingSession)
final class CDWorkingSession: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var statusRawValue: String
    @NSManaged var treatmentTemplateNameSnapshot: String
    @NSManaged var plannedTreatmentsData: Data
    @NSManaged var sourcePastureIDSnapshot: UUID
    @NSManaged var sourcePastureNameSnapshot: String
    @NSManaged var herd: CDHerd
    @NSManaged var sourcePasture: CDPasture?
    @NSManaged var queueItems: NSSet?
    @NSManaged var activeAnimals: NSSet?
    @NSManaged var treatmentRecords: NSSet?
    @NSManaged var healthRecords: NSSet?
    @NSManaged var pregnancyChecks: NSSet?
}
