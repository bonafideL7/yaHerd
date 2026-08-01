import CoreData
import Foundation

/// Entity-specific batches route Working Session records through the current
/// unreleased V1 importer without duplicating bridge orchestration.
struct WorkingSessionV1ImportBatch {
    let records: [SharedWorkingSessionRecord]
}

struct WorkingQueueItemV1ImportBatch {
    let records: [SharedWorkingQueueItemRecord]
}

struct WorkingTreatmentRecordV1ImportBatch {
    let records: [SharedWorkingTreatmentRecord]
}

extension HerdSharingCoreDataStore {
    func canonicalImportRecords(
        _ records: [SharedWorkingSessionRecord]
    ) -> WorkingSessionV1ImportBatch {
        WorkingSessionV1ImportBatch(records: canonicalWorkingV1Records(records))
    }

    func canonicalImportRecords(
        _ records: [SharedWorkingQueueItemRecord]
    ) -> WorkingQueueItemV1ImportBatch {
        WorkingQueueItemV1ImportBatch(records: canonicalWorkingV1Records(records))
    }

    func canonicalImportRecords(
        _ records: [SharedWorkingTreatmentRecord]
    ) -> WorkingTreatmentRecordV1ImportBatch {
        WorkingTreatmentRecordV1ImportBatch(records: canonicalWorkingV1Records(records))
    }

    private func canonicalWorkingV1Records<Record: NSManagedObject>(
        _ records: [Record]
    ) -> [Record] {
        var recordsByPublicID: [String: Record] = [:]
        for record in records {
            guard let publicID = record.value(forKey: "publicID") as? String,
                  !publicID.isEmpty else {
                continue
            }
            guard let existing = recordsByPublicID[publicID] else {
                recordsByPublicID[publicID] = record
                continue
            }
            let existingDate = existing.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
            let candidateDate = record.value(forKey: "lastMirroredAt") as? Date ?? .distantPast
            let candidateWins = candidateDate > existingDate
                || (candidateDate == existingDate
                    && record.objectID.uriRepresentation().absoluteString
                        < existing.objectID.uriRepresentation().absoluteString)
            if candidateWins {
                recordsByPublicID[publicID] = record
            }
        }
        return recordsByPublicID.values.sorted { lhs, rhs in
            let lhsID = lhs.value(forKey: "publicID") as? String ?? ""
            let rhsID = rhs.value(forKey: "publicID") as? String ?? ""
            return lhsID < rhsID
        }
    }

    func workingV1ConflictSnapshot(
        for session: WorkingSession
    ) -> [String: HerdSharingBridgeConflictValue] {
        workingV1ConflictSnapshot([
            "date": session.date,
            "status": session.status.rawValue,
            "sourcePasturePublicID": session.sourcePasture?.publicID,
            "protocolName": session.protocolName,
            "protocolItems": session.protocolItems,
            "notes": session.notes,
        ])
    }

    func workingV1ConflictSnapshot(
        for queueItem: WorkingQueueItem
    ) -> [String: HerdSharingBridgeConflictValue] {
        workingV1ConflictSnapshot([
            "status": queueItem.status.rawValue,
            "completedAt": queueItem.completedAt,
            "collectedFromPasturePublicID": queueItem.collectedFromPasture?.publicID,
            "destinationPasturePublicID": queueItem.destinationPasture?.publicID,
            "workNotes": queueItem.workNotes,
            "sessionPublicID": queueItem.session?.publicID,
            "animalPublicID": queueItem.animal?.publicID,
        ])
    }

    func workingV1ConflictSnapshot(
        for treatmentRecord: WorkingTreatmentRecord
    ) -> [String: HerdSharingBridgeConflictValue] {
        workingV1ConflictSnapshot([
            "date": treatmentRecord.date,
            "treatmentItemID": treatmentRecord.treatmentItemID,
            "itemName": treatmentRecord.itemName,
            "given": treatmentRecord.given,
            "doseAmount": treatmentRecord.doseAmount,
            "doseUnit": treatmentRecord.doseUnit?.rawValue,
            "administrationRoute": treatmentRecord.administrationRoute?.rawValue,
            "sessionPublicID": treatmentRecord.session?.publicID,
            "animalPublicID": treatmentRecord.animal?.publicID,
        ])
    }

    private func workingV1ConflictSnapshot(
        _ values: [String: Any?]
    ) -> [String: HerdSharingBridgeConflictValue] {
        values.reduce(into: [String: HerdSharingBridgeConflictValue]()) { result, entry in
            result[entry.key] = workingV1ConflictValue(entry.value)
        }
    }

    private func workingV1ConflictValue(_ value: Any?) -> HerdSharingBridgeConflictValue {
        guard let value else { return .null }
        if let date = value as? Date {
            return HerdSharingBridgeConflictValue(
                type: .date,
                encodedValue: ISO8601DateFormatter().string(from: date)
            )
        }
        if let uuid = value as? UUID {
            return HerdSharingBridgeConflictValue(type: .uuid, encodedValue: uuid.uuidString)
        }
        if let bool = value as? Bool {
            return HerdSharingBridgeConflictValue(
                type: .bool,
                encodedValue: bool ? "true" : "false"
            )
        }
        if let int = value as? Int {
            return HerdSharingBridgeConflictValue(type: .int, encodedValue: String(int))
        }
        if let double = value as? Double {
            return HerdSharingBridgeConflictValue(type: .double, encodedValue: String(double))
        }
        if let string = value as? String {
            return HerdSharingBridgeConflictValue(type: .string, encodedValue: string)
        }
        return HerdSharingBridgeConflictValue(
            type: .string,
            encodedValue: String(describing: value)
        )
    }
}
