import CryptoKit
import Foundation
import SwiftData

@ModelActor
actor DeterministicSwiftDataPublicIDRepairService: PublicIDRepairTransactionalService {
    struct LoadedRecords {
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

    struct AggregateNode {
        let entityType: PublicIDRepairEntityType
        let collaborationType: CollaborationAggregateType
        let aggregate: any CollaborativelyMutableAggregate
        let localIdentifier: String
        let recordDescription: String
        let readPublicID: () -> UUID
        let assignPublicID: (UUID) -> Void
        let snapshotKey: String
    }

    struct DuplicateCandidate {
        let entityType: PublicIDRepairEntityType
        let localIdentifier: String
        let stableRecordIdentifier: String
        let recordDescription: String
        let detail: String
        let retainedPublicID: UUID
        let resultingPublicID: UUID
    }

    struct PlannedReplacement {
        let report: PublicIDRepairReplacement
        let localRecordIdentifier: String
        let readPublicID: () -> UUID
        let assignPublicID: (UUID) -> Void
    }

    struct PlannedReferenceUpdate {
        let report: PublicIDRepairReferenceUpdate
        let readPublicID: () -> UUID?
        let assignPublicID: (UUID) -> Void
    }

    struct EntityPlan {
        let assessment: PublicIDRepairEntityAssessment
        let replacements: [PlannedReplacement]
        let candidates: [DuplicateCandidate]
        let unresolvedIssues: [PublicIDRepairUnresolvedReference]
    }

    struct TreatmentItemLocation {
        let entityType: PublicIDRepairEntityType
        let ownerLocalIdentifier: String
        let ownerPublicID: UUID
        let ownerSnapshotKey: String
        let itemIndex: Int
        let localIdentifier: String
        let originalID: UUID
        let item: WorkingProtocolItem
        let ownerDescription: String
        let session: WorkingSession?
        let readPublicID: () -> UUID
        let assignPublicID: (UUID) -> Void
    }

    struct RepairPlan {
        let assessment: PublicIDRepairAssessment
        let replacements: [PlannedReplacement]
        let candidates: [DuplicateCandidate]
        let unresolvedIssues: [PublicIDRepairUnresolvedReference]
        let graphFingerprintByLocalIdentifier: [String: String]
        let treatmentLocations: [TreatmentItemLocation]

        var reportReplacements: [PublicIDRepairReplacement] {
            replacements.map(\.report)
        }

        var replacementIDByLocalRecordIdentifier: [String: UUID] {
            Dictionary(uniqueKeysWithValues: replacements.map {
                ($0.localRecordIdentifier, $0.report.replacementPublicID)
            })
        }

        var candidateByLocalIdentifier: [String: DuplicateCandidate] {
            Dictionary(uniqueKeysWithValues: candidates.map { ($0.localIdentifier, $0) })
        }

        var candidateByStableIdentifier: [String: DuplicateCandidate] {
            Dictionary(uniqueKeysWithValues: candidates.map { ($0.stableRecordIdentifier, $0) })
        }
    }

    func scan() throws -> PublicIDRepairAssessment {
        let loaded = try loadRecords()
        let plan = makeRepairPlan(loaded: loaded)
        let unresolved = unresolvedReferences(
            loaded: loaded,
            plan: plan,
            resolutions: [:]
        )
        return PublicIDRepairAssessment(
            scannedAt: plan.assessment.scannedAt,
            entities: plan.assessment.entities,
            unresolvedReferences: unresolved
        )
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        let loaded = try loadRecords()
        let plan = makeRepairPlan(loaded: loaded)
        guard plan.assessment.hasDuplicates else {
            throw PublicIDRepairError.noDuplicatesFound
        }

        let resolutionMap = try validatedResolutionMap(resolutions)
        let unresolved = unresolvedReferences(
            loaded: loaded,
            plan: plan,
            resolutions: resolutionMap
        )
        guard unresolved.isEmpty else {
            throw PublicIDRepairError.unresolvedReferences(unresolved)
        }

        let assessment = PublicIDRepairAssessment(
            scannedAt: plan.assessment.scannedAt,
            entities: plan.assessment.entities,
            unresolvedReferences: []
        )
        let referenceUpdates = try plannedReferenceUpdates(
            loaded: loaded,
            plan: plan,
            resolutions: resolutionMap
        )
        let reportReferenceUpdates = referenceUpdates.map(\.report)
        let backupURL = try createBackup(
            loaded: loaded,
            plan: plan,
            assessment: assessment,
            referenceUpdates: reportReferenceUpdates,
            resolutions: resolutions
        )
        let report = PublicIDRepairReport(
            completedAt: .now,
            assessment: assessment,
            replacements: plan.reportReplacements,
            referenceUpdates: reportReferenceUpdates,
            backupFilename: backupURL.lastPathComponent,
            backupPath: backupURL.path,
            validationIssueCount: 0
        )

        // This callback is the durable crash-recovery boundary. No SwiftData mutation has
        // occurred yet, but the complete deterministic transaction and backup are known.
        try await willCommit(report)

        do {
            for replacement in plan.replacements {
                replacement.assignPublicID(replacement.report.replacementPublicID)
            }
            for update in referenceUpdates {
                update.assignPublicID(update.report.repairedPublicID)
            }

            try synchronizeRevisionRecords(loaded: loaded)
            let validationIssues = try validationIssues(
                loaded: loaded,
                replacements: plan.replacements,
                referenceUpdates: referenceUpdates
            )
            guard validationIssues.isEmpty else {
                throw PublicIDRepairError.validationFailed(validationIssues)
            }

            try PersistenceLog.save(
                modelContext,
                operation: "DeterministicSwiftDataPublicIDRepairService.repair"
            )
            registerCurrentRevisionMetadata(loaded.allAggregates)

            ReliabilityLog.persistenceEvent(
                "DeterministicSwiftDataPublicIDRepairService.repair",
                detail: "reassigned=\(plan.replacements.count) references=\(referenceUpdates.count)"
            )

            return report
        } catch {
            modelContext.rollback()
            ReliabilityLog.persistenceFailure(
                "DeterministicSwiftDataPublicIDRepairService.repair",
                error: error
            )
            throw error
        }
    }

    func loadRecords() throws -> LoadedRecords {
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

    func fetchAll<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try modelContext.fetch(FetchDescriptor<Model>())
    }

    func validatedResolutionMap(
        _ resolutions: [PublicIDRepairReferenceResolution]
    ) throws -> [String: String] {
        var map: [String: String] = [:]
        for resolution in resolutions {
            if let existing = map[resolution.unresolvedReferenceID],
               existing != resolution.selectedCandidateStableRecordIdentifier {
                throw PublicIDRepairError.conflictingResolution(resolution.unresolvedReferenceID)
            }
            map[resolution.unresolvedReferenceID] = resolution.selectedCandidateStableRecordIdentifier
        }
        return map
    }

    func localRecordIdentifier<Model: PersistentModel>(_ model: Model) -> String {
        String(describing: model.persistentModelID)
    }

    func localRecordIdentifier(
        _ aggregate: any CollaborativelyMutableAggregate
    ) -> String {
        guard let model = aggregate as? any PersistentModel else {
            return aggregate.collaborationKey.storageKey
        }
        return String(describing: model.persistentModelID)
    }

    func localTreatmentItemIdentifier<Owner: PersistentModel>(
        owner: Owner,
        index: Int
    ) -> String {
        "\(localRecordIdentifier(owner))|treatmentItem|\(index)"
    }

    func deterministicDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func deterministicUUID(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func stableSnapshotKey(_ snapshot: CollaborationFieldSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            return String(describing: snapshot)
        }
        return String(data: data, encoding: .utf8) ?? String(describing: snapshot)
    }

    func normalizedTreatmentName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum PublicIDRepairError: LocalizedError {
    case noDuplicatesFound
    case backupDirectoryUnavailable
    case unresolvedReferences([PublicIDRepairUnresolvedReference])
    case conflictingResolution(String)
    case invalidResolution(String)
    case validationFailed([String])

    var errorDescription: String? {
        switch self {
        case .noDuplicatesFound:
            "No duplicate public IDs were found. No repair or backup was needed."
        case .backupDirectoryUnavailable:
            "The repair backup directory could not be located. No records were changed."
        case .unresolvedReferences(let issues):
            "The repair was not started because \(issues.count) references or duplicate records still require a deliberate choice in Sync Diagnostics."
        case .conflictingResolution(let identifier):
            "More than one choice was supplied for repair issue \(identifier). No records were changed."
        case .invalidResolution(let identifier):
            "The selected repair candidate for issue \(identifier) is no longer valid. Scan again before retrying."
        case .validationFailed(let issues):
            "The repair did not pass validation, so no changes were saved. \(issues.joined(separator: " "))"
        }
    }
}
