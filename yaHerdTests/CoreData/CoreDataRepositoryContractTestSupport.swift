@preconcurrency import CoreData
import Foundation
@testable import yaHerd

@MainActor
final class CoreDataContractSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

@MainActor
enum CoreDataContractTestSupport {
    static func herdSelectionControl(
        selection: CoreDataContractSelection,
        assembly: CoreDataPersistenceAssembly
    ) -> HerdRepositorySelectionTestControl {
        HerdRepositorySelectionTestControl(
            seedHerd: { id, name, createdAt, updatedAt in
                try write(assembly) { context in
                    let herd = CDHerd(context: context)
                    herd.id = id
                    herd.name = name
                    herd.createdAt = createdAt
                    herd.updatedAt = updatedAt
                }
            },
            setCurrentHerdID: { selection.currentHerdID = $0 },
            persistedHerdRowCountsByID: {
                let context = assembly.contextFactory.makeReadContext()
                return try context.performAndWait {
                    let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
                    return try context.fetch(request).reduce(into: [UUID: Int]()) {
                        $0[$1.id, default: 0] += 1
                    }
                }
            }
        )
    }

    static func write(
        _ assembly: CoreDataPersistenceAssembly,
        _ changes: (NSManagedObjectContext) throws -> Void
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            try changes(context)
            if context.hasChanges { try context.save() }
        }
    }
}

@MainActor
final class CoreDataTagColorContractHarness {
    let fixture: TagColorRepositoryContractFixture

    private let assembly: CoreDataPersistenceAssembly
    private let selection: CoreDataContractSelection
    private let ids: ReferenceIDs

    static func make() async throws -> CoreDataTagColorContractHarness {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = CoreDataContractSelection()
        let herdID = UUID()

        try CoreDataContractTestSupport.herdSelectionControl(
            selection: selection,
            assembly: assembly
        ).seedHerd(
            herdID,
            "Tag Color Contract Herd",
            Date(timeIntervalSince1970: 1_700_000_000),
            Date(timeIntervalSince1970: 1_700_000_100)
        )
        selection.currentHerdID = herdID
        return CoreDataTagColorContractHarness(assembly: assembly, selection: selection)
    }

    private init(
        assembly: CoreDataPersistenceAssembly,
        selection: CoreDataContractSelection
    ) {
        self.assembly = assembly
        self.selection = selection
        let ids = ReferenceIDs()
        self.ids = ids

        fixture = TagColorRepositoryContractFixture(
            makeTagColorRepository: {
                CoreDataTagColorRepository(selection: selection, assembly: assembly)
            },
            referenceControl: TagColorReferenceTestControl(
                seedPersistedColor: { [assembly, selection] in
                    try Self.seedColor($0, assembly: assembly, selection: selection)
                },
                seedReferences: { [assembly, selection, ids] in
                    try Self.seedReferences(
                        colorID: $0,
                        ids: ids,
                        assembly: assembly,
                        selection: selection
                    )
                },
                fetchReferences: { [assembly, selection, ids] in
                    try Self.fetchReferences(
                        ids: ids,
                        assembly: assembly,
                        selection: selection
                    )

                }
            ),
            herdSelectionControl: CoreDataContractTestSupport.herdSelectionControl(
                selection: selection,
                assembly: assembly
            )
        )
    }

    private static func seedColor(
        _ color: TagColorSnapshot,
        assembly: CoreDataPersistenceAssembly,
        selection: CoreDataContractSelection
    ) throws {
        try CoreDataContractTestSupport.write(assembly) { context in
            let herd = try currentHerd(assembly, selection, context)
            let managed = CDTagColorDefinition(context: context)
            managed.id = color.id
            managed.name = color.name
            managed.prefix = color.prefix
            managed.red = color.rgba.r
            managed.green = color.rgba.g
            managed.blue = color.rgba.b
            managed.alpha = color.rgba.a
            managed.sortOrder = Int64(color.sortOrder)
            managed.isHidden = false
            managed.isDefault = color.isDefault
            managed.createdAt = color.createdAt
            managed.updatedAt = color.updatedAt
            managed.herd = herd
        }
    }

