import CoreData
import Foundation

@MainActor
struct HerdSharingBridgeMaterializedArchive {
    let herdRecords: [SharedHerdRecord]
    let tagColorDefinitions: [SharedTagColorDefinitionRecord]
    let statusReferences: [SharedAnimalStatusReferenceRecord]
    let pastureGroups: [SharedPastureGroupRecord]
    let pastures: [SharedPastureRecord]
    let animals: [SharedAnimalRecord]
    let animalTags: [SharedAnimalTagRecord]
    let movements: [SharedMovementRecord]
    let statusRecords: [SharedStatusRecord]
    let workingProtocolTemplates: [SharedWorkingProtocolTemplateRecord]
    let workingSessions: [SharedWorkingSessionRecord]
    let workingQueueItems: [SharedWorkingQueueItemRecord]
    let workingTreatmentRecords: [SharedWorkingTreatmentRecord]
    let healthRecords: [SharedHealthRecord]
    let pregnancyChecks: [SharedPregnancyCheckRecord]
    let fieldCheckSessions: [SharedFieldCheckSessionRecord]
    let fieldCheckAnimalChecks: [SharedFieldCheckAnimalCheckRecord]
    let fieldCheckFindings: [SharedFieldCheckFindingRecord]
    let deletedRecords: [SharedDeletedRecord]

