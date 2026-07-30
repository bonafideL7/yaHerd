@preconcurrency import CoreData
import Foundation

extension HerdSharingCoreDataStore {
    func applyBridgeArchiveToPrivateStore(
        _ archive: HerdSharingBridgeArchive
    ) async throws -> HerdSharingBridgeArchiveApplyResult {
        try await loadIfNeeded()
        guard let privateStore else {
            throw HerdSharingActionError.sharingStoreUnavailable(
                "The private sharing bridge store was not loaded."
            )
        }
        return try await applyBridgeArchive(archive, to: privateStore)
    }

    func snapshotBridgeArchive(
        herdPublicID: UUID?,
        from store: NSPersistentStore
    ) async throws -> [HerdSharingBridgeRecordSnapshot] {
        try await loadIfNeeded()
        let context = persistentContainer.newBackgroundContext()
        context.name = "HerdSharingBridgeSnapshotContext"
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let herdID = herdPublicID?.uuidString

        return try await PerformanceLog.measureAsync("HerdSharingCoreDataStore.snapshotBridgeArchive") {
            try await context.perform {
                var snapshots: [HerdSharingBridgeRecordSnapshot] = []
                for entityName in Self.archiveEntityNames {
                    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    request.affectedStores = [store]
                    if entityName == SharedHerdRecord.entityName {
                        if let herdID {
                            request.predicate = NSPredicate(format: "publicID == %@", herdID)
                        }
                    } else if let herdID {
                        request.predicate = NSPredicate(format: "herdPublicID == %@", herdID)
                    }
                    request.fetchBatchSize = 250
                    snapshots.append(contentsOf: try context.fetch(request).map {
                        try HerdSharingBridgeArchiveCodec.snapshot($0)
                    })
                }
                return snapshots
            }
        }
    }

    private func applyBridgeArchive(
        _ archive: HerdSharingBridgeArchive,
        to store: NSPersistentStore
    ) async throws -> HerdSharingBridgeArchiveApplyResult {
        let context = persistentContainer.newBackgroundContext()
        context.name = "HerdSharingBridgeExportContext"
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let model = persistentContainer.managedObjectModel
        let herdPublicID = archive.herd.publicID.uuidString

        return try await PerformanceLog.measureAsync("HerdSharingCoreDataStore.applyBridgeArchive") {
            try await context.perform {
                var recordsByKey: [HerdSharingBridgeRecordKey: NSManagedObject] = [:]
                var existingByEntityName: [String: [NSManagedObject]] = [:]

                for entityName in Self.archiveEntityNames {
                    let existing = try Self.fetchArchiveRecords(
                        entityName: entityName,
                        herdPublicID: herdPublicID,
                        store: store,
                        context: context
                    )
                    existingByEntityName[entityName] = existing
                    let canonical = Self.repairArchiveDuplicates(existing, context: context)
                    for record in canonical {
                        guard let publicID = record.value(forKey: "publicID") as? String else { continue }
                        recordsByKey[
                            HerdSharingBridgeRecordKey(entityName: entityName, publicID: publicID)
                        ] = record
                    }
                }

                var liveKeys = Set<HerdSharingBridgeRecordKey>()
                for snapshot in archive.records {
                    guard let entity = model.entitiesByName[snapshot.entityName] else {
                        throw HerdSharingActionError.bridgeConsistencyFailed(
                            "The Core Data sharing bridge model is missing \(snapshot.entityName)."
                        )
                    }
                    let record = recordsByKey[snapshot.key]
                        ?? NSManagedObject(entity: entity, insertInto: context)
                    if record.objectID.isTemporaryID {
                        context.assign(record, to: store)
                    }
                    try HerdSharingBridgeArchiveCodec.apply(snapshot, to: record)
                    recordsByKey[snapshot.key] = record
                    liveKeys.insert(snapshot.key)
                }

                let herdKey = HerdSharingBridgeRecordKey(
                    entityName: SharedHerdRecord.entityName,
                    publicID: herdPublicID
                )
                guard let herdRecord = recordsByKey[herdKey] else {
                    throw HerdSharingActionError.shareRootMissing
                }

                let deletedEntityName = SharedDeletedRecord.entityName
                let existingTombstones = existingByEntityName[deletedEntityName] ?? []
                var tombstonesBySourceKey: [HerdSharingBridgeRecordKey: NSManagedObject] = [:]
                for tombstone in existingTombstones {
                    guard let publicID = tombstone.value(forKey: "publicID") as? String,
                          let sourceEntityName = tombstone.value(forKey: "sourceEntityName") as? String else {
                        continue
                    }
                    tombstonesBySourceKey[
                        HerdSharingBridgeRecordKey(entityName: sourceEntityName, publicID: publicID)
                    ] = tombstone
                }

                for key in liveKeys {
                    if let tombstone = tombstonesBySourceKey.removeValue(forKey: key) {
                        context.delete(tombstone)
                    }
                }

                for entityName in Self.liveArchiveEntityNames {
                    for staleRecord in existingByEntityName[entityName] ?? [] {
                        guard let publicID = staleRecord.value(forKey: "publicID") as? String else {
                            continue
                        }
                        let key = HerdSharingBridgeRecordKey(
                            entityName: entityName,
                            publicID: publicID
                        )
                        guard !liveKeys.contains(key) else { continue }

                        guard let deletedEntity = model.entitiesByName[deletedEntityName] else {
                            throw HerdSharingActionError.bridgeConsistencyFailed(
                                "The Core Data sharing bridge model is missing \(deletedEntityName)."
                            )
                        }
                        let tombstone = tombstonesBySourceKey[key]
                            ?? NSManagedObject(entity: deletedEntity, insertInto: context)
                        if tombstone.objectID.isTemporaryID {
                            context.assign(tombstone, to: store)
                        }
                        tombstone.setValue(publicID, forKey: "publicID")
                        tombstone.setValue(herdPublicID, forKey: "herdPublicID")
                        tombstone.setValue(entityName, forKey: "sourceEntityName")
                        tombstone.setValue(archive.mirroredAt, forKey: "deletedAt")
                        tombstone.setValue(archive.mirroredAt, forKey: "lastMirroredAt")
                        tombstone.setValue(herdRecord, forKey: "herd")
                        tombstonesBySourceKey[key] = tombstone
                        context.delete(staleRecord)
                    }
                }

                Self.applyArchiveRelationships(
                    recordsByKey: recordsByKey,
                    herdRecord: herdRecord
                )

                if context.hasChanges {
                    try context.save()
                }

                let recordsToShare = try Self.fetchAllArchiveRecords(
                    herdPublicID: herdPublicID,
                    store: store,
                    context: context
                )
                let bridgePublicIDs = Self.makeBridgePublicIDs(recordsToShare)
                let tombstoneCount = recordsToShare.filter {
                    $0.entity.name == SharedDeletedRecord.entityName
                }.count

                return HerdSharingBridgeArchiveApplyResult(
                    recordObjectIDURIs: recordsToShare.map { $0.objectID.uriRepresentation() },
                    deletionTombstoneCount: tombstoneCount,
                    bridgePublicIDs: bridgePublicIDs
                )
            }
        }
    }

