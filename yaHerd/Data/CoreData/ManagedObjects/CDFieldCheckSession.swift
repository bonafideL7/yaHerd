import CoreData
import Foundation

@objc(CDFieldCheckSession)
final class CDFieldCheckSession: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var startedAt: Date
    @NSManaged var completedAt: Date?
    @NSManaged var notes: String
    @NSManaged var expectedHeadCountSnapshot: Int64
    @NSManaged var quickCowCount: Int64
    @NSManaged var quickHeiferCount: Int64
    @NSManaged var quickCalfCount: Int64
    @NSManaged var quickBullCount: Int64
    @NSManaged var quickSteerCount: Int64
    @NSManaged var pastureIDSnapshot: UUID
    @NSManaged var pastureNameSnapshot: String
    @NSManaged var pastureArchivedAt: Date?
    @NSManaged var herd: CDHerd
    @NSManaged var pasture: CDPasture?
    @NSManaged var animalChecks: NSSet?
    @NSManaged var findings: NSSet?
}
