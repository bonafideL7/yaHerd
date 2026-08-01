import Foundation
import SwiftData

extension HerdSharingCoreDataStore {
    func upsertSwiftDataWorkingSessions(
        from batch: WorkingSessionV1ImportBatch,
        herd: Herd,
        in context: ModelContext
    ) throws -> (
        inserted: Int,
        updated: Int,
        updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
    ) {
        let validSharedRecords = batch.records.compactMap {
            record -> (SharedWorkingSessionRecord, UUID)? in
            guard let publicID = record.parsedPublicID else { return nil }
            return (record, publicID)
        }
        guard !validSharedRecords.isEmpty else { return (0, 0, []) }

        var sessionsByPublicID: [UUID: WorkingSession] = [:]
        for session in try context.fetch(FetchDescriptor<WorkingSession>())
        where sessionsByPublicID[session.publicID] == nil {
            sessionsByPublicID[session.publicID] = session
        }

        var pasturesByPublicID: [UUID: Pasture] = [:]
        for pasture in try context.fetch(FetchDescriptor<Pasture>())
        where pasturesByPublicID[pasture.publicID] == nil {
            pasturesByPublicID[pasture.publicID] = pasture
        }

        var inserted = 0
        var updated = 0
        var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

        for (record, publicID) in validSharedRecords {
            let session: WorkingSession
            var beforeFieldSnapshot: HerdSharingSwiftDataImportEngine.HerdSharingConflictFieldSnapshot?
            if let existingSession = sessionsByPublicID[publicID] {
                session = existingSession
                updated += 1
                beforeFieldSnapshot = workingV1ConflictSnapshot(for: session)
            } else {
                session = WorkingSession(
                    publicID: publicID,
                    date: record.date ?? Date.now,
                    status: record.parsedStatus,
                    sourcePasture: record.parsedSourcePasturePublicID.flatMap {
                        pasturesByPublicID[$0]
                    },
                    protocolName: record.protocolName ?? "",
                    protocolItems: record.parsedProtocolItems,
                    notes: record.notes
                )
                context.insert(session)
                sessionsByPublicID[publicID] = session
                inserted += 1
            }

            applyWorkingV1(
                record,
                to: session,
                herd: herd,
                pasturesByPublicID: pasturesByPublicID
            )
            if let beforeFieldSnapshot {
                updatedRecordConflicts.append(
                    HerdSharingSwiftDataImportEngine.updatedRecordConflict(
                        sourceEntityName: SharedWorkingSessionRecord.entityName,
                        publicID: publicID,
                        localModifiedAt: nil,
                        sharedModifiedAt: record.lastMirroredAt,
                        before: beforeFieldSnapshot,
                        after: workingV1ConflictSnapshot(for: session)
                    )
                )
            }
        }

        return (inserted, updated, updatedRecordConflicts)
    }

    private func applyWorkingV1(
        _ sharedRecord: SharedWorkingSessionRecord,
        to session: WorkingSession,
        herd: Herd,
        pasturesByPublicID: [UUID: Pasture]
    ) {
        session.herd = herd
        session.date = sharedRecord.date ?? session.date
        session.status = sharedRecord.parsedStatus
        session.sourcePasture = sharedRecord.parsedSourcePasturePublicID.flatMap {
            pasturesByPublicID[$0]
        }
        session.protocolName = sharedRecord.protocolName ?? ""
        session.protocolItems = sharedRecord.parsedProtocolItems
        session.currentQueueIndex = 0
        session.notes = sharedRecord.notes
    }
}