    init(snapshots: [HerdSharingBridgeRecordSnapshot]) throws {
        let model = HerdSharingCoreDataModelFactory.makeCurrentModel()
        var recordsByEntityName: [String: [NSManagedObject]] = [:]

        for snapshot in snapshots {
            guard let entity = model.entitiesByName[snapshot.entityName] else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The Core Data sharing bridge model is missing \(snapshot.entityName)."
                )
            }
            let record = NSManagedObject(entity: entity, insertInto: nil)
            try HerdSharingBridgeArchiveCodec.apply(snapshot, to: record)
            recordsByEntityName[snapshot.entityName, default: []].append(record)
        }

        herdRecords = try Self.cast(recordsByEntityName, as: SharedHerdRecord.self)
        tagColorDefinitions = try Self.cast(recordsByEntityName, as: SharedTagColorDefinitionRecord.self)
        statusReferences = try Self.cast(recordsByEntityName, as: SharedAnimalStatusReferenceRecord.self)
        pastureGroups = try Self.cast(recordsByEntityName, as: SharedPastureGroupRecord.self)
        pastures = try Self.cast(recordsByEntityName, as: SharedPastureRecord.self)
        animals = try Self.cast(recordsByEntityName, as: SharedAnimalRecord.self)
        animalTags = try Self.cast(recordsByEntityName, as: SharedAnimalTagRecord.self)
        movements = try Self.cast(recordsByEntityName, as: SharedMovementRecord.self)
        statusRecords = try Self.cast(recordsByEntityName, as: SharedStatusRecord.self)
        workingProtocolTemplates = try Self.cast(recordsByEntityName, as: SharedWorkingProtocolTemplateRecord.self)
        workingSessions = try Self.cast(recordsByEntityName, as: SharedWorkingSessionRecord.self)
        workingQueueItems = try Self.cast(recordsByEntityName, as: SharedWorkingQueueItemRecord.self)
        workingTreatmentRecords = try Self.cast(recordsByEntityName, as: SharedWorkingTreatmentRecord.self)
        healthRecords = try Self.cast(recordsByEntityName, as: SharedHealthRecord.self)
        pregnancyChecks = try Self.cast(recordsByEntityName, as: SharedPregnancyCheckRecord.self)
        fieldCheckSessions = try Self.cast(recordsByEntityName, as: SharedFieldCheckSessionRecord.self)
        fieldCheckAnimalChecks = try Self.cast(recordsByEntityName, as: SharedFieldCheckAnimalCheckRecord.self)
        fieldCheckFindings = try Self.cast(recordsByEntityName, as: SharedFieldCheckFindingRecord.self)
        deletedRecords = try Self.cast(recordsByEntityName, as: SharedDeletedRecord.self)
    }

    func filtered(to herdPublicID: UUID) -> HerdSharingBridgeMaterializedArchive {
        let herdID = herdPublicID.uuidString
        return HerdSharingBridgeMaterializedArchive(
            herdRecords: herdRecords.filter { $0.publicID == herdID },
            tagColorDefinitions: tagColorDefinitions.filter { $0.herdPublicID == herdID },
            statusReferences: statusReferences.filter { $0.herdPublicID == herdID },
            pastureGroups: pastureGroups.filter { $0.herdPublicID == herdID },
            pastures: pastures.filter { $0.herdPublicID == herdID },
            animals: animals.filter { $0.herdPublicID == herdID },
            animalTags: animalTags.filter { $0.herdPublicID == herdID },
            movements: movements.filter { $0.herdPublicID == herdID },
            statusRecords: statusRecords.filter { $0.herdPublicID == herdID },
            workingProtocolTemplates: workingProtocolTemplates.filter { $0.herdPublicID == herdID },
            workingSessions: workingSessions.filter { $0.herdPublicID == herdID },
            workingQueueItems: workingQueueItems.filter { $0.herdPublicID == herdID },
            workingTreatmentRecords: workingTreatmentRecords.filter { $0.herdPublicID == herdID },
            healthRecords: healthRecords.filter { $0.herdPublicID == herdID },
            pregnancyChecks: pregnancyChecks.filter { $0.herdPublicID == herdID },
            fieldCheckSessions: fieldCheckSessions.filter { $0.herdPublicID == herdID },
            fieldCheckAnimalChecks: fieldCheckAnimalChecks.filter { $0.herdPublicID == herdID },
            fieldCheckFindings: fieldCheckFindings.filter { $0.herdPublicID == herdID },
            deletedRecords: deletedRecords.filter { $0.herdPublicID == herdID }
        )
    }

    private init(
        herdRecords: [SharedHerdRecord],
        tagColorDefinitions: [SharedTagColorDefinitionRecord],
        statusReferences: [SharedAnimalStatusReferenceRecord],
        pastureGroups: [SharedPastureGroupRecord],
        pastures: [SharedPastureRecord],
        animals: [SharedAnimalRecord],
        animalTags: [SharedAnimalTagRecord],
        movements: [SharedMovementRecord],
        statusRecords: [SharedStatusRecord],
        workingProtocolTemplates: [SharedWorkingProtocolTemplateRecord],
        workingSessions: [SharedWorkingSessionRecord],
        workingQueueItems: [SharedWorkingQueueItemRecord],
        workingTreatmentRecords: [SharedWorkingTreatmentRecord],
        healthRecords: [SharedHealthRecord],
        pregnancyChecks: [SharedPregnancyCheckRecord],
        fieldCheckSessions: [SharedFieldCheckSessionRecord],
        fieldCheckAnimalChecks: [SharedFieldCheckAnimalCheckRecord],
        fieldCheckFindings: [SharedFieldCheckFindingRecord],
        deletedRecords: [SharedDeletedRecord]
    ) {
        self.herdRecords = herdRecords
        self.tagColorDefinitions = tagColorDefinitions
        self.statusReferences = statusReferences
        self.pastureGroups = pastureGroups
        self.pastures = pastures
        self.animals = animals
        self.animalTags = animalTags
        self.movements = movements
        self.statusRecords = statusRecords
        self.workingProtocolTemplates = workingProtocolTemplates
        self.workingSessions = workingSessions
        self.workingQueueItems = workingQueueItems
        self.workingTreatmentRecords = workingTreatmentRecords
        self.healthRecords = healthRecords
        self.pregnancyChecks = pregnancyChecks
        self.fieldCheckSessions = fieldCheckSessions
        self.fieldCheckAnimalChecks = fieldCheckAnimalChecks
        self.fieldCheckFindings = fieldCheckFindings
        self.deletedRecords = deletedRecords
    }

    private static func cast<Record: NSManagedObject>(
        _ recordsByEntityName: [String: [NSManagedObject]],
        as type: Record.Type
    ) throws -> [Record] {
        let entityName = type.entityName
        return try (recordsByEntityName[entityName] ?? []).map { record in
            guard let typedRecord = record as? Record else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The archived \(entityName) record could not be materialized."
                )
            }
            return typedRecord
        }
    }
}
