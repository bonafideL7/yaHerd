@preconcurrency import CoreData
import Foundation
@testable import yaHerd

/// Physical persistence test control for the seven Tag Color UUID reference
/// locations. Seeding bypasses TagColorRepository deliberately: the contract
/// must observe repair of real, previously persisted references.
@MainActor
final class CoreDataTagColorReferenceProbe {
    private let assembly: CoreDataPersistenceAssembly
    private let herdID: UUID

    private let animalID = UUID()
    private let currentTagID = UUID()
    private let retiredTagID = UUID()
    private let checkSessionID = UUID()
    private let checkID = UUID()
    private let findingID = UUID()
    private let workingSessionID = UUID()
    private let queueItemID = UUID()

    init(assembly: CoreDataPersistenceAssembly, herdID: UUID) {
        self.assembly = assembly
        self.herdID = herdID
    }

    func seedPersistedColor(_ snapshot: TagColorSnapshot) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        let selectedHerdID = herdID
        try context.performAndWait {
            let herd = try Self.required(
                CDHerd.self, entity: CDHerd.coreDataEntityName,
                id: selectedHerdID, herdID: nil, in: context
            )
            let existing = try Self.fetch(
                CDTagColorDefinition.self,
                entity: CDTagColorDefinition.coreDataEntityName,
                id: snapshot.id,
                herdID: selectedHerdID,
                in: context
            )
            guard existing.isEmpty else {
                throw CoreDataTagColorReferenceProbeError.duplicateFixtureColor
            }
            let color = CDTagColorDefinition(context: context)
            color.id = snapshot.id
            color.name = snapshot.name
            color.prefix = snapshot.prefix
            color.red = snapshot.rgba.r
            color.green = snapshot.rgba.g
            color.blue = snapshot.rgba.b
            color.alpha = snapshot.rgba.a
            color.sortOrder = Int64(snapshot.sortOrder)
            color.isHidden = false
            color.isDefault = snapshot.isDefault
            color.createdAt = snapshot.createdAt
            color.updatedAt = snapshot.updatedAt
            color.herd = herd
            try context.save()
        }
    }

    func seedReferences(_ colorID: UUID) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        let selectedHerdID = herdID
        let animalID = animalID
        let currentTagID = currentTagID
        let retiredTagID = retiredTagID
        let checkSessionID = checkSessionID
        let checkID = checkID
        let findingID = findingID
        let workingSessionID = workingSessionID
        let queueItemID = queueItemID

        try context.performAndWait {
            let herd = try Self.required(
                CDHerd.self, entity: CDHerd.coreDataEntityName,
                id: selectedHerdID, herdID: nil, in: context
            )
            let color = try Self.required(
                CDTagColorDefinition.self,
                entity: CDTagColorDefinition.coreDataEntityName,
                id: colorID, herdID: selectedHerdID, in: context
            )
            let timestamp = Date(timeIntervalSinceReferenceDate: 10_000)

            let animal = CDAnimal(context: context)
            animal.id = animalID
            animal.editorRevision = UUID()
            animal.name = "Reference Contract Cow"
            animal.sexRawValue = "female"
            animal.birthDate = timestamp
            animal.statusRawValue = "active"
            animal.isArchived = false
            animal.distinguishingFeaturesData = Data("[]".utf8)
            animal.herd = herd

            let current = CDAnimalTag(context: context)
            current.id = currentTagID
            current.number = "31"
            current.isPrimary = true
            current.isActive = true
            current.assignedAt = timestamp
            current.herd = herd
            current.animal = animal
            current.color = color

            let retired = CDAnimalTag(context: context)
            retired.id = retiredTagID
            retired.number = "17"
            retired.isPrimary = false
            retired.isActive = false
            retired.assignedAt = timestamp.addingTimeInterval(-100)
            retired.removedAt = timestamp
            retired.herd = herd
            retired.animal = animal
            retired.color = color

            let checkSession = CDFieldCheckSession(context: context)
            checkSession.id = checkSessionID
            checkSession.startedAt = timestamp
            checkSession.notes = "Tag Color reference contract"
            checkSession.expectedHeadCountSnapshot = 1
            checkSession.quickCowCount = 0
            checkSession.quickHeiferCount = 0
            checkSession.quickCalfCount = 0
            checkSession.quickBullCount = 0
            checkSession.quickSteerCount = 0
            checkSession.pastureIDSnapshot = UUID()
            checkSession.pastureNameSnapshot = "Reference North"
            checkSession.herd = herd

            let check = CDFieldCheckAnimalCheck(context: context)
            check.id = checkID
            check.animalIDSnapshot = animalID
            check.rosterTagNumberSnapshot = "31"
            check.rosterTagColorIDSnapshot = colorID
            check.damRosterTagNumberSnapshot = "17"
            check.damRosterTagColorIDSnapshot = colorID
            check.animalNameSnapshot = animal.name
            check.animalSexRawValueSnapshot = animal.sexRawValue
            check.animalTypeRawValueSnapshot = "cow"
            check.wasExpectedAtStart = true
            check.herd = herd
            check.session = checkSession
            check.animal = animal

            let finding = CDFieldCheckFinding(context: context)
            finding.id = findingID
            finding.recordedAt = timestamp
            finding.typeRawValue = "pinkEye"
            finding.severityRawValue = "warning"
            finding.statusRawValue = "open"
            finding.note = "Tag Color reference finding"
            finding.animalIDSnapshot = animalID
            finding.animalDisplayTagNumberSnapshot = "31"
            finding.animalDisplayTagColorIDSnapshot = colorID
            finding.animalNameSnapshot = animal.name
            finding.pastureNameSnapshot = "Reference North"
            finding.herd = herd
            finding.session = checkSession
            finding.animal = animal

            let workingSession = CDWorkingSession(context: context)
            workingSession.id = workingSessionID
            workingSession.date = timestamp
            workingSession.statusRawValue = "active"
            workingSession.treatmentTemplateNameSnapshot = "Reference Contract"
            workingSession.plannedTreatmentsData = Data("[]".utf8)
            workingSession.sourcePastureIDSnapshot = UUID()
            workingSession.sourcePastureNameSnapshot = "Reference North"
            workingSession.herd = herd

            let queue = CDWorkingQueueItem(context: context)
            queue.id = queueItemID
            queue.statusRawValue = "pending"
            queue.animalIDSnapshot = animalID
            queue.animalTagNumberSnapshot = "31"
            queue.animalTagColorIDSnapshot = colorID
            queue.animalNameSnapshot = animal.name
            queue.animalSexRawValueSnapshot = animal.sexRawValue
            queue.animalDamDisplayTagNumberSnapshot = "17"
            queue.animalDamDisplayTagColorIDSnapshot = colorID
            queue.herd = herd
            queue.session = workingSession
            queue.animal = animal
            try context.save()
        }
    }

    /// Each probe uses a fresh read context and locates the same physical rows
    /// by their application IDs. A missing/duplicated row fails the contract,
    /// rather than being disguised as an empty optional UUID.
    func fetchReferences() throws -> TagColorReferenceSnapshot {
        let context = assembly.contextFactory.makeReadContext()
        let herdID = herdID
        let currentTagID = currentTagID
        let retiredTagID = retiredTagID
        let checkID = checkID
        let findingID = findingID
        let queueItemID = queueItemID
        return try context.performAndWait {
            let current = try Self.required(
                CDAnimalTag.self, entity: CDAnimalTag.coreDataEntityName,
                id: currentTagID, herdID: herdID, in: context
            )
            let retired = try Self.required(
                CDAnimalTag.self, entity: CDAnimalTag.coreDataEntityName,
                id: retiredTagID, herdID: herdID, in: context
            )
            let check = try Self.required(
                CDFieldCheckAnimalCheck.self,
                entity: CDFieldCheckAnimalCheck.coreDataEntityName,
                id: checkID, herdID: herdID, in: context
            )
            let finding = try Self.required(
                CDFieldCheckFinding.self,
                entity: CDFieldCheckFinding.coreDataEntityName,
                id: findingID, herdID: herdID, in: context
            )
            let queue = try Self.required(
                CDWorkingQueueItem.self,
                entity: CDWorkingQueueItem.coreDataEntityName,
                id: queueItemID, herdID: herdID, in: context
            )
            return TagColorReferenceSnapshot(
                animalTagColorID: current.color?.id,
                historicalTagColorID: retired.color?.id,
                fieldCheckRosterTagColorID: check.rosterTagColorIDSnapshot,
                fieldCheckDamRosterTagColorID: check.damRosterTagColorIDSnapshot,
                fieldCheckFindingTagColorIDSnapshot: finding.animalDisplayTagColorIDSnapshot,
                workingQueueTagColorIDSnapshot: queue.animalTagColorIDSnapshot,
                workingQueueDamTagColorIDSnapshot: queue.animalDamDisplayTagColorIDSnapshot
            )
        }
    }

    private nonisolated static func fetch<T: NSManagedObject>(
        _ type: T.Type,
        entity: String,
        id: UUID,
        herdID: UUID?,
        in context: NSManagedObjectContext
    ) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: entity)
        if let herdID {
            request.predicate = NSPredicate(
                format: "id == %@ AND herd.id == %@",
                id as NSUUID, herdID as NSUUID
            )
        } else {
            request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        }
        request.fetchLimit = 2
        return try context.fetch(request)
    }

    private nonisolated static func required<T: NSManagedObject>(
        _ type: T.Type,
        entity: String,
        id: UUID,
        herdID: UUID?,
        in context: NSManagedObjectContext
    ) throws -> T {
        let rows = try fetch(type, entity: entity, id: id, herdID: herdID, in: context)
        guard rows.count == 1, let row = rows.first else {
            throw CoreDataTagColorReferenceProbeError.missingOrDuplicateReference(
                entity: entity, id: id, actualCount: rows.count
            )
        }
        return row
    }
}

private enum CoreDataTagColorReferenceProbeError: Error {
    case duplicateFixtureColor
    case missingOrDuplicateReference(entity: String, id: UUID, actualCount: Int)
}
