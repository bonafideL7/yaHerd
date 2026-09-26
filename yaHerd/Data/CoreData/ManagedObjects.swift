import CoreData
import Foundation

@objc(CDHerd)
final class CDHerd: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @NSManaged var tagColors: NSSet
    @NSManaged var statusReferences: NSSet
    @NSManaged var pastureGroups: NSSet
    @NSManaged var pastures: NSSet
    @NSManaged var animals: NSSet
    @NSManaged var animalTags: NSSet
    @NSManaged var movementRecords: NSSet
    @NSManaged var statusRecords: NSSet
    @NSManaged var healthRecords: NSSet
    @NSManaged var pregnancyChecks: NSSet
    @NSManaged var fieldCheckSessions: NSSet
    @NSManaged var fieldCheckAnimalChecks: NSSet
    @NSManaged var fieldCheckFindings: NSSet
    @NSManaged var workingTreatmentTemplates: NSSet
    @NSManaged var workingSessions: NSSet
    @NSManaged var workingQueueItems: NSSet
    @NSManaged var workingTreatmentRecords: NSSet
}

@objc(CDTagColorDefinition)
final class CDTagColorDefinition: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var prefix: String
    @NSManaged var red: Double
    @NSManaged var green: Double
    @NSManaged var blue: Double
    @NSManaged var alpha: Double
    @NSManaged var sortOrder: Int64
    @NSManaged var isHidden: Bool
    @NSManaged var isDefault: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var herd: CDHerd
    @NSManaged var tags: NSSet
}

@objc(CDAnimalStatusReference)
final class CDAnimalStatusReference: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var baseStatusRawValue: String
    @NSManaged var herd: CDHerd
    @NSManaged var animals: NSSet
}

@objc(CDPastureGroup)
final class CDPastureGroup: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var grazeDays: Int64
    @NSManaged var restDays: Int64
    @NSManaged var herd: CDHerd
    @NSManaged var pastures: NSSet
}

@objc(CDPasture)
final class CDPasture: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var sortOrder: Int64
    @NSManaged var acreage: NSNumber?
    @NSManaged var usableAcreage: NSNumber?
    @NSManaged var targetAcresPerHead: NSNumber?
    @NSManaged var lastGrazedDate: Date?
    @NSManaged var herd: CDHerd
    @NSManaged var group: CDPastureGroup?
    @NSManaged var animals: NSSet
    @NSManaged var workingSourceSessions: NSSet
    @NSManaged var workingCollectedQueueItems: NSSet
    @NSManaged var workingDestinationQueueItems: NSSet
    @NSManaged var fieldCheckSessions: NSSet
}

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
    @NSManaged var tags: NSSet
    @NSManaged var healthRecords: NSSet
    @NSManaged var pregnancyChecks: NSSet
    @NSManaged var movementRecords: NSSet
    @NSManaged var statusRecords: NSSet
    @NSManaged var sireOffspring: NSSet
    @NSManaged var damOffspring: NSSet
    @NSManaged var pregnancyChecksAsSire: NSSet
    @NSManaged var fieldCheckAnimalChecks: NSSet
    @NSManaged var fieldCheckFindings: NSSet
    @NSManaged var workingQueueItems: NSSet
    @NSManaged var workingTreatmentRecords: NSSet
}

@objc(CDAnimalTag)
final class CDAnimalTag: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var number: String
    @NSManaged var isPrimary: Bool
    @NSManaged var isActive: Bool
    @NSManaged var assignedAt: Date
    @NSManaged var removedAt: Date?
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
    @NSManaged var color: CDTagColorDefinition?
}

@objc(CDMovementRecord)
final class CDMovementRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var fromPastureIDSnapshot: UUID?
    @NSManaged var fromPastureNameSnapshot: String?
    @NSManaged var toPastureIDSnapshot: UUID?
    @NSManaged var toPastureNameSnapshot: String?
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
}

@objc(CDStatusRecord)
final class CDStatusRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var oldStatusRawValue: String
    @NSManaged var newStatusRawValue: String
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
}

@objc(CDHealthRecord)
final class CDHealthRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var treatment: String
    @NSManaged var notes: String?
    @NSManaged var herd: CDHerd
    @NSManaged var animal: CDAnimal
    @NSManaged var workingSession: CDWorkingSession?
}

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
    @NSManaged var animalChecks: NSSet
    @NSManaged var findings: NSSet
}

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

@objc(CDWorkingTreatmentTemplate)
final class CDWorkingTreatmentTemplate: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var itemsData: Data
    @NSManaged var herd: CDHerd
}

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
    @NSManaged var queueItems: NSSet
    @NSManaged var activeAnimals: NSSet
    @NSManaged var treatmentRecords: NSSet
    @NSManaged var healthRecords: NSSet
    @NSManaged var pregnancyChecks: NSSet
}

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
