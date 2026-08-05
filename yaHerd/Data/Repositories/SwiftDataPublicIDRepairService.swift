import CryptoKit
import Foundation
import SwiftData

@ModelActor
actor SwiftDataPublicIDRepairService: PublicIDRepairService {
    private struct LoadedRecords {
        let herds: [Herd]
        let tagColorDefinitions: [TagColorDefinition]
        let animalStatusReferences: [AnimalStatusReference]
        let pastureGroups: [PastureGroup]
        let pastures: [Pasture]
        let animals: [Animal]
        let animalTags: [AnimalTag]
        let movements: [MovementRecord]
        let statusRecords: [StatusRecord]
        let workingProtocolTemplates: [WorkingProtocolTemplate]
        let workingSessions: [WorkingSession]
        let workingQueueItems: [WorkingQueueItem]
        let workingTreatmentRecords: [WorkingTreatmentRecord]
        let healthRecords: [HealthRecord]
        let pregnancyChecks: [PregnancyCheck]
        let fieldCheckSessions: [FieldCheckSession]
        let fieldCheckAnimalChecks: [FieldCheckAnimalCheck]
        let fieldCheckFindings: [FieldCheckFinding]
        let revisionRecords: [CollaborationRevisionRecord]

        var allAggregates: [any CollaborativelyMutableAggregate] {
            var result: [any CollaborativelyMutableAggregate] = []
            result.reserveCapacity(
                herds.count
                    + tagColorDefinitions.count
                    + animalStatusReferences.count
                    + pastureGroups.count
                    + pastures.count
                    + animals.count
                    + animalTags.count
                    + movements.count
                    + statusRecords.count
                    + workingProtocolTemplates.count
                    + workingSessions.count
                    + workingQueueItems.count
                    + workingTreatmentRecords.count
                    + healthRecords.count
                    + pregnancyChecks.count
                    + fieldCheckSessions.count
                    + fieldCheckAnimalChecks.count
                    + fieldCheckFindings.count
            )
            result.append(contentsOf: herds)
            result.append(contentsOf: tagColorDefinitions)
            result.append(contentsOf: animalStatusReferences)
            result.append(contentsOf: pastureGroups)
            result.append(contentsOf: pastures)
            result.append(contentsOf: animals)
            result.append(contentsOf: animalTags)
            result.append(contentsOf: movements)
            result.append(contentsOf: statusRecords)
            result.append(contentsOf: workingProtocolTemplates)
            result.append(contentsOf: workingSessions)
            result.append(contentsOf: workingQueueItems)
            result.append(contentsOf: workingTreatmentRecords)
            result.append(contentsOf: healthRecords)
            result.append(contentsOf: pregnancyChecks)
            result.append(contentsOf: fieldCheckSessions)
            result.append(contentsOf: fieldCheckAnimalChecks)
            result.append(contentsOf: fieldCheckFindings)
            return result
        }
    }

    private struct PlannedReplacement {
        let report: PublicIDRepairReplacement
        let aggregate: any CollaborativelyMutableAggregate
        let readPublicID: () -> UUID
        let assignPublicID: (UUID) -> Void
    }

    private struct EntityPlan {
        let assessment: PublicIDRepairEntityAssessment
        let replacements: [PlannedReplacement]
    }

    private struct RepairPlan {
        let assessment: PublicIDRepairAssessment
        let replacements: [PlannedReplacement]

        var reportReplacements: [PublicIDRepairReplacement] {
            replacements.map(\.report)
        }

        var replacementIDByStableRecordIdentifier: [String: UUID] {
            Dictionary(
                uniqueKeysWithValues: replacements.map {
                    ($0.report.stableRecordIdentifier, $0.report.replacementPublicID)
                }
            )
        }
    }

    private struct PublicIDRepairBackup: Codable {
        let formatVersion: Int
        let createdAt: Date
        let assessment: PublicIDRepairAssessment
        let replacements: [PublicIDRepairReplacement]
        let referenceUpdates: [PublicIDRepairReferenceUpdate]
        let aggregates: [BackupAggregate]
        let revisionRecords: [BackupRevisionRecord]
    }

    private struct BackupAggregate: Codable {
        let entityType: PublicIDRepairEntityType
        let stableRecordIdentifier: String
        let recordDescription: String
        let publicID: UUID
        let herdPublicID: UUID?
        let sharedFields: CollaborationFieldSnapshot
    }

    private struct BackupRevisionRecord: Codable {
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

    func scan() throws -> PublicIDRepairAssessment {
        let loaded = try loadRecords()
        return makeRepairPlan(
            loaded: loaded,
            revisionMetadata: preferredRevisionMetadata(loaded.revisionRecords)
        ).assessment
    }

    func repair() throws -> PublicIDRepairReport {
        let loaded = try loadRecords()
        let plan = makeRepairPlan(
            loaded: loaded,
            revisionMetadata: preferredRevisionMetadata(loaded.revisionRecords)
        )
        guard plan.assessment.hasDuplicates else {
            throw PublicIDRepairError.noDuplicatesFound
        }

        let referenceUpdates = plannedReferenceUpdates(
            loaded: loaded,
            replacementIDByStableRecordIdentifier: plan.replacementIDByStableRecordIdentifier
        )
        let backupURL = try createBackup(
            loaded: loaded,
            plan: plan,
            referenceUpdates: referenceUpdates
        )

        do {
            for replacement in plan.replacements {
                replacement.assignPublicID(replacement.report.replacementPublicID)
            }

            applyRelationshipBackedReferenceUpdates(loaded: loaded)
            try synchronizeRevisionRecords(loaded: loaded)

            let validationIssues = try validationIssues(
                loaded: loaded,
                replacements: plan.replacements
            )
            guard validationIssues.isEmpty else {
                throw PublicIDRepairError.validationFailed(validationIssues)
            }

            try PersistenceLog.save(
                modelContext,
                operation: "SwiftDataPublicIDRepairService.repair"
            )
            registerCurrentRevisionMetadata(loaded.allAggregates)

            ReliabilityLog.persistenceEvent(
                "SwiftDataPublicIDRepairService.repair",
                detail: "reassigned=\(plan.replacements.count) references=\(referenceUpdates.count)"
            )

            return PublicIDRepairReport(
                completedAt: .now,
                assessment: plan.assessment,
                replacements: plan.reportReplacements,
                referenceUpdates: referenceUpdates,
                backupFilename: backupURL.lastPathComponent,
                backupPath: backupURL.path,
                validationIssueCount: 0
            )
        } catch {
            modelContext.rollback()
            ReliabilityLog.persistenceFailure(
                "SwiftDataPublicIDRepairService.repair",
                error: error
            )
            throw error
        }
    }

    private func loadRecords() throws -> LoadedRecords {
        LoadedRecords(
            herds: try fetchAll(Herd.self),
            tagColorDefinitions: try fetchAll(TagColorDefinition.self),
            animalStatusReferences: try fetchAll(AnimalStatusReference.self),
            pastureGroups: try fetchAll(PastureGroup.self),
            pastures: try fetchAll(Pasture.self),
            animals: try fetchAll(Animal.self),
            animalTags: try fetchAll(AnimalTag.self),
            movements: try fetchAll(MovementRecord.self),
            statusRecords: try fetchAll(StatusRecord.self),
            workingProtocolTemplates: try fetchAll(WorkingProtocolTemplate.self),
            workingSessions: try fetchAll(WorkingSession.self),
            workingQueueItems: try fetchAll(WorkingQueueItem.self),
            workingTreatmentRecords: try fetchAll(WorkingTreatmentRecord.self),
            healthRecords: try fetchAll(HealthRecord.self),
            pregnancyChecks: try fetchAll(PregnancyCheck.self),
            fieldCheckSessions: try fetchAll(FieldCheckSession.self),
            fieldCheckAnimalChecks: try fetchAll(FieldCheckAnimalCheck.self),
            fieldCheckFindings: try fetchAll(FieldCheckFinding.self),
            revisionRecords: try fetchAll(CollaborationRevisionRecord.self)
        )
    }

    private func fetchAll<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try modelContext.fetch(FetchDescriptor<Model>())
    }

    private func makeRepairPlan(
        loaded: LoadedRecords,
        revisionMetadata: [CollaborationAggregateKey: CollaborationRevisionMetadata]
    ) -> RepairPlan {
        let plans = [
            makeEntityPlan(
                records: loaded.herds,
                entityType: .herd,
                collaborationType: .herd,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.updatedAt },
                recordDescription: { $0.name.isEmpty ? "Unnamed herd" : $0.name },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.tagColorDefinitions,
                entityType: .tagColorDefinition,
                collaborationType: .tagColorDefinition,
                publicID: { $0.id },
                assignPublicID: { $0.id = $1 },
                canonicalTimestamp: { $0.updatedAt },
                recordDescription: { $0.name.isEmpty ? "Unnamed tag color" : $0.name },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.animalStatusReferences,
                entityType: .animalStatusReference,
                collaborationType: .animalStatusReference,
                publicID: { $0.id },
                assignPublicID: { $0.id = $1 },
                canonicalTimestamp: { $0.createdAt },
                recordDescription: { $0.name.isEmpty ? "Unnamed status" : $0.name },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.pastureGroups,
                entityType: .pastureGroup,
                collaborationType: .pastureGroup,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { _ in .distantPast },
                recordDescription: { $0.name.isEmpty ? "Unnamed pasture group" : $0.name },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.pastures,
                entityType: .pasture,
                collaborationType: .pasture,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.lastGrazedDate ?? .distantPast },
                recordDescription: { $0.name.isEmpty ? "Unnamed pasture" : $0.name },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.animals,
                entityType: .animal,
                collaborationType: .animal,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.softDeletedAt ?? $0.deathDate ?? $0.saleDate ?? .distantPast },
                recordDescription: { animalDescription($0) },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.animalTags,
                entityType: .animalTag,
                collaborationType: .animalTag,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.removedAt ?? $0.assignedAt },
                recordDescription: { $0.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \($0.normalizedNumber)" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.movements,
                entityType: .movement,
                collaborationType: .movement,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.date },
                recordDescription: { "Movement on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.statusRecords,
                entityType: .statusRecord,
                collaborationType: .statusRecord,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.date },
                recordDescription: { "Status change on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.workingProtocolTemplates,
                entityType: .workingProtocolTemplate,
                collaborationType: .workingProtocolTemplate,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { _ in .distantPast },
                recordDescription: { $0.name.isEmpty ? "Unnamed working protocol" : $0.name },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.workingSessions,
                entityType: .workingSession,
                collaborationType: .workingSession,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.date },
                recordDescription: { "Working session on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.workingQueueItems,
                entityType: .workingQueueItem,
                collaborationType: .workingQueueItem,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.completedAt ?? .distantPast },
                recordDescription: { "Working item for \(animalDescription($0.animal))" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.workingTreatmentRecords,
                entityType: .workingTreatmentRecord,
                collaborationType: .workingTreatmentRecord,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.date },
                recordDescription: { $0.itemName.isEmpty ? "Unnamed treatment" : $0.itemName },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.healthRecords,
                entityType: .healthRecord,
                collaborationType: .healthRecord,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.date },
                recordDescription: { $0.treatment.isEmpty ? "Health record" : $0.treatment },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.pregnancyChecks,
                entityType: .pregnancyCheck,
                collaborationType: .pregnancyCheck,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.date },
                recordDescription: { "Pregnancy check on \($0.date.formatted(date: .abbreviated, time: .omitted))" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.fieldCheckSessions,
                entityType: .fieldCheckSession,
                collaborationType: .fieldCheckSession,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.completedAt ?? $0.startedAt },
                recordDescription: { "Field check for \($0.pastureNameSnapshot.isEmpty ? "unknown pasture" : $0.pastureNameSnapshot)" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.fieldCheckAnimalChecks,
                entityType: .fieldCheckAnimalCheck,
                collaborationType: .fieldCheckAnimalCheck,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.missingConfirmedAt ?? $0.countedAt ?? .distantPast },
                recordDescription: { "Animal check \($0.displayTagNumber)" },
                revisionMetadata: revisionMetadata
            ),
            makeEntityPlan(
                records: loaded.fieldCheckFindings,
                entityType: .fieldCheckFinding,
                collaborationType: .fieldCheckFinding,
                publicID: { $0.publicID },
                assignPublicID: { $0.publicID = $1 },
                canonicalTimestamp: { $0.recordedAt },
                recordDescription: { $0.note.isEmpty ? "Field check finding" : $0.note },
                revisionMetadata: revisionMetadata
            ),
        ]

        return RepairPlan(
            assessment: PublicIDRepairAssessment(
                scannedAt: .now,
                entities: plans.map(\.assessment)
            ),
            replacements: plans.flatMap(\.replacements)
        )
    }

    private func makeEntityPlan<Model>(
        records: [Model],
        entityType: PublicIDRepairEntityType,
        collaborationType: CollaborationAggregateType,
        publicID: @escaping (Model) -> UUID,
        assignPublicID: @escaping (Model, UUID) -> Void,
        canonicalTimestamp: @escaping (Model) -> Date,
        recordDescription: @escaping (Model) -> String,
        revisionMetadata: [CollaborationAggregateKey: CollaborationRevisionMetadata]
    ) -> EntityPlan where Model: PersistentModel, Model: CollaborativelyMutableAggregate {
        let grouped = Dictionary(grouping: records, by: publicID)
        let duplicateGroups = grouped
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        var replacements: [PlannedReplacement] = []
        var usedIDs = Set(records.map(publicID))

        for (retainedID, duplicateRecords) in duplicateGroups {
            let metadata = revisionMetadata[
                CollaborationAggregateKey(type: collaborationType, publicID: retainedID)
            ]
            let ordered = duplicateRecords.sorted { lhs, rhs in
                isPreferredCanonical(
                    lhs,
                    over: rhs,
                    metadata: metadata,
                    canonicalTimestamp: canonicalTimestamp
                )
            }

            for duplicate in ordered.dropFirst() {
                let stableIdentifier = stableRecordIdentifier(duplicate)
                let replacementID = makeReplacementID(
                    entityType: entityType,
                    retainedID: retainedID,
                    stableRecordIdentifier: stableIdentifier,
                    usedIDs: &usedIDs
                )
                replacements.append(
                    PlannedReplacement(
                        report: PublicIDRepairReplacement(
                            entityType: entityType,
                            recordDescription: recordDescription(duplicate),
                            stableRecordIdentifier: stableIdentifier,
                            retainedPublicID: retainedID,
                            replacementPublicID: replacementID
                        ),
                        aggregate: duplicate,
                        readPublicID: { publicID(duplicate) },
                        assignPublicID: { assignPublicID(duplicate, $0) }
                    )
                )
            }
        }

        return EntityPlan(
            assessment: PublicIDRepairEntityAssessment(
                entityType: entityType,
                scannedRecordCount: records.count,
                duplicateGroupCount: duplicateGroups.count,
                duplicateRecordCount: replacements.count
            ),
            replacements: replacements
        )
    }

    private func isPreferredCanonical<Model>(
        _ lhs: Model,
        over rhs: Model,
        metadata: CollaborationRevisionMetadata?,
        canonicalTimestamp: (Model) -> Date
    ) -> Bool where Model: PersistentModel, Model: CollaborativelyMutableAggregate {
        let lhsSnapshot = CollaborationFieldSnapshotProvider.snapshot(for: lhs)
        let rhsSnapshot = CollaborationFieldSnapshotProvider.snapshot(for: rhs)
        let lhsMatchesRevision = metadata?.currentFieldValues == lhsSnapshot
        let rhsMatchesRevision = metadata?.currentFieldValues == rhsSnapshot
        if lhsMatchesRevision != rhsMatchesRevision {
            return lhsMatchesRevision
        }

        let lhsTimestamp = canonicalTimestamp(lhs)
        let rhsTimestamp = canonicalTimestamp(rhs)
        if lhsTimestamp != rhsTimestamp {
            return lhsTimestamp > rhsTimestamp
        }

        let lhsSnapshotKey = stableSnapshotKey(lhsSnapshot)
        let rhsSnapshotKey = stableSnapshotKey(rhsSnapshot)
        if lhsSnapshotKey != rhsSnapshotKey {
            return lhsSnapshotKey < rhsSnapshotKey
        }

        return stableRecordIdentifier(lhs) < stableRecordIdentifier(rhs)
    }

    private func preferredRevisionMetadata(
        _ records: [CollaborationRevisionRecord]
    ) -> [CollaborationAggregateKey: CollaborationRevisionMetadata] {
        var result: [CollaborationAggregateKey: CollaborationRevisionMetadata] = [:]
        for record in records {
            let key = record.key
            guard let existing = result[key] else {
                result[key] = record.metadata
                continue
            }
            if record.revision > existing.revision
                || (record.revision == existing.revision && record.modifiedAt > existing.modifiedAt) {
                result[key] = record.metadata
            }
        }
        return result
    }

    private func makeReplacementID(
        entityType: PublicIDRepairEntityType,
        retainedID: UUID,
        stableRecordIdentifier: String,
        usedIDs: inout Set<UUID>
    ) -> UUID {
        var attempt = 0
        while true {
            let seed = [
                "yaHerd-public-id-repair-v1",
                entityType.rawValue,
                retainedID.uuidString.lowercased(),
                stableRecordIdentifier,
                String(attempt),
            ].joined(separator: "|")
            let candidate = deterministicUUID(seed: seed)
            if usedIDs.insert(candidate).inserted {
                return candidate
            }
            attempt += 1
        }
    }

    private func deterministicUUID(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    private func plannedReferenceUpdates(
        loaded: LoadedRecords,
        replacementIDByStableRecordIdentifier: [String: UUID]
    ) -> [PublicIDRepairReferenceUpdate] {
        var updates: [PublicIDRepairReferenceUpdate] = []

        for session in loaded.fieldCheckSessions {
            guard let pasture = session.pasture else { continue }
            let desiredID = replacementIDByStableRecordIdentifier[stableRecordIdentifier(pasture)]
                ?? pasture.publicID
            appendReferenceUpdate(
                entityType: .fieldCheckSession,
                model: session,
                recordDescription: "Field check for \(session.pastureNameSnapshot.isEmpty ? "unknown pasture" : session.pastureNameSnapshot)",
                fieldName: "pastureID",
                previousID: session.pastureID,
                desiredID: desiredID,
                to: &updates
            )
        }

        for check in loaded.fieldCheckAnimalChecks {
            guard let animal = check.animal else { continue }
            let desiredID = replacementIDByStableRecordIdentifier[stableRecordIdentifier(animal)]
                ?? animal.publicID
            appendReferenceUpdate(
                entityType: .fieldCheckAnimalCheck,
                model: check,
                recordDescription: "Animal check \(check.displayTagNumber)",
                fieldName: "animalIDSnapshot",
                previousID: check.animalIDSnapshot,
                desiredID: desiredID,
                to: &updates
            )
        }

        for finding in loaded.fieldCheckFindings {
            if let animal = finding.animal {
                let desiredID = replacementIDByStableRecordIdentifier[stableRecordIdentifier(animal)]
                    ?? animal.publicID
                appendReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "animalIDSnapshot",
                    previousID: finding.animalIDSnapshot,
                    desiredID: desiredID,
                    to: &updates
                )
            }
            if let session = finding.session {
                let desiredID = replacementIDByStableRecordIdentifier[stableRecordIdentifier(session)]
                    ?? session.publicID
                appendReferenceUpdate(
                    entityType: .fieldCheckFinding,
                    model: finding,
                    recordDescription: finding.note.isEmpty ? "Field check finding" : finding.note,
                    fieldName: "sessionIDSnapshot",
                    previousID: finding.sessionIDSnapshot,
                    desiredID: desiredID,
                    to: &updates
                )
            }
        }

        return updates.sorted {
            if $0.entityType != $1.entityType {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            if $0.stableRecordIdentifier != $1.stableRecordIdentifier {
                return $0.stableRecordIdentifier < $1.stableRecordIdentifier
            }
            return $0.fieldName < $1.fieldName
        }
    }

    private func appendReferenceUpdate<Model: PersistentModel>(
        entityType: PublicIDRepairEntityType,
        model: Model,
        recordDescription: String,
        fieldName: String,
        previousID: UUID?,
        desiredID: UUID,
        to updates: inout [PublicIDRepairReferenceUpdate]
    ) {
        guard previousID != desiredID else { return }
        updates.append(
            PublicIDRepairReferenceUpdate(
                entityType: entityType,
                recordDescription: recordDescription,
                stableRecordIdentifier: stableRecordIdentifier(model),
                fieldName: fieldName,
                previousPublicID: previousID,
                repairedPublicID: desiredID
            )
        )
    }

    private func applyRelationshipBackedReferenceUpdates(loaded: LoadedRecords) {
        for session in loaded.fieldCheckSessions {
            if let pasture = session.pasture {
                session.pastureID = pasture.publicID
            }
        }
        for check in loaded.fieldCheckAnimalChecks {
            if let animal = check.animal {
                check.animalIDSnapshot = animal.publicID
            }
        }
        for finding in loaded.fieldCheckFindings {
            if let animal = finding.animal {
                finding.animalIDSnapshot = animal.publicID
            }
            if let session = finding.session {
                finding.sessionIDSnapshot = session.publicID
            }
        }
    }

    private func synchronizeRevisionRecords(loaded: LoadedRecords) throws {
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

    private func preferredRevisionRecord(
        _ lhs: CollaborationRevisionRecord,
        _ rhs: CollaborationRevisionRecord
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return stableRecordIdentifier(lhs) < stableRecordIdentifier(rhs)
    }

    private func registerCurrentRevisionMetadata(
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

    private func validationIssues(
        loaded: LoadedRecords,
        replacements: [PlannedReplacement]
    ) throws -> [String] {
        var issues: [String] = []
        appendDuplicateValidationIssues(loaded.herds, entityType: .herd, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.tagColorDefinitions, entityType: .tagColorDefinition, publicID: { $0.id }, to: &issues)
        appendDuplicateValidationIssues(loaded.animalStatusReferences, entityType: .animalStatusReference, publicID: { $0.id }, to: &issues)
        appendDuplicateValidationIssues(loaded.pastureGroups, entityType: .pastureGroup, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.pastures, entityType: .pasture, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.animals, entityType: .animal, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.animalTags, entityType: .animalTag, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.movements, entityType: .movement, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.statusRecords, entityType: .statusRecord, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingProtocolTemplates, entityType: .workingProtocolTemplate, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingSessions, entityType: .workingSession, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingQueueItems, entityType: .workingQueueItem, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.workingTreatmentRecords, entityType: .workingTreatmentRecord, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.healthRecords, entityType: .healthRecord, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.pregnancyChecks, entityType: .pregnancyCheck, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.fieldCheckSessions, entityType: .fieldCheckSession, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.fieldCheckAnimalChecks, entityType: .fieldCheckAnimalCheck, publicID: { $0.publicID }, to: &issues)
        appendDuplicateValidationIssues(loaded.fieldCheckFindings, entityType: .fieldCheckFinding, publicID: { $0.publicID }, to: &issues)

        for replacement in replacements where replacement.readPublicID() != replacement.report.replacementPublicID {
            issues.append("\(replacement.report.entityType.displayName) replacement did not retain its assigned public ID.")
        }

        for session in loaded.fieldCheckSessions {
            if let pasture = session.pasture, session.pastureID != pasture.publicID {
                issues.append("A field-check pasture reference still points to an obsolete public ID.")
            }
        }
        for check in loaded.fieldCheckAnimalChecks {
            if let animal = check.animal, check.animalIDSnapshot != animal.publicID {
                issues.append("A field-check animal reference still points to an obsolete public ID.")
            }
        }
        for finding in loaded.fieldCheckFindings {
            if let animal = finding.animal, finding.animalIDSnapshot != animal.publicID {
                issues.append("A field-check finding animal reference still points to an obsolete public ID.")
            }
            if let session = finding.session, finding.sessionIDSnapshot != session.publicID {
                issues.append("A field-check finding session reference still points to an obsolete public ID.")
            }
        }

        let revisionRecords = try fetchAll(CollaborationRevisionRecord.self)
        let groupedRevisionRecords = Dictionary(grouping: revisionRecords, by: \.key)
        for aggregate in loaded.allAggregates {
            let key = aggregate.collaborationKey
            let matching = groupedRevisionRecords[key] ?? []
            if matching.count != 1 {
                issues.append("Revision metadata count for \(key.storageKey) is \(matching.count), expected 1.")
                continue
            }
            guard let record = matching.first else { continue }
            if record.herdPublicID != aggregate.collaborationHerdPublicID {
                issues.append("Revision metadata herd scope is stale for \(key.storageKey).")
            }
            if record.metadata.currentFieldValues != CollaborationFieldSnapshotProvider.snapshot(for: aggregate) {
                issues.append("Revision metadata fields are stale for \(key.storageKey).")
            }
        }

        return issues
    }

    private func appendDuplicateValidationIssues<Model>(
        _ records: [Model],
        entityType: PublicIDRepairEntityType,
        publicID: (Model) -> UUID,
        to issues: inout [String]
    ) {
        let duplicates = Dictionary(grouping: records, by: publicID).filter { $0.value.count > 1 }
        if !duplicates.isEmpty {
            issues.append("\(entityType.displayName) still contain \(duplicates.count) duplicate public-ID groups.")
        }
    }

    private func createBackup(
        loaded: LoadedRecords,
        plan: RepairPlan,
        referenceUpdates: [PublicIDRepairReferenceUpdate]
    ) throws -> URL {
        let backup = PublicIDRepairBackup(
            formatVersion: 1,
            createdAt: .now,
            assessment: plan.assessment,
            replacements: plan.reportReplacements,
            referenceUpdates: referenceUpdates,
            aggregates: loaded.allAggregates
                .map(makeBackupAggregate)
                .sorted {
                    if $0.entityType != $1.entityType {
                        return $0.entityType.rawValue < $1.entityType.rawValue
                    }
                    return $0.stableRecordIdentifier < $1.stableRecordIdentifier
                },
            revisionRecords: loaded.revisionRecords
                .map(makeBackupRevisionRecord)
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

    private func backupDirectoryURL() throws -> URL {
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

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: .now)
    }

    private func makeBackupAggregate(
        _ aggregate: any CollaborativelyMutableAggregate
    ) -> BackupAggregate {
        BackupAggregate(
            entityType: publicIDRepairEntityType(for: aggregate),
            stableRecordIdentifier: stableRecordIdentifier(aggregate),
            recordDescription: recordDescription(for: aggregate),
            publicID: aggregate.collaborationKey.publicID,
            herdPublicID: aggregate.collaborationHerdPublicID,
            sharedFields: CollaborationFieldSnapshotProvider.snapshot(for: aggregate)
        )
    }

    private func makeBackupRevisionRecord(
        _ record: CollaborationRevisionRecord
    ) -> BackupRevisionRecord {
        BackupRevisionRecord(
            stableRecordIdentifier: stableRecordIdentifier(record),
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

    private func stableRecordIdentifier<Model: PersistentModel>(_ model: Model) -> String {
        String(describing: model.persistentModelID)
    }

    private func stableRecordIdentifier(
        _ aggregate: any CollaborativelyMutableAggregate
    ) -> String {
        guard let model = aggregate as? any PersistentModel else {
            return aggregate.collaborationKey.storageKey
        }
        return String(describing: model.persistentModelID)
    }

    private func stableSnapshotKey(_ snapshot: CollaborationFieldSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            return String(describing: snapshot)
        }
        return String(data: data, encoding: .utf8) ?? String(describing: snapshot)
    }

    private func publicIDRepairEntityType(
        for aggregate: any CollaborativelyMutableAggregate
    ) -> PublicIDRepairEntityType {
        switch aggregate {
        case is Herd: .herd
        case is TagColorDefinition: .tagColorDefinition
        case is AnimalStatusReference: .animalStatusReference
        case is PastureGroup: .pastureGroup
        case is Pasture: .pasture
        case is Animal: .animal
        case is AnimalTag: .animalTag
        case is MovementRecord: .movement
        case is StatusRecord: .statusRecord
        case is WorkingProtocolTemplate: .workingProtocolTemplate
        case is WorkingSession: .workingSession
        case is WorkingQueueItem: .workingQueueItem
        case is WorkingTreatmentRecord: .workingTreatmentRecord
        case is HealthRecord: .healthRecord
        case is PregnancyCheck: .pregnancyCheck
        case is FieldCheckSession: .fieldCheckSession
        case is FieldCheckAnimalCheck: .fieldCheckAnimalCheck
        case is FieldCheckFinding: .fieldCheckFinding
        default: preconditionFailure("Unsupported collaborative aggregate: \(type(of: aggregate))")
        }
    }

    private func recordDescription(
        for aggregate: any CollaborativelyMutableAggregate
    ) -> String {
        switch aggregate {
        case let herd as Herd:
            return herd.name.isEmpty ? "Unnamed herd" : herd.name
        case let definition as TagColorDefinition:
            return definition.name.isEmpty ? "Unnamed tag color" : definition.name
        case let reference as AnimalStatusReference:
            return reference.name.isEmpty ? "Unnamed status" : reference.name
        case let group as PastureGroup:
            return group.name.isEmpty ? "Unnamed pasture group" : group.name
        case let pasture as Pasture:
            return pasture.name.isEmpty ? "Unnamed pasture" : pasture.name
        case let animal as Animal:
            return animalDescription(animal)
        case let tag as AnimalTag:
            return tag.normalizedNumber.isEmpty ? "Untagged animal tag" : "Tag \(tag.normalizedNumber)"
        case let movement as MovementRecord:
            return "Movement on \(movement.date.formatted(date: .abbreviated, time: .omitted))"
        case let status as StatusRecord:
            return "Status change on \(status.date.formatted(date: .abbreviated, time: .omitted))"
        case let template as WorkingProtocolTemplate:
            return template.name.isEmpty ? "Unnamed working protocol" : template.name
        case let session as WorkingSession:
            return "Working session on \(session.date.formatted(date: .abbreviated, time: .omitted))"
        case let item as WorkingQueueItem:
            return "Working item for \(animalDescription(item.animal))"
        case let treatment as WorkingTreatmentRecord:
            return treatment.itemName.isEmpty ? "Unnamed treatment" : treatment.itemName
        case let health as HealthRecord:
            return health.treatment.isEmpty ? "Health record" : health.treatment
        case let check as PregnancyCheck:
            return "Pregnancy check on \(check.date.formatted(date: .abbreviated, time: .omitted))"
        case let session as FieldCheckSession:
            return "Field check for \(session.pastureNameSnapshot.isEmpty ? "unknown pasture" : session.pastureNameSnapshot)"
        case let check as FieldCheckAnimalCheck:
            return "Animal check \(check.displayTagNumber)"
        case let finding as FieldCheckFinding:
            return finding.note.isEmpty ? "Field check finding" : finding.note
        default:
            return aggregate.collaborationKey.storageKey
        }
    }

    private func animalDescription(_ animal: Animal?) -> String {
        guard let animal else { return "unknown animal" }
        let tag = animal.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty { return "animal \(tag)" }
        let name = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "untagged animal" : name
    }
}

private enum PublicIDRepairError: LocalizedError {
    case noDuplicatesFound
    case backupDirectoryUnavailable
    case validationFailed([String])

    var errorDescription: String? {
        switch self {
        case .noDuplicatesFound:
            "No duplicate public IDs were found. No repair or backup was needed."
        case .backupDirectoryUnavailable:
            "The repair backup directory could not be located. No records were changed."
        case .validationFailed(let issues):
            "The repair did not pass validation, so no changes were saved. \(issues.joined(separator: " "))"
        }
    }
}
