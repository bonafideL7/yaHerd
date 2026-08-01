import Foundation
import SwiftData

extension HerdSharingCoreDataStore {
    func upsertSwiftDataWorkingTreatmentRecords(
        from batch: WorkingTreatmentRecordV1ImportBatch,
        herd: Herd,
        in context: ModelContext
    ) throws -> (
        inserted: Int,
        updated: Int,
        updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
    ) {
        let validSharedRecords = batch.records.compactMap {
            record -> (SharedWorkingTreatmentRecord, UUID, UUID, UUID)? in
            guard let publicID = record.parsedPublicID,
                  let sessionPublicID = record.parsedSessionPublicID,
                  let animalPublicID = record.parsedAnimalPublicID else {
                return nil
            }
            return (record, publicID, sessionPublicID, animalPublicID)
        }
        guard !validSharedRecords.isEmpty else { return (0, 0, []) }

        var treatmentRecordsByPublicID: [UUID: WorkingTreatmentRecord] = [:]
        for treatmentRecord in try context.fetch(FetchDescriptor<WorkingTreatmentRecord>())
        where treatmentRecordsByPublicID[treatmentRecord.publicID] == nil {
            treatmentRecordsByPublicID[treatmentRecord.publicID] = treatmentRecord
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

        var inserted = 0
        var updated = 0
        var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []

        for (record, publicID, sessionPublicID, animalPublicID) in validSharedRecords {
            guard let session = sessionsByPublicID[sessionPublicID],
                  let animal = animalsByPublicID[animalPublicID] else {
                continue
            }
            guard let treatmentItemID = resolvedTreatmentItemID(
                from: record,
                session: session
            ) else {
                throw HerdSharingActionError.bridgeImportFailed(
                    "A shared treatment record is missing a stable treatment-item identifier."
                )
            }

            let treatmentRecord: WorkingTreatmentRecord
            var beforeFieldSnapshot: HerdSharingSwiftDataImportEngine.HerdSharingConflictFieldSnapshot?
            if let existingTreatmentRecord = treatmentRecordsByPublicID[publicID] {
                treatmentRecord = existingTreatmentRecord
                updated += 1
                beforeFieldSnapshot = workingV1ConflictSnapshot(for: treatmentRecord)
            } else {
                treatmentRecord = WorkingTreatmentRecord(
                    publicID: publicID,
                    date: record.date ?? Date.now,
                    treatmentItemID: treatmentItemID,
                    itemName: record.itemName ?? "",
                    given: record.given?.boolValue ?? false,
                    dose: record.parsedDose,
                    animal: animal,
                    session: session
                )
                context.insert(treatmentRecord)
                treatmentRecordsByPublicID[publicID] = treatmentRecord
                inserted += 1
            }

            applyWorkingV1(
                record,
                treatmentItemID: treatmentItemID,
                to: treatmentRecord,
                herd: herd,
                session: session,
                animal: animal
            )
            if let beforeFieldSnapshot {
                updatedRecordConflicts.append(
                    HerdSharingSwiftDataImportEngine.updatedRecordConflict(
                        sourceEntityName: SharedWorkingTreatmentRecord.entityName,
                        publicID: publicID,
                        localModifiedAt: nil,
                        sharedModifiedAt: record.lastMirroredAt,
                        before: beforeFieldSnapshot,
                        after: workingV1ConflictSnapshot(for: treatmentRecord)
                    )
                )
            }
        }

        return (inserted, updated, updatedRecordConflicts)
    }

    private func applyWorkingV1(
        _ sharedRecord: SharedWorkingTreatmentRecord,
        treatmentItemID: UUID,
        to treatmentRecord: WorkingTreatmentRecord,
        herd: Herd,
        session: WorkingSession,
        animal: Animal
    ) {
        treatmentRecord.herd = herd
        treatmentRecord.session = session
        treatmentRecord.animal = animal
        treatmentRecord.date = sharedRecord.date ?? treatmentRecord.date
        treatmentRecord.treatmentItemID = treatmentItemID
        treatmentRecord.itemName = sharedRecord.itemName ?? ""
        treatmentRecord.given = sharedRecord.given?.boolValue ?? false
        treatmentRecord.dose = sharedRecord.parsedDose
    }

    private func resolvedTreatmentItemID(
        from sharedRecord: SharedWorkingTreatmentRecord,
        session: WorkingSession
    ) -> UUID? {
        sharedRecord.parsedTreatmentItemID
            ?? session.protocolItems.first(where: { $0.name == sharedRecord.itemName })?.id
    }
}
