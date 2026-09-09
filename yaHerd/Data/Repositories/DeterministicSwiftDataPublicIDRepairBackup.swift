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
        var candidateByLocalIdentifier: [String: DuplicateCandidate] = [:]
        candidateByLocalIdentifier.reserveCapacity(plan.candidates.count)
        for candidate in plan.candidates {
            candidateByLocalIdentifier[candidate.localIdentifier] = candidate
        }
        let graphFingerprintByLocalIdentifier = plan.graphFingerprintByLocalIdentifier

        var reportReplacements: [PublicIDRepairReplacement] = []
        reportReplacements.reserveCapacity(plan.replacements.count)
        for replacement in plan.replacements {
            reportReplacements.append(replacement.report)
        }

        var aggregateBackups: [BackupAggregate] = []
        appendBackupAggregates(
            loaded.herds,
            entityType: .herd,
            publicID: { $0.publicID },
            herdPublicID: { $0.publicID },
            description: { $0.name.isEmpty ? "Unnamed herd" : $0.name },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.tagColorDefinitions,
            entityType: .tagColorDefinition,
            publicID: { $0.id },
            herdPublicID: { $0.herd?.publicID },
            description: { $0.name.isEmpty ? "Unnamed tag color" : $0.name },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.animalStatusReferences,
            entityType: .animalStatusReference,
            publicID: { $0.id },
            herdPublicID: { $0.herd?.publicID },
            description: { $0.name.isEmpty ? "Unnamed status" : $0.name },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.pastureGroups,
            entityType: .pastureGroup,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID },
            description: { $0.name.isEmpty ? "Unnamed pasture group" : $0.name },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.pastures,
            entityType: .pasture,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID },
            description: { $0.name.isEmpty ? "Unnamed pasture" : $0.name },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.animals,
            entityType: .animal,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID },
            description: { self.animalDescription($0) },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.animalTags,
            entityType: .animalTag,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: {
                $0.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \($0.normalizedNumber)"
            },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.movements,
            entityType: .movement,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { "Movement on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.statusRecords,
            entityType: .statusRecord,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { "Status change on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.workingProtocolTemplates,
            entityType: .workingProtocolTemplate,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID },
            description: { $0.name.isEmpty ? "Unnamed working protocol" : $0.name },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.workingSessions,
            entityType: .workingSession,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID },
            description: { "Working session on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.workingQueueItems,
            entityType: .workingQueueItem,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.session?.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { "Working item for \(self.animalDescription($0.animal))" },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.workingTreatmentRecords,
            entityType: .workingTreatmentRecord,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.session?.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { $0.itemName.isEmpty ? "Unnamed treatment" : $0.itemName },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.healthRecords,
            entityType: .healthRecord,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { $0.treatment.isEmpty ? "Health record" : $0.treatment },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.pregnancyChecks,
            entityType: .pregnancyCheck,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { "Pregnancy check on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.fieldCheckSessions,
            entityType: .fieldCheckSession,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID },
            description: {
                "Field check for \($0.pastureNameSnapshot.isEmpty ? "unknown pasture" : $0.pastureNameSnapshot)"
            },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.fieldCheckAnimalChecks,
            entityType: .fieldCheckAnimalCheck,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.session?.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { "Animal check \($0.displayTagNumber)" },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        appendBackupAggregates(
            loaded.fieldCheckFindings,
            entityType: .fieldCheckFinding,
            publicID: { $0.publicID },
            herdPublicID: { $0.herd?.publicID ?? $0.session?.herd?.publicID ?? $0.animal?.herd?.publicID },
            description: { $0.note.isEmpty ? "Field check finding" : $0.note },
            candidateByLocalIdentifier: candidateByLocalIdentifier,
            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
            to: &aggregateBackups
        )
        aggregateBackups.sort {
            if $0.entityType != $1.entityType {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            return $0.stableRecordIdentifier < $1.stableRecordIdentifier
        }

        var treatmentItemBackups: [BackupTreatmentItem] = []
        treatmentItemBackups.reserveCapacity(plan.treatmentLocations.count)
        for location in plan.treatmentLocations {
            treatmentItemBackups.append(
                BackupTreatmentItem(
                    entityType: location.entityType,
                    ownerStableRecordIdentifier: candidateByLocalIdentifier[location.ownerLocalIdentifier]?.stableRecordIdentifier
                        ?? location.ownerLocalIdentifier,
                    itemIndex: location.itemIndex,
                    item: location.item
                )
            )
        }
        treatmentItemBackups.sort {
            if $0.entityType != $1.entityType {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            if $0.ownerStableRecordIdentifier != $1.ownerStableRecordIdentifier {
                return $0.ownerStableRecordIdentifier < $1.ownerStableRecordIdentifier
            }
            return $0.itemIndex < $1.itemIndex
        }

        var revisionRecordBackups: [BackupRevisionRecord] = []
        revisionRecordBackups.reserveCapacity(loaded.revisionRecords.count)
        for record in loaded.revisionRecords {
            revisionRecordBackups.append(makeBackupRevisionRecord(record))
        }
        revisionRecordBackups.sort { $0.stableRecordIdentifier < $1.stableRecordIdentifier }

        let backup = PublicIDRepairBackup(
            formatVersion: 4,
            createdAt: .now,
            assessment: assessment,
            replacements: reportReplacements,
            referenceUpdates: referenceUpdates,
            resolutions: resolutions.sorted { $0.id < $1.id },
            aggregates: aggregateBackups,
            treatmentItems: treatmentItemBackups,
            revisionRecords: revisionRecordBackups
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let directoryURL = try backupDirectoryURL()
        // Every committed generation needs an independent recovery point. A timestamp alone can
        // collide when chained repairs are created within the same millisecond, which would let a
        // later generation overwrite the prior generation's backup.
        let filename = "yaHerd-PublicID-Repair-\(backupTimestamp())-\(UUID().uuidString.lowercased()).json"
        let url = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try PublicIDRepairDurableFile.persist(data, to: url)
        return url
    }

    func appendBackupAggregates<Model>(
        _ records: [Model],
        entityType: PublicIDRepairEntityType,
        publicID: (Model) -> UUID,
        herdPublicID: (Model) -> UUID?,
        description: (Model) -> String,
        candidateByLocalIdentifier: [String: DuplicateCandidate],
        graphFingerprintByLocalIdentifier: [String: String],
        to backups: inout [BackupAggregate]
    ) where Model: PersistentModel, Model: CollaborativelyMutableAggregate {
        backups.reserveCapacity(backups.count + records.count)
        for record in records {
            let localID = localRecordIdentifier(record)
            let recordPublicID = publicID(record)
            let sharedFields = CollaborationFieldSnapshotProvider.snapshot(for: record)
            let stableID = candidateByLocalIdentifier[localID]?.stableRecordIdentifier
                ?? [
                    entityType.rawValue,
                    recordPublicID.uuidString.lowercased(),
                    deterministicDigest(stableSnapshotKey(sharedFields)),
                    graphFingerprintByLocalIdentifier[localID] ?? "",
                ].joined(separator: "|")
            backups.append(
                BackupAggregate(
                    entityType: entityType,
                    stableRecordIdentifier: stableID,
                    recordDescription: description(record),
                    publicID: recordPublicID,
                    herdPublicID: herdPublicID(record),
                    sharedFields: sharedFields
                )
            )
        }
    }

    func backupDirectoryURL() throws -> URL {
        #if DEBUG
        if let backupDirectoryOverrideForTesting {
            try FileManager.default.createDirectory(
                at: backupDirectoryOverrideForTesting,
                withIntermediateDirectories: true
            )
            return backupDirectoryOverrideForTesting
        }
        #endif

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