    private static func seedReferences(
        colorID: UUID,
        ids: ReferenceIDs,
        assembly: CoreDataPersistenceAssembly,
        selection: CoreDataContractSelection
    ) throws {
        try CoreDataContractTestSupport.write(assembly) { context in
            let herd = try currentHerd(assembly, selection, context)
            guard let color = try assembly.lookup.herdOwned(
                CDTagColorDefinition.self,
                id: colorID,
                herdID: herd.id,
                in: context
            ) else {
                throw HerdRepositoryError.missingHerd
            }

            // The persistence-neutral control means "seed representative references to this color."
            // Re-seeding replaces the probe graph instead of creating duplicate application IDs.
            try deleteIfPresent(CDAnimalTag.self, id: ids.currentTag, herdID: herd.id, assembly: assembly, context: context)
            try deleteIfPresent(CDAnimalTag.self, id: ids.historicalTag, herdID: herd.id, assembly: assembly, context: context)
            try deleteIfPresent(CDFieldCheckAnimalCheck.self, id: ids.fieldCheck, herdID: herd.id, assembly: assembly, context: context)
            try deleteIfPresent(CDFieldCheckFinding.self, id: ids.finding, herdID: herd.id, assembly: assembly, context: context)
            try deleteIfPresent(CDWorkingQueueItem.self, id: ids.queueItem, herdID: herd.id, assembly: assembly, context: context)

            let animal = CDAnimal(context: context)
            animal.id = UUID()
            animal.editorRevision = UUID()
            animal.name = "Tag Color Contract Animal"
            animal.sexRawValue = "female"
            animal.birthDate = Date(timeIntervalSince1970: 1_650_000_000)
            animal.statusRawValue = "active"
            animal.isArchived = false
            animal.distinguishingFeaturesData = Data()
            animal.herd = herd

            let currentTag = CDAnimalTag(context: context)
            currentTag.id = ids.currentTag
            currentTag.number = "101"
            currentTag.isPrimary = true
            currentTag.isActive = true
            currentTag.assignedAt = Date(timeIntervalSince1970: 1_700_000_000)
            currentTag.herd = herd
            currentTag.animal = animal
            currentTag.color = color

            let historicalTag = CDAnimalTag(context: context)
            historicalTag.id = ids.historicalTag
            historicalTag.number = "OLD101"
            historicalTag.isPrimary = false
            historicalTag.isActive = false
            historicalTag.assignedAt = Date(timeIntervalSince1970: 1_690_000_000)
            historicalTag.removedAt = Date(timeIntervalSince1970: 1_695_000_000)
            historicalTag.herd = herd
            historicalTag.animal = animal
            historicalTag.color = color

            let fieldSession = CDFieldCheckSession(context: context)
            fieldSession.id = UUID()
            fieldSession.startedAt = Date(timeIntervalSince1970: 1_700_010_000)
            fieldSession.notes = ""
            fieldSession.expectedHeadCountSnapshot = 1
            fieldSession.quickCowCount = 0
            fieldSession.quickHeiferCount = 0
            fieldSession.quickCalfCount = 0
            fieldSession.quickBullCount = 0
            fieldSession.quickSteerCount = 0
            fieldSession.pastureIDSnapshot = UUID()
            fieldSession.pastureNameSnapshot = "Contract Pasture"
            fieldSession.herd = herd

            let check = CDFieldCheckAnimalCheck(context: context)
            check.id = ids.fieldCheck
            check.animalIDSnapshot = animal.id
            check.rosterTagNumberSnapshot = "101"
            check.rosterTagColorIDSnapshot = colorID
            check.damRosterTagNumberSnapshot = "DAM1"
            check.damRosterTagColorIDSnapshot = colorID
            check.animalNameSnapshot = animal.name
            check.animalSexRawValueSnapshot = animal.sexRawValue
            check.animalTypeRawValueSnapshot = "cow"
            check.wasExpectedAtStart = true
            check.herd = herd
            check.session = fieldSession
            check.animal = animal

            let finding = CDFieldCheckFinding(context: context)
            finding.id = ids.finding
            finding.recordedAt = Date(timeIntervalSince1970: 1_700_010_100)
            finding.typeRawValue = "other"
            finding.severityRawValue = "low"
            finding.statusRawValue = "open"
            finding.note = ""
            finding.animalIDSnapshot = animal.id
            finding.animalDisplayTagNumberSnapshot = "101"
            finding.animalDisplayTagColorIDSnapshot = colorID
            finding.animalNameSnapshot = animal.name
            finding.pastureNameSnapshot = "Contract Pasture"
            finding.herd = herd
            finding.session = fieldSession
            finding.animal = animal

            let workingSession = CDWorkingSession(context: context)
            workingSession.id = UUID()
            workingSession.date = Date(timeIntervalSince1970: 1_700_020_000)
            workingSession.statusRawValue = "planned"
            workingSession.treatmentTemplateNameSnapshot = ""
            workingSession.plannedTreatmentsData = Data()
            workingSession.sourcePastureIDSnapshot = UUID()
            workingSession.sourcePastureNameSnapshot = "Contract Pasture"
            workingSession.herd = herd

            let queueItem = CDWorkingQueueItem(context: context)
            queueItem.id = ids.queueItem
            queueItem.statusRawValue = "pending"
            queueItem.animalIDSnapshot = animal.id
            queueItem.animalTagNumberSnapshot = "101"
            queueItem.animalTagColorIDSnapshot = colorID
            queueItem.animalNameSnapshot = animal.name
            queueItem.animalSexRawValueSnapshot = animal.sexRawValue
            queueItem.animalDamDisplayTagNumberSnapshot = "DAM1"
            queueItem.animalDamDisplayTagColorIDSnapshot = colorID
            queueItem.herd = herd
            queueItem.session = workingSession
            queueItem.animal = animal
        }
    }