    private static let archiveEntityNames: [String] = [
        SharedHerdRecord.entityName,
        SharedTagColorDefinitionRecord.entityName,
        SharedAnimalStatusReferenceRecord.entityName,
        SharedPastureGroupRecord.entityName,
        SharedPastureRecord.entityName,
        SharedAnimalRecord.entityName,
        SharedAnimalTagRecord.entityName,
        SharedMovementRecord.entityName,
        SharedStatusRecord.entityName,
        SharedWorkingProtocolTemplateRecord.entityName,
        SharedWorkingSessionRecord.entityName,
        SharedWorkingQueueItemRecord.entityName,
        SharedWorkingTreatmentRecord.entityName,
        SharedHealthRecord.entityName,
        SharedPregnancyCheckRecord.entityName,
        SharedFieldCheckSessionRecord.entityName,
        SharedFieldCheckAnimalCheckRecord.entityName,
        SharedFieldCheckFindingRecord.entityName,
        SharedDeletedRecord.entityName,
    ]

    private static let liveArchiveEntityNames: [String] = archiveEntityNames.filter {
        $0 != SharedHerdRecord.entityName && $0 != SharedDeletedRecord.entityName
    }

    private static func fetchArchiveRecords(
        entityName: String,
        herdPublicID: String,
        store: NSPersistentStore,
        context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.affectedStores = [store]
        request.fetchBatchSize = 250
        if entityName == SharedHerdRecord.entityName {
            request.predicate = NSPredicate(format: "publicID == %@", herdPublicID)
        } else {
            request.predicate = NSPredicate(format: "herdPublicID == %@", herdPublicID)
        }
        return try context.fetch(request)
    }

    private static func fetchAllArchiveRecords(
        herdPublicID: String,
        store: NSPersistentStore,
        context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        try archiveEntityNames.flatMap {
            try fetchArchiveRecords(
                entityName: $0,
                herdPublicID: herdPublicID,
                store: store,
                context: context
            )
        }
    }

    private static func repairArchiveDuplicates(
        _ records: [NSManagedObject],
        context: NSManagedObjectContext
    ) -> [NSManagedObject] {
        var canonical: [NSManagedObject] = []
        for group in Dictionary(grouping: records, by: {
            ($0.value(forKey: "publicID") as? String) ?? ""
        }).values {
            let ordered = group.sorted { lhs, rhs in
                let leftDate = lhs.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
                let rightDate = rhs.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return lhs.objectID.uriRepresentation().absoluteString
                    < rhs.objectID.uriRepresentation().absoluteString
            }
            guard let winner = ordered.first else { continue }
            canonical.append(winner)
            for duplicate in ordered.dropFirst() {
                context.delete(duplicate)
            }
        }
        return canonical
    }

