import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    struct PublicIDRepairBackup: Codable {
        let formatVersion: Int
        let createdAt: Date
        let assessment: PublicIDRepairAssessment
        let replacements: [PublicIDRepairReplacement]
        let referenceUpdates: [PublicIDRepairReferenceUpdate]
        let resolutions: [PublicIDRepairReferenceResolution]
        let aggregates: [BackupAggregate]
        let treatmentItems: [BackupTreatmentItem]
        let revisionRecords: [BackupRevisionRecord]
    }

    struct BackupAggregate: Codable {
        let entityType: PublicIDRepairEntityType
        let stableRecordIdentifier: String
        let recordDescription: String
        let publicID: UUID
        let herdPublicID: UUID?
        let sharedFields: CollaborationFieldSnapshot
    }

    struct BackupTreatmentItem: Codable {
        let entityType: PublicIDRepairEntityType
        let ownerStableRecordIdentifier: String
        let itemIndex: Int
        let item: WorkingProtocolItem
    }

    struct BackupRevisionRecord: Codable {
        let stableRecordIdentifier: String
        let publicID: UUID
        let aggregateKey: String
        let sourceEntityName: String
        let aggregatePublicID: UUID
        let herdPublicID: UUID?
        let modifiedAt: Date
        let revision: Int
        let modifiedByParticipantID: String
        let modifiedByDeviceID: String
        let baseRevision: Int
        let baseFieldValuesData: Data?
        let currentFieldValuesData: Data?
        let isDeleted: Bool
    }

    func createBackup(
        loaded: LoadedRecords,
        plan: RepairPlan,
        assessment: PublicIDRepairAssessment,
        referenceUpdates: [PublicIDRepairReferenceUpdate],
        resolutions: [PublicIDRepairReferenceResolution]
    ) throws -> URL {
        let backup = PublicIDRepairBackup(
            formatVersion: 4,
            createdAt: .now,
            assessment: assessment,
            replacements: plan.reportReplacements,
            referenceUpdates: referenceUpdates,
            resolutions: resolutions.sorted { $0.id < $1.id },
            aggregates: loaded.allAggregates.map { aggregate in
                let entityType = publicIDRepairEntityType(for: aggregate)
                let localID = localRecordIdentifier(aggregate)
                let stableID = plan.candidateByLocalIdentifier[localID]?.stableRecordIdentifier
                    ?? [
                        entityType.rawValue,
                        aggregate.collaborationKey.publicID.uuidString.lowercased(),
                        deterministicDigest(
                            stableSnapshotKey(
                                CollaborationFieldSnapshotProvider.snapshot(for: aggregate)
                            )
                        ),
                        plan.graphFingerprintByLocalIdentifier[localID] ?? "",
                    ].joined(separator: "|")
                return BackupAggregate(
                    entityType: entityType,
                    stableRecordIdentifier: stableID,
                    recordDescription: recordDescription(for: aggregate),
                    publicID: aggregate.collaborationKey.publicID,
                    herdPublicID: aggregate.collaborationHerdPublicID,
                    sharedFields: CollaborationFieldSnapshotProvider.snapshot(for: aggregate)
                )
            }.sorted {
                if $0.entityType != $1.entityType {
                    return $0.entityType.rawValue < $1.entityType.rawValue
                }
                return $0.stableRecordIdentifier < $1.stableRecordIdentifier
            },
            treatmentItems: plan.treatmentLocations.map { location in
                BackupTreatmentItem(
                    entityType: location.entityType,
                    ownerStableRecordIdentifier: plan.candidateByLocalIdentifier[location.ownerLocalIdentifier]?.stableRecordIdentifier
                        ?? location.ownerLocalIdentifier,
                    itemIndex: location.itemIndex,
                    item: location.item
                )
            }.sorted {
                if $0.entityType != $1.entityType {
                    return $0.entityType.rawValue < $1.entityType.rawValue
                }
                if $0.ownerStableRecordIdentifier != $1.ownerStableRecordIdentifier {
                    return $0.ownerStableRecordIdentifier < $1.ownerStableRecordIdentifier
                }
                return $0.itemIndex < $1.itemIndex
            },
            revisionRecords: loaded.revisionRecords.map(makeBackupRevisionRecord)
                .sorted { $0.stableRecordIdentifier < $1.stableRecordIdentifier }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let directoryURL = try backupDirectoryURL()
        let filename = "yaHerd-PublicID-Repair-\(backupTimestamp()).json"
        let url = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    func backupDirectoryURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PublicIDRepairError.backupDirectoryUnavailable
        }
        let directoryURL = applicationSupportURL
            .appendingPathComponent("yaHerd", isDirectory: true)
            .appendingPathComponent("PublicIDRepairBackups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: .now)
    }

    func makeBackupRevisionRecord(
        _ record: CollaborationRevisionRecord
    ) -> BackupRevisionRecord {
        BackupRevisionRecord(
            stableRecordIdentifier: deterministicRevisionRecordIdentifier(record),
            publicID: record.publicID,
            aggregateKey: record.aggregateKey,
            sourceEntityName: record.sourceEntityName,
            aggregatePublicID: record.aggregatePublicID,
            herdPublicID: record.herdPublicID,
            modifiedAt: record.modifiedAt,
            revision: record.revision,
            modifiedByParticipantID: record.modifiedByParticipantID,
            modifiedByDeviceID: record.modifiedByDeviceID,
            baseRevision: record.baseRevision,
            baseFieldValuesData: record.baseFieldValuesData,
            currentFieldValuesData: record.currentFieldValuesData,
            isDeleted: record.isDeleted
        )
    }

}