    private static func fetchReferences(
        ids: ReferenceIDs,
        assembly: CoreDataPersistenceAssembly,
        selection: CoreDataContractSelection
    ) throws -> TagColorReferenceSnapshot {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let herd = try currentHerd(assembly, selection, context)
            let current: CDAnimalTag = try required(ids.currentTag, herd.id, assembly, context)
            let historical: CDAnimalTag = try required(ids.historicalTag, herd.id, assembly, context)
            let check: CDFieldCheckAnimalCheck = try required(ids.fieldCheck, herd.id, assembly, context)
            let finding: CDFieldCheckFinding = try required(ids.finding, herd.id, assembly, context)
            let queue: CDWorkingQueueItem = try required(ids.queueItem, herd.id, assembly, context)

            return TagColorReferenceSnapshot(
                animalTagColorID: current.color?.id,
                historicalTagColorID: historical.color?.id,
                fieldCheckRosterTagColorID: check.rosterTagColorIDSnapshot,
                fieldCheckDamRosterTagColorID: check.damRosterTagColorIDSnapshot,
                fieldCheckFindingTagColorIDSnapshot: finding.animalDisplayTagColorIDSnapshot,
                workingQueueTagColorIDSnapshot: queue.animalTagColorIDSnapshot,
                workingQueueDamTagColorIDSnapshot: queue.animalDamDisplayTagColorIDSnapshot
            )
        }
    }

    private static func currentHerd(
        _ assembly: CoreDataPersistenceAssembly,
        _ selection: CoreDataContractSelection,
        _ context: NSManagedObjectContext
    ) throws -> CDHerd {
        guard let id = selection.currentHerdID,
              let herd = try assembly.lookup.herd(id: id, in: context) else {
            throw HerdRepositoryError.missingHerd
        }
        return herd
    }

    private static func deleteIfPresent<Object>(
        _ type: Object.Type,
        id: UUID,
        herdID: UUID,
        assembly: CoreDataPersistenceAssembly,
        context: NSManagedObjectContext
    ) throws where Object: NSManagedObject & CoreDataHerdOwnedManagedObject {
        if let object = try assembly.lookup.herdOwned(
            type,
            id: id,
            herdID: herdID,
            in: context
        ) {
            context.delete(object)
        }
    }

    private static func required<Object>(
        _ id: UUID,
        _ herdID: UUID,
        _ assembly: CoreDataPersistenceAssembly,
        _ context: NSManagedObjectContext
    ) throws -> Object
    where Object: NSManagedObject & CoreDataHerdOwnedManagedObject {
        guard let object = try assembly.lookup.herdOwned(
            Object.self,
            id: id,
            herdID: herdID,
            in: context
        ) else {
            throw HerdRepositoryError.missingHerd
        }
        return object
    }

    private struct ReferenceIDs {
        let currentTag = UUID()
        let historicalTag = UUID()
        let fieldCheck = UUID()
        let finding = UUID()
        let queueItem = UUID()
    }
}
