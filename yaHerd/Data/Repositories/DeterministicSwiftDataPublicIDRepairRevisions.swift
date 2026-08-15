import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func synchronizeRevisionRecords(loaded: LoadedRecords) throws {
        var recordsByKey: [CollaborationAggregateKey: CollaborationRevisionRecord] = [:]
        for record in loaded.revisionRecords.sorted(by: preferredRevisionRecord) {
            let key = record.key
            if recordsByKey[key] == nil {
                recordsByKey[key] = record
            } else {
                modelContext.delete(record)
            }
        }

        let identity = CollaborationIdentityProvider.current()
        for aggregate in loaded.allAggregates {
            let key = aggregate.collaborationKey
            let fields = CollaborationFieldSnapshotProvider.snapshot(for: aggregate)
            if let record = recordsByKey[key] {
                let existing = record.metadata
                record.aggregateKey = key.storageKey
                record.sourceEntityName = key.sourceEntityName
                record.aggregatePublicID = key.publicID
                record.herdPublicID = aggregate.collaborationHerdPublicID

                guard existing.currentFieldValues != fields || existing.isDeleted else {
                    continue
                }
                let now = Date.now
                record.apply(
                    CollaborationRevisionMetadata(
                        modifiedAt: now > existing.modifiedAt
                            ? now
                            : existing.modifiedAt.addingTimeInterval(0.001),
                        revision: max(existing.revision + 1, 1),
                        modifiedByParticipantID: identity.participantID,
                        modifiedByDeviceID: identity.deviceID,
                        baseRevision: existing.revision,
                        baseFieldValues: existing.currentFieldValues,
                        currentFieldValues: fields,
                        isDeleted: false
                    )
                )
            } else {
                let record = CollaborationRevisionRecord(
                    key: key,
                    herdPublicID: aggregate.collaborationHerdPublicID,
                    metadata: .localBootstrap(fieldValues: fields)
                )
                modelContext.insert(record)
                recordsByKey[key] = record
            }
        }
    }

    func preferredRevisionRecord(
        _ lhs: CollaborationRevisionRecord,
        _ rhs: CollaborationRevisionRecord
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return deterministicRevisionRecordIdentifier(lhs)
            < deterministicRevisionRecordIdentifier(rhs)
    }

    func deterministicRevisionRecordIdentifier(
        _ record: CollaborationRevisionRecord
    ) -> String {
        let components = [
            record.publicID.uuidString.lowercased(),
            record.aggregateKey,
            record.sourceEntityName,
            record.aggregatePublicID.uuidString.lowercased(),
            record.herdPublicID?.uuidString.lowercased() ?? "",
            String(record.modifiedAt.timeIntervalSinceReferenceDate),
            String(record.revision),
            record.modifiedByParticipantID,
            record.modifiedByDeviceID,
            String(record.baseRevision),
            record.baseFieldValuesData?.base64EncodedString() ?? "",
            record.currentFieldValuesData?.base64EncodedString() ?? "",
            String(record.isDeleted),
        ].joined(separator: "|")
        return "revision|\(deterministicDigest(components))"
    }

    func registerCurrentRevisionMetadata(
        _ aggregates: [any CollaborativelyMutableAggregate]
    ) {
        for aggregate in aggregates {
            let key = aggregate.collaborationKey
            let aggregateKey = key.storageKey
            var descriptor = FetchDescriptor<CollaborationRevisionRecord>(
                predicate: #Predicate<CollaborationRevisionRecord> { record in
                    record.aggregateKey == aggregateKey
                },
                sortBy: [
                    SortDescriptor(\CollaborationRevisionRecord.revision, order: .reverse),
                    SortDescriptor(\CollaborationRevisionRecord.modifiedAt, order: .reverse),
                ]
            )
            descriptor.fetchLimit = 1
            guard let record = try? modelContext.fetch(descriptor).first else { continue }
            CollaborationRevisionRegistry.registerLocal(record.metadata, for: key)
        }
    }

}