    private static func applyArchiveRelationships(
        recordsByKey: [HerdSharingBridgeRecordKey: NSManagedObject],
        herdRecord: NSManagedObject
    ) {
        for (key, record) in recordsByKey {
            guard key.entityName != SharedHerdRecord.entityName else { continue }
            if record.entity.relationshipsByName["herd"] != nil {
                record.setValue(herdRecord, forKey: "herd")
            }

            switch key.entityName {
            case SharedPastureRecord.entityName:
                setRelationship("group", targetEntityName: SharedPastureGroupRecord.entityName, targetPublicIDAttribute: "groupPublicID", record: record, recordsByKey: recordsByKey)
            case SharedAnimalTagRecord.entityName,
                 SharedMovementRecord.entityName,
                 SharedStatusRecord.entityName,
                 SharedHealthRecord.entityName,
                 SharedPregnancyCheckRecord.entityName:
                setRelationship("animal", targetEntityName: SharedAnimalRecord.entityName, targetPublicIDAttribute: "animalPublicID", record: record, recordsByKey: recordsByKey)
            case SharedWorkingQueueItemRecord.entityName,
                 SharedWorkingTreatmentRecord.entityName:
                setRelationship("session", targetEntityName: SharedWorkingSessionRecord.entityName, targetPublicIDAttribute: "sessionPublicID", record: record, recordsByKey: recordsByKey)
                setRelationship("animal", targetEntityName: SharedAnimalRecord.entityName, targetPublicIDAttribute: "animalPublicID", record: record, recordsByKey: recordsByKey)
            case SharedFieldCheckAnimalCheckRecord.entityName,
                 SharedFieldCheckFindingRecord.entityName:
                setRelationship("session", targetEntityName: SharedFieldCheckSessionRecord.entityName, targetPublicIDAttribute: "sessionPublicID", record: record, recordsByKey: recordsByKey)
                setRelationship("animal", targetEntityName: SharedAnimalRecord.entityName, targetPublicIDAttribute: "animalPublicID", record: record, recordsByKey: recordsByKey)
            default:
                break
            }
        }
    }

    private static func setRelationship(
        _ relationshipName: String,
        targetEntityName: String,
        targetPublicIDAttribute: String,
        record: NSManagedObject,
        recordsByKey: [HerdSharingBridgeRecordKey: NSManagedObject]
    ) {
        let target: NSManagedObject?
        if let publicID = record.value(forKey: targetPublicIDAttribute) as? String {
            target = recordsByKey[
                HerdSharingBridgeRecordKey(entityName: targetEntityName, publicID: publicID)
            ]
        } else {
            target = nil
        }
        record.setValue(target, forKey: relationshipName)
    }

    private static func makeBridgePublicIDs(
        _ records: [NSManagedObject]
    ) -> [HerdSharingBridgeStep: [UUID]] {
        var result: [HerdSharingBridgeStep: [UUID]] = [:]
        for (step, entityName) in bridgeStepEntityNames {
            result[step] = records
                .filter { $0.entity.name == entityName }
                .compactMap { ($0.value(forKey: "publicID") as? String).flatMap(UUID.init(uuidString:)) }
        }
        return result
    }

    private static let bridgeStepEntityNames: [HerdSharingBridgeStep: String] = [
        .herd: SharedHerdRecord.entityName,
        .tagColorDefinitions: SharedTagColorDefinitionRecord.entityName,
        .statusReferences: SharedAnimalStatusReferenceRecord.entityName,
        .pastureGroups: SharedPastureGroupRecord.entityName,
        .pastures: SharedPastureRecord.entityName,
        .animals: SharedAnimalRecord.entityName,
        .animalTags: SharedAnimalTagRecord.entityName,
        .movements: SharedMovementRecord.entityName,
        .statusRecords: SharedStatusRecord.entityName,
        .workingProtocolTemplates: SharedWorkingProtocolTemplateRecord.entityName,
        .workingSessions: SharedWorkingSessionRecord.entityName,
        .workingQueueItems: SharedWorkingQueueItemRecord.entityName,
        .workingTreatmentRecords: SharedWorkingTreatmentRecord.entityName,
        .healthRecords: SharedHealthRecord.entityName,
        .pregnancyChecks: SharedPregnancyCheckRecord.entityName,
        .fieldCheckSessions: SharedFieldCheckSessionRecord.entityName,
        .fieldCheckAnimalChecks: SharedFieldCheckAnimalCheckRecord.entityName,
        .fieldCheckFindings: SharedFieldCheckFindingRecord.entityName,
        .deletions: SharedDeletedRecord.entityName,
    ]
}
