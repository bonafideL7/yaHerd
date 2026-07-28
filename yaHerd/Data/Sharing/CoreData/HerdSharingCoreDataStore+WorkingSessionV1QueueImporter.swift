import Foundation
import SwiftData

extension HerdSharingCoreDataStore {
    func upsertSwiftDataWorkingQueueItems(
        from batch: WorkingQueueItemV1ImportBatch,
        herd: Herd,
        in context: ModelContext
    ) throws -> (
        inserted: Int,
        updated: Int,
        updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
    ) {
        let validSharedRecords = batch.records.compactMap {
            record -> (SharedWorkingQueueItemRecord, UUID, UUID, UUID)? in
            guard let publicID = record.parsedPublicID,
                  let sessionPublicID = record.parsedSessionPublicID,
                  let animalPublicID = record.parsedAnimalPublicID else {
                return nil
            }
            return (record, publicID, sessionPublicID, animalPublicID)
        }
        guard !validSharedRecords.isEmpty else { return (0, 0, []) }

        var queueItemsByPublicID: [UUID: WorkingQueueItem] = [:]
        for queueItem in try context.fetch(FetchDescriptor<WorkingQueueItem>())
        where queueItemsByPublicID[queueItem.publicID] == nil {
            queueItemsByPublicID[queueItem.publicID] = queueItem
        }

        var sessionsByPublicID: [UUID: WorkingSession] = [:]
        for session in try context.fetch(FetchDescriptor<WorkingSession>())
        where sessionsByPublicID[session.publicID] == nil {
            sessionsByPublicID[session.publicID] = session
        }

        var animalsByPublicID: [UUID: Animal] = [:]
        for animal in try context.fetch(FetchDescriptor<Animal>())
        where animalsByPublicID[animal.publicID] == nil {
            animalsByPublicID[animal.publicID] = animal
        }

        var pasturesByPublicID: [UUID: Pasture] = [:]
        for pasture in try context.fetch(FetchDescriptor<Pasture>())
        where pasturesByPublicID[pasture.publicID] == nil {
            pasturesByPublicID[pasture.publicID] = pasture
        }

        var inserted = 0
        var updated = 0
        var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

        for (record, publicID, sessionPublicID, animalPublicID) in validSharedRecords {
            guard let session = sessionsByPublicID[sessionPublicID],
                  let animal = animalsByPublicID[animalPublicID] else {
                continue
            }

            let queueItem: WorkingQueueItem
            var beforeFieldSnapshot: HerdSharingConflictFieldSnapshot?
            if let existingQueueItem = queueItemsByPublicID[publicID] {
                queueItem = existingQueueItem
                updated += 1
                beforeFieldSnapshot = workingV1ConflictSnapshot(for: queueItem)
            } else {
                queueItem = WorkingQueueItem(
                    publicID: publicID,
                    status: record.parsedStatus,
                    collectedFromPasture: record.parsedCollectedFromPasturePublicID.flatMap {
                        pasturesByPublicID[$0]
                    },
                    destinationPasture: record.parsedDestinationPasturePublicID.flatMap {
                        pasturesByPublicID[$0]
                    },
                    workNotes: record.workNotes,
                    animal: animal,
                    session: session
                )
                context.insert(queueItem)
                queueItemsByPublicID[publicID] = queueItem
                inserted += 1
            }

            applyWorkingV1(
                record,
                to: queueItem,
                herd: herd,
                session: session,
                animal: animal,
                pasturesByPublicID: pasturesByPublicID
            )
            if let beforeFieldSnapshot {
                updatedRecordConflicts.append(
                    updatedRecordConflict(
                        sourceEntityName: SharedWorkingQueueItemRecord.entityName,
                        publicID: publicID,
                        localModifiedAt: nil,
                        sharedModifiedAt: record.lastMirroredAt,
                        before: beforeFieldSnapshot,
                        after: workingV1ConflictSnapshot(for: queueItem)
                    )
                )
            }
        }

        return (inserted, updated, updatedRecordConflicts)
    }

    private func applyWorkingV1(
        _ sharedRecord: SharedWorkingQueueItemRecord,
        to queueItem: WorkingQueueItem,
        herd: Herd,
        session: WorkingSession,
        animal: Animal,
        pasturesByPublicID: [UUID: Pasture]
    ) {
        queueItem.herd = herd
        queueItem.session = session
        queueItem.animal = animal
        queueItem.queueOrder = 0
        queueItem.status = sharedRecord.parsedStatus
        queueItem.completedAt = sharedRecord.completedAt
        queueItem.collectedFromPasture = sharedRecord.parsedCollectedFromPasturePublicID.flatMap {
            pasturesByPublicID[$0]
        }
        queueItem.destinationPasture = sharedRecord.parsedDestinationPasturePublicID.flatMap {
            pasturesByPublicID[$0]
        }
        queueItem.workNotes = sharedRecord.workNotes

        if session.status == .active {
            animal.activeWorkingSession = session
        } else if animal.activeWorkingSession?.publicID == session.publicID {
            animal.activeWorkingSession = nil
        }
    }
}
