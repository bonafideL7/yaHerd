import Foundation
import SwiftData

enum CollaborationMutationSavePolicy: Sendable {
    case localMutation
    case acceptIncomingSharedRevision

    static func policy(for operation: String) -> CollaborationMutationSavePolicy {
        if operation == "SwiftDataHerdSharingActor.atomicImport" {
            return .acceptIncomingSharedRevision
        }
        return .localMutation
    }
}

struct CollaborationPreparedSave {
    fileprivate let localMetadataUpdates: [CollaborationAggregateKey: CollaborationRevisionMetadata]

    func commitRegistryUpdates() {
        for (key, metadata) in localMetadataUpdates {
            CollaborationRevisionRegistry.registerLocal(metadata, for: key)
        }
    }
}

/// Central mutation boundary for every collaboratively mutable aggregate.
/// Repositories and use cases continue to save normally; revision stamping is
/// derived from ModelContext changes immediately before the transaction commits.
enum CollaborationMutationPipeline {
    static func prepareForSave(
        in context: ModelContext,
        operation: String
    ) throws -> CollaborationPreparedSave {
        let policy = CollaborationMutationSavePolicy.policy(for: operation)
        let pendingAggregates = pendingAggregates(in: context)
        guard !pendingAggregates.isEmpty else {
            return CollaborationPreparedSave(localMetadataUpdates: [:])
        }

        let records = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
        var recordsByKey: [CollaborationAggregateKey: CollaborationRevisionRecord] = [:]
        canonicalize(records, into: &recordsByKey, in: context)

        var updates: [CollaborationAggregateKey: CollaborationRevisionMetadata] = [:]
        updates.reserveCapacity(pendingAggregates.count)

        for pending in pendingAggregates.values {
            let key = pending.aggregate.collaborationKey
            let currentFields = CollaborationFieldSnapshotProvider.snapshot(for: pending.aggregate)
            let existingRecord = recordsByKey[key]
            let existingMetadata = preferredCurrentMetadata(
                record: existingRecord,
                cached: CollaborationRevisionRegistry.localMetadata(for: key)
            )

            let metadata: CollaborationRevisionMetadata
            switch policy {
            case .localMutation:
                metadata = makeLocalMutationMetadata(
                    existing: existingMetadata,
                    observedShared: CollaborationRevisionRegistry.observedSharedMetadata(for: key),
                    currentFields: currentFields,
                    isDeleted: pending.isDeleted
                )
            case .acceptIncomingSharedRevision:
                metadata = makeAcceptedSharedMetadata(
                    incoming: CollaborationRevisionRegistry.incomingMetadata(for: key),
                    currentFields: currentFields,
                    isDeleted: pending.isDeleted
                )
            }

            let record: CollaborationRevisionRecord
            if let existingRecord {
                record = existingRecord
                record.aggregateKey = key.storageKey
                record.sourceEntityName = key.sourceEntityName
                record.aggregatePublicID = key.publicID
                record.herdPublicID = pending.aggregate.collaborationHerdPublicID
                record.apply(metadata)
            } else {
                record = CollaborationRevisionRecord(
                    key: key,
                    herdPublicID: pending.aggregate.collaborationHerdPublicID,
                    metadata: metadata
                )
                context.insert(record)
                recordsByKey[key] = record
            }

            updates[key] = metadata
        }

        return CollaborationPreparedSave(localMetadataUpdates: updates)
    }

    private struct PendingAggregate {
        let aggregate: any CollaborativelyMutableAggregate
        let isDeleted: Bool
    }

    private static func pendingAggregates(
        in context: ModelContext
    ) -> [CollaborationAggregateKey: PendingAggregate] {
        var pending: [CollaborationAggregateKey: PendingAggregate] = [:]

        func collect(_ models: [any PersistentModel], isDeleted: Bool) {
            for model in models {
                guard let aggregate = model as? any CollaborativelyMutableAggregate else { continue }
                pending[aggregate.collaborationKey] = PendingAggregate(
                    aggregate: aggregate,
                    isDeleted: isDeleted
                )
            }
        }

        collect(context.insertedModelsArray, isDeleted: false)
        collect(context.changedModelsArray, isDeleted: false)
        collect(context.deletedModelsArray, isDeleted: true)
        return pending
    }

