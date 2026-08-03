import Foundation
import SwiftData

protocol CollaborationRevisionHydrating: Sendable {
    func hydrateCollaborationRevisions(for herdPublicID: UUID) async throws
}

extension SwiftDataHerdSharingActor: CollaborationRevisionHydrating {
    func hydrateCollaborationRevisions(for herdPublicID: UUID) throws {
        let descriptor = FetchDescriptor<CollaborationRevisionRecord>(
            predicate: #Predicate<CollaborationRevisionRecord> { record in
                record.herdPublicID == herdPublicID
            },
            sortBy: [SortDescriptor(\CollaborationRevisionRecord.aggregateKey)]
        )
        let records = try modelContext.fetch(descriptor)
        var canonicalByKey: [CollaborationAggregateKey: CollaborationRevisionRecord] = [:]
        var repairedDuplicates = false

        for record in records {
            let key = record.key
            guard CollaborationAggregateType(rawValue: key.sourceEntityName) != nil else {
                continue
            }
            guard let existing = canonicalByKey[key] else {
                canonicalByKey[key] = record
                continue
            }

            let keepIncoming = record.revision > existing.revision
                || (record.revision == existing.revision && record.modifiedAt > existing.modifiedAt)
            if keepIncoming {
                modelContext.delete(existing)
                canonicalByKey[key] = record
            } else {
                modelContext.delete(record)
            }
            repairedDuplicates = true
            ReliabilityLog.persistenceEvent(
                "SwiftDataHerdSharingActor.duplicateRevisionMetadataRepaired",
                detail: key.storageKey
            )
        }

        if repairedDuplicates {
            try PersistenceLog.save(
                modelContext,
                operation: "SwiftDataHerdSharingActor.repairCollaborationRevisionMetadata"
            )
        }

        let entries = canonicalByKey.values
            .map { CollaborationRevisionRegistry.Entry(key: $0.key, metadata: $0.metadata) }
            .sorted { $0.key.storageKey < $1.key.storageKey }
        CollaborationRevisionRegistry.registerAuthoritativeLocals(entries)
    }
}