    private static func canonicalize(
        _ records: [CollaborationRevisionRecord],
        into recordsByKey: inout [CollaborationAggregateKey: CollaborationRevisionRecord],
        in context: ModelContext
    ) {
        for record in records {
            let key = CollaborationAggregateKey(
                sourceEntityName: record.sourceEntityName,
                publicID: record.aggregatePublicID
            )
            guard let existing = recordsByKey[key] else {
                recordsByKey[key] = record
                continue
            }

            let keepIncoming = record.revision > existing.revision
                || (record.revision == existing.revision && record.modifiedAt > existing.modifiedAt)
            if keepIncoming {
                context.delete(existing)
                recordsByKey[key] = record
            } else {
                context.delete(record)
            }
            ReliabilityLog.persistenceEvent(
                "CollaborationMutationPipeline.duplicateMetadataRepaired",
                detail: key.storageKey
            )
        }
    }

    private static func preferredCurrentMetadata(
        record: CollaborationRevisionRecord?,
        cached: CollaborationRevisionMetadata?
    ) -> CollaborationRevisionMetadata? {
        guard let record else { return cached }
        let stored = record.metadata
        guard let cached else { return stored }
        if stored.revision != cached.revision {
            return stored.revision > cached.revision ? stored : cached
        }
        return stored.modifiedAt >= cached.modifiedAt ? stored : cached
    }

    private static func makeLocalMutationMetadata(
        existing: CollaborationRevisionMetadata?,
        observedShared: CollaborationRevisionMetadata?,
        currentFields: CollaborationFieldSnapshot,
        isDeleted: Bool
    ) -> CollaborationRevisionMetadata {
        guard let existing else {
            if let observedShared {
                let identity = CollaborationIdentityProvider.current()
                return CollaborationRevisionMetadata(
                    modifiedAt: .now,
                    revision: observedShared.revision + 1,
                    modifiedByParticipantID: identity.participantID,
                    modifiedByDeviceID: identity.deviceID,
                    baseRevision: observedShared.revision,
                    baseFieldValues: observedShared.currentFieldValues,
                    currentFieldValues: currentFields,
                    isDeleted: isDeleted
                )
            }
            return CollaborationRevisionMetadata.localBootstrap(
                fieldValues: currentFields,
                isDeleted: isDeleted
            )
        }

        var baseRevision = existing.baseRevision
        var baseFields = existing.baseFieldValues
        if let observedShared,
           observedShared.revision == existing.revision,
           observedShared.currentFieldValues == existing.currentFieldValues {
            baseRevision = existing.revision
            baseFields = existing.currentFieldValues
        }

        let identity = CollaborationIdentityProvider.current()
        let now = Date.now
        let monotonicModifiedAt = now > existing.modifiedAt
            ? now
            : existing.modifiedAt.addingTimeInterval(0.001)
        return CollaborationRevisionMetadata(
            modifiedAt: monotonicModifiedAt,
            revision: existing.revision + 1,
            modifiedByParticipantID: identity.participantID,
            modifiedByDeviceID: identity.deviceID,
            baseRevision: baseRevision,
            baseFieldValues: baseFields,
            currentFieldValues: currentFields,
            isDeleted: isDeleted
        )
    }

    private static func makeAcceptedSharedMetadata(
        incoming: CollaborationRevisionMetadata?,
        currentFields: CollaborationFieldSnapshot,
        isDeleted: Bool
    ) -> CollaborationRevisionMetadata {
        guard var incoming else {
            return CollaborationRevisionMetadata.legacySharedBootstrap(
                fieldValues: currentFields,
                isDeleted: isDeleted,
                modifiedAt: .now
            ).acceptingAsCommonRevision()
        }

        incoming.currentFieldValues = currentFields
        incoming.isDeleted = isDeleted
        return incoming.acceptingAsCommonRevision()
    }
}
