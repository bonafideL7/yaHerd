import Foundation

enum PublicIDRepairEntityType: String, CaseIterable, Codable, Sendable {
    case herd
    case tagColorDefinition
    case animalStatusReference
    case pastureGroup
    case pasture
    case animal
    case animalTag
    case movement
    case statusRecord
    case workingProtocolTemplate
    case workingSession
    case workingQueueItem
    case workingTreatmentRecord
    case healthRecord
    case pregnancyCheck
    case fieldCheckSession
    case fieldCheckAnimalCheck
    case fieldCheckFinding

    var displayName: String {
        switch self {
        case .herd: "Herds"
        case .tagColorDefinition: "Tag color definitions"
        case .animalStatusReference: "Animal status references"
        case .pastureGroup: "Pasture groups"
        case .pasture: "Pastures"
        case .animal: "Animals"
        case .animalTag: "Animal tags"
        case .movement: "Movement records"
        case .statusRecord: "Status records"
        case .workingProtocolTemplate: "Working protocol templates"
        case .workingSession: "Working sessions"
        case .workingQueueItem: "Working queue items"
        case .workingTreatmentRecord: "Working treatment records"
        case .healthRecord: "Health records"
        case .pregnancyCheck: "Pregnancy checks"
        case .fieldCheckSession: "Field check sessions"
        case .fieldCheckAnimalCheck: "Field check animal checks"
        case .fieldCheckFinding: "Field check findings"
        }
    }
}

enum PublicIDRepairUnresolvedReferenceKind: String, Codable, Sendable {
    case lookupReference
    case treatmentReference
    case canonicalRecord
    case bridgeRecordOwner
    case preparedHerdRecovery
    case indeterminateLocalRepairRecovery
}

struct PublicIDRepairEntityAssessment: Identifiable, Codable, Equatable, Sendable {
    let entityType: PublicIDRepairEntityType
    let scannedRecordCount: Int
    let duplicateGroupCount: Int
    let duplicateRecordCount: Int

    var id: PublicIDRepairEntityType { entityType }
}

struct PublicIDRepairResolutionCandidate: Identifiable, Codable, Equatable, Sendable {
    let stableRecordIdentifier: String
    let recordDescription: String
    let detail: String
    let resultingPublicID: UUID

    var id: String { stableRecordIdentifier }
}

struct PublicIDRepairUnresolvedReference: Identifiable, Codable, Equatable, Sendable {
    let kind: PublicIDRepairUnresolvedReferenceKind
    let entityType: PublicIDRepairEntityType
    let recordDescription: String
    let stableRecordIdentifier: String
    let fieldName: String
    let referencedPublicID: UUID
    let reason: String
    let candidates: [PublicIDRepairResolutionCandidate]
    /// Exact Herd roots proven to contain the colliding source entity. This is intentionally
    /// narrower than the repair preparation target set, which also contains reference-only roots.
    let bridgeParticipantHerdPublicIDs: [UUID]?

    init(
        kind: PublicIDRepairUnresolvedReferenceKind = .lookupReference,
        entityType: PublicIDRepairEntityType,
        recordDescription: String,
        stableRecordIdentifier: String,
        fieldName: String,
        referencedPublicID: UUID,
        reason: String,
        candidates: [PublicIDRepairResolutionCandidate] = [],
        bridgeParticipantHerdPublicIDs: [UUID]? = nil
    ) {
        self.kind = kind
        self.entityType = entityType
        self.recordDescription = recordDescription
        self.stableRecordIdentifier = stableRecordIdentifier
        self.fieldName = fieldName
        self.referencedPublicID = referencedPublicID
        self.reason = reason
        self.candidates = candidates
        self.bridgeParticipantHerdPublicIDs = bridgeParticipantHerdPublicIDs.map {
            Array(Set($0)).sorted { $0.uuidString < $1.uuidString }
        }
    }

    var id: String {
        "\(kind.rawValue)|\(entityType.rawValue)|\(stableRecordIdentifier)|\(fieldName)|\(referencedPublicID.uuidString)"
    }
}

struct PublicIDRepairReferenceResolution: Identifiable, Codable, Equatable, Sendable {
    let unresolvedReferenceID: String
    let selectedCandidateStableRecordIdentifier: String

    var id: String { unresolvedReferenceID }
}

struct PublicIDRepairAssessment: Codable, Equatable, Sendable {
    let scannedAt: Date
    let entities: [PublicIDRepairEntityAssessment]
    let unresolvedReferences: [PublicIDRepairUnresolvedReference]
    let requiresBridgeConvergence: Bool

    init(
        scannedAt: Date,
        entities: [PublicIDRepairEntityAssessment],
        unresolvedReferences: [PublicIDRepairUnresolvedReference] = [],
        requiresBridgeConvergence: Bool = false
    ) {
        self.scannedAt = scannedAt
        self.entities = entities
        self.unresolvedReferences = unresolvedReferences
        self.requiresBridgeConvergence = requiresBridgeConvergence
    }

    var totalScannedRecordCount: Int {
        entities.reduce(0) { $0 + $1.scannedRecordCount }
    }

    var duplicateGroupCount: Int {
        entities.reduce(0) { $0 + $1.duplicateGroupCount }
    }

    var duplicateRecordCount: Int {
        entities.reduce(0) { $0 + $1.duplicateRecordCount }
    }

    var hasDuplicates: Bool { duplicateRecordCount > 0 }
    var hasRepairWork: Bool { hasDuplicates || requiresBridgeConvergence }
    var hasBlockingIssues: Bool { !unresolvedReferences.isEmpty }
}

struct PublicIDRepairReplacement: Identifiable, Codable, Equatable, Sendable {
    let entityType: PublicIDRepairEntityType
    let recordDescription: String
    let stableRecordIdentifier: String
    let retainedPublicID: UUID
    let replacementPublicID: UUID
    /// Portable ownership/fingerprint fields used by the durable manifest. They are optional for
    /// backward decoding of existing pending repair journals.
    let owningHerdPublicID: UUID?
    let recordFingerprint: String?
    let retainedStableRecordIdentifier: String?
    let retainedOwningHerdPublicID: UUID?
    let retainedRecordFingerprint: String?

    init(
        entityType: PublicIDRepairEntityType,
        recordDescription: String,
        stableRecordIdentifier: String,
        retainedPublicID: UUID,
        replacementPublicID: UUID,
        owningHerdPublicID: UUID? = nil,
        recordFingerprint: String? = nil,
        retainedStableRecordIdentifier: String? = nil,
        retainedOwningHerdPublicID: UUID? = nil,
        retainedRecordFingerprint: String? = nil
    ) {
        self.entityType = entityType
        self.recordDescription = recordDescription
        self.stableRecordIdentifier = stableRecordIdentifier
        self.retainedPublicID = retainedPublicID
        self.replacementPublicID = replacementPublicID
        self.owningHerdPublicID = owningHerdPublicID
        self.recordFingerprint = recordFingerprint
        self.retainedStableRecordIdentifier = retainedStableRecordIdentifier
        self.retainedOwningHerdPublicID = retainedOwningHerdPublicID
        self.retainedRecordFingerprint = retainedRecordFingerprint
    }

    var id: String {
        "\(entityType.rawValue)|\(stableRecordIdentifier)|\(replacementPublicID.uuidString)"
    }
}

struct PublicIDRepairReferenceUpdate: Identifiable, Codable, Equatable, Sendable {
    let entityType: PublicIDRepairEntityType
    let recordDescription: String
    let stableRecordIdentifier: String
    let fieldName: String
    let previousPublicID: UUID?
    let repairedPublicID: UUID
    let owningHerdPublicID: UUID?

    init(
        entityType: PublicIDRepairEntityType,
        recordDescription: String,
        stableRecordIdentifier: String,
        fieldName: String,
        previousPublicID: UUID?,
        repairedPublicID: UUID,
        owningHerdPublicID: UUID? = nil
    ) {
        self.entityType = entityType
        self.recordDescription = recordDescription
        self.stableRecordIdentifier = stableRecordIdentifier
        self.fieldName = fieldName
        self.previousPublicID = previousPublicID
        self.repairedPublicID = repairedPublicID
        self.owningHerdPublicID = owningHerdPublicID
    }

    var id: String {
        "\(entityType.rawValue)|\(stableRecordIdentifier)|\(fieldName)"
    }
}

struct PublicIDRepairBridgeReplacementMapping: Identifiable, Codable, Equatable, Sendable {
    let herdPublicID: UUID
    let replacementPublicID: UUID

    var id: UUID { herdPublicID }
}

/// Backward-compatible collision projection used by pending v3 journals. New repair code treats
/// the report's `manifest` as authoritative; this structure is a manifest projection and decode
/// compatibility carrier, not an independent identity decision store.
struct PublicIDRepairBridgeCollisionResolution: Identifiable, Codable, Equatable, Sendable {
    let entityType: PublicIDRepairEntityType
    let retainedPublicID: UUID
    let selectedHerdPublicID: UUID
    let herdPublicIDs: [UUID]
    let replacementMappings: [PublicIDRepairBridgeReplacementMapping]?

    init(
        entityType: PublicIDRepairEntityType,
        retainedPublicID: UUID,
        selectedHerdPublicID: UUID,
        herdPublicIDs: [UUID],
        replacementMappings: [PublicIDRepairBridgeReplacementMapping]? = nil
    ) {
        self.entityType = entityType
        self.retainedPublicID = retainedPublicID
        self.selectedHerdPublicID = selectedHerdPublicID
        self.herdPublicIDs = Array(Set(herdPublicIDs)).sorted {
            $0.uuidString < $1.uuidString
        }

        let participantIDs = Set(self.herdPublicIDs)
        let providedByHerd = Dictionary(
            uniqueKeysWithValues: (replacementMappings ?? [])
                .filter {
                    participantIDs.contains($0.herdPublicID)
                        && $0.herdPublicID != selectedHerdPublicID
                }
                .map { ($0.herdPublicID, $0.replacementPublicID) }
        )
        let mappings = self.herdPublicIDs.compactMap { herdPublicID
            -> PublicIDRepairBridgeReplacementMapping? in
            guard herdPublicID != selectedHerdPublicID else { return nil }
            let portableIdentity = publicIDRepairManifestCrossHerdRecordIdentity(
                entityType: entityType,
                originalPublicID: retainedPublicID,
                herdPublicID: herdPublicID
            )
            return PublicIDRepairBridgeReplacementMapping(
                herdPublicID: herdPublicID,
                replacementPublicID: providedByHerd[herdPublicID]
                    ?? publicIDRepairDeterministicReplacementID(
                        entityType: entityType,
                        originalPublicID: retainedPublicID,
                        portableRecordIdentity: portableIdentity
                    )
            )
        }
        self.replacementMappings = mappings.isEmpty ? nil : mappings
    }

    var id: String {
        "\(entityType.rawValue)|\(retainedPublicID.uuidString.lowercased())"
    }

    var authoritativeReplacementMappings: [PublicIDRepairBridgeReplacementMapping] {
        if let replacementMappings {
            return replacementMappings.sorted { $0.herdPublicID.uuidString < $1.herdPublicID.uuidString }
        }
        // A nil mapping can only come from a legacy v3 shape. Preserve the identity that version
        // would have used; PublicIDRepairLegacyCollisionMigration normally materializes it during
        // decoding before this compatibility fallback is reached.
        return herdPublicIDs.compactMap { herdPublicID in
            guard herdPublicID != selectedHerdPublicID else { return nil }
            return PublicIDRepairBridgeReplacementMapping(
                herdPublicID: herdPublicID,
                replacementPublicID: publicIDRepairLegacyV3CrossHerdReplacementID(
                    entityType: entityType,
                    originalPublicID: retainedPublicID,
                    herdPublicID: herdPublicID
                )
            )
        }
    }

    func persistedReplacementPublicID(for herdPublicID: UUID) -> UUID? {
        authoritativeReplacementMappings.first { $0.herdPublicID == herdPublicID }?.replacementPublicID
    }
}

enum PublicIDRepairBridgeRecoveryActionKind: String, Codable, Equatable, Sendable {
    /// Legacy pending-journal value from the first missing-Herd recovery implementation. It is
    /// retained only so those journals decode; current recovery never treats it as user intent.
    case recoverMissingPreparedHerd
    /// The user explicitly chose to reconstruct the missing local Herd from the exact journaled
    /// bridge target after its location and fingerprint are verified.
    case restoreMissingPreparedHerd
    /// The user explicitly confirmed that the locally missing Herd was intentionally deleted and
    /// that the exact journaled bridge target should be retired after safety validation.
    case retireIntentionallyDeletedPreparedHerd
}

struct PublicIDRepairBridgeRecoveryAction: Identifiable, Codable, Equatable, Sendable {
    let kind: PublicIDRepairBridgeRecoveryActionKind
    let herdPublicID: UUID

    var id: String {
        "\(kind.rawValue)|\(herdPublicID.uuidString.lowercased())"
    }
}

struct PublicIDRepairBackupReference: Identifiable, Codable, Equatable, Sendable {
    let filename: String
    let path: String

    var id: String { path }
}

struct PublicIDRepairReport: Codable, Equatable, Sendable {
    let completedAt: Date
    let assessment: PublicIDRepairAssessment
    /// Backward-compatible report views reconstructed from `manifest` on every creation/decode.
    let replacements: [PublicIDRepairReplacement]
    let referenceUpdates: [PublicIDRepairReferenceUpdate]
    let backupFilename: String
    let backupPath: String
    let validationIssueCount: Int
    let bridgeCollisionResolutions: [PublicIDRepairBridgeCollisionResolution]?
    let priorBackups: [PublicIDRepairBackupReference]?
    let bridgeRecoveryActions: [PublicIDRepairBridgeRecoveryAction]?
    let manifest: PublicIDRepairManifest

    init(
        completedAt: Date,
        assessment: PublicIDRepairAssessment,
        replacements: [PublicIDRepairReplacement],
        referenceUpdates: [PublicIDRepairReferenceUpdate],
        backupFilename: String,
        backupPath: String,
        validationIssueCount: Int,
        bridgeCollisionResolutions: [PublicIDRepairBridgeCollisionResolution]? = nil,
        priorBackups: [PublicIDRepairBackupReference]? = nil,
        bridgeRecoveryActions: [PublicIDRepairBridgeRecoveryAction]? = nil,
        manifest: PublicIDRepairManifest? = nil
    ) {
        self.completedAt = completedAt
        self.assessment = assessment
        self.backupFilename = backupFilename
        self.backupPath = backupPath
        self.validationIssueCount = validationIssueCount
        self.priorBackups = priorBackups

        let durableManifest = manifest ?? PublicIDRepairManifest.migratingLegacy(
            completedAt: completedAt,
            replacements: replacements,
            referenceUpdates: referenceUpdates,
            backupFilename: backupFilename,
            backupPath: backupPath,
            validationPassed: validationIssueCount == 0,
            bridgeCollisionResolutions: bridgeCollisionResolutions,
            priorBackups: priorBackups,
            bridgeRecoveryActions: bridgeRecoveryActions
        )
        self.manifest = durableManifest
        self.replacements = durableManifest.reportReplacements
        self.referenceUpdates = durableManifest.reportReferenceUpdates
        let collisionProjection = durableManifest.reportBridgeCollisionResolutions
        self.bridgeCollisionResolutions = collisionProjection.isEmpty ? nil : collisionProjection
        let recoveryProjection = durableManifest.bridgeRecoveryActions
        self.bridgeRecoveryActions = recoveryProjection.isEmpty ? nil : recoveryProjection
    }

    private enum CodingKeys: String, CodingKey {
        case completedAt
        case assessment
        case replacements
        case referenceUpdates
        case backupFilename
        case backupPath
        case validationIssueCount
        case bridgeCollisionResolutions
        case priorBackups
        case bridgeRecoveryActions
        case manifest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        assessment = try container.decode(PublicIDRepairAssessment.self, forKey: .assessment)
        backupFilename = try container.decode(String.self, forKey: .backupFilename)
        backupPath = try container.decode(String.self, forKey: .backupPath)
        validationIssueCount = try container.decode(Int.self, forKey: .validationIssueCount)
        priorBackups = try container.decodeIfPresent(
            [PublicIDRepairBackupReference].self,
            forKey: .priorBackups
        )

        let legacyReplacements = try container.decodeIfPresent(
            [PublicIDRepairReplacement].self,
            forKey: .replacements
        ) ?? []
        let legacyReferenceUpdates = try container.decodeIfPresent(
            [PublicIDRepairReferenceUpdate].self,
            forKey: .referenceUpdates
        ) ?? []
        let legacyCollisionResolutions = try container.decodeIfPresent(
            [PublicIDRepairBridgeCollisionResolution].self,
            forKey: .bridgeCollisionResolutions
        )
        let legacyRecoveryActions = try container.decodeIfPresent(
            [PublicIDRepairBridgeRecoveryAction].self,
            forKey: .bridgeRecoveryActions
        )

        let durableManifest = try container.decodeIfPresent(
            PublicIDRepairManifest.self,
            forKey: .manifest
        ) ?? PublicIDRepairManifest.migratingLegacy(
            completedAt: completedAt,
            replacements: legacyReplacements,
            referenceUpdates: legacyReferenceUpdates,
            backupFilename: backupFilename,
            backupPath: backupPath,
            validationPassed: validationIssueCount == 0,
            bridgeCollisionResolutions: legacyCollisionResolutions,
            priorBackups: priorBackups,
            bridgeRecoveryActions: legacyRecoveryActions
        )
        manifest = durableManifest
        replacements = durableManifest.reportReplacements
        referenceUpdates = durableManifest.reportReferenceUpdates
        let collisionProjection = durableManifest.reportBridgeCollisionResolutions
        bridgeCollisionResolutions = collisionProjection.isEmpty ? nil : collisionProjection
        let recoveryProjection = durableManifest.bridgeRecoveryActions
        bridgeRecoveryActions = recoveryProjection.isEmpty ? nil : recoveryProjection
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(assessment, forKey: .assessment)
        try container.encode(replacements, forKey: .replacements)
        try container.encode(referenceUpdates, forKey: .referenceUpdates)
        try container.encode(backupFilename, forKey: .backupFilename)
        try container.encode(backupPath, forKey: .backupPath)
        try container.encode(validationIssueCount, forKey: .validationIssueCount)
        try container.encodeIfPresent(bridgeCollisionResolutions, forKey: .bridgeCollisionResolutions)
        try container.encodeIfPresent(priorBackups, forKey: .priorBackups)
        try container.encodeIfPresent(bridgeRecoveryActions, forKey: .bridgeRecoveryActions)
        try container.encode(manifest, forKey: .manifest)
    }

    var repairedRecordCount: Int {
        manifest.recordMappings.filter {
            $0.origin == .localSwiftData && !$0.retainedOriginalID
        }.count
    }

    var updatedReferenceCount: Int {
        manifest.referenceTransformations.filter {
            $0.origin == .localSwiftData && $0.sourceEntityType != nil
        }.count
    }

    var bridgeReassignedRecordCount: Int {
        manifest.recordMappings.filter {
            ($0.origin == .bridgeCollision || $0.origin == .bridgeOnly)
                && !$0.retainedOriginalID
        }.count
    }

    var bridgeReferenceTransformationCount: Int {
        manifest.referenceTransformations.filter {
            $0.origin == .bridgeCollision || $0.origin == .bridgeOnly
        }.count
    }

    var validationPassed: Bool {
        validationIssueCount == 0 && manifest.contradictions.isEmpty
    }

    var backupReferences: [PublicIDRepairBackupReference] {
        var byPath: [String: PublicIDRepairBackupReference] = [:]
        for generation in manifest.generations {
            if let backup = generation.backup {
                byPath[backup.path] = backup
            }
        }
        for backup in priorBackups ?? [] {
            byPath[backup.path] = backup
        }
        byPath[backupPath] = PublicIDRepairBackupReference(
            filename: backupFilename,
            path: backupPath
        )
        let current = byPath.removeValue(forKey: backupPath)
        return byPath.values.sorted { $0.path < $1.path } + [current].compactMap { $0 }
    }

    var userReadableSummary: String {
        var lines = [
            "Duplicate public-ID repair completed.",
            "Local records reassigned: \(repairedRecordCount.formatted())",
            "Local stored references updated: \(updatedReferenceCount.formatted())",
            "Shared records reassigned: \(bridgeReassignedRecordCount.formatted())",
            "Shared references or deletion targets updated: \(bridgeReferenceTransformationCount.formatted())",
            "Repair generations: \(manifest.generations.count.formatted())",
            "Validation: \(validationPassed ? "Passed" : "Failed")",
            "Backup: \(backupFilename)",
        ]
        if backupReferences.count > 1 {
            lines.append("Repair backups retained: \(backupReferences.count.formatted())")
        }

        let localReplacements = replacements.filter { replacement in
            manifest.recordMappings.contains {
                $0.origin == .localSwiftData
                    && !$0.retainedOriginalID
                    && $0.portableRecordIdentity == replacement.stableRecordIdentifier
                    && $0.finalPublicID == replacement.replacementPublicID
            }
        }
        let repairedEntities = Dictionary(grouping: localReplacements, by: \.entityType)
        for entityType in PublicIDRepairEntityType.allCases {
            guard let entityReplacements = repairedEntities[entityType], !entityReplacements.isEmpty else {
                continue
            }
            lines.append("\(entityType.displayName): \(entityReplacements.count.formatted()) local records reassigned")
        }

        let collisionMappings = manifest.recordMappings
            .filter { $0.origin == .bridgeCollision }
            .sorted { $0.id < $1.id }
        if !collisionMappings.isEmpty {
            lines.append("Shared identity decisions:")
            for mapping in collisionMappings {
                let action = mapping.retainedOriginalID
                    ? "kept its existing ID"
                    : "changed to \(mapping.finalPublicID.uuidString)"
                let owner = mapping.owningHerdPublicID?.uuidString ?? "unknown Herd"
                lines.append(
                    "\(mapping.entityType.displayName) \(mapping.originalPublicID.uuidString) in Herd \(owner): \(action)."
                )
            }
        }

        let userSelectedBridgeReferences = manifest.referenceTransformations.filter {
            $0.origin == .bridgeOnly
        }
        if !userSelectedBridgeReferences.isEmpty {
            lines.append(
                "Shared reference choices recorded: \(userSelectedBridgeReferences.count.formatted())"
            )
        }

        if !manifest.bridgeRecoveryActions.isEmpty {
            lines.append(
                "Shared-data recovery decisions: \(manifest.bridgeRecoveryActions.count.formatted())"
            )
        }

        if !manifest.contradictions.isEmpty {
            lines.append("Validation found contradictory repair mappings; changes remain blocked.")
        }
        return lines.joined(separator: "\n")
    }
}

enum PublicIDRepairCommitState: Equatable, Sendable {
    case committed
    case notCommitted
    case indeterminate
}

/// Main-actor façade consumed by diagnostics/UI orchestration.
@MainActor
protocol PublicIDRepairService: AnyObject, Sendable {
    func scan() async throws -> PublicIDRepairAssessment
    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport
}

typealias PublicIDRepairWillCommit = @MainActor @Sendable (PublicIDRepairReport) async throws -> Void

/// Sendable persistence worker. Its persistence details stay behind this domain abstraction,
/// and it crosses to the main actor only at the durable pre-commit callback boundary.
protocol PublicIDRepairTransactionalService: Sendable {
    func scan() async throws -> PublicIDRepairAssessment
    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport
    func commitState(for report: PublicIDRepairReport) async throws -> PublicIDRepairCommitState
}

extension PublicIDRepairTransactionalService {
    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport {
        try await repair(resolutions: resolutions, willCommit: { _ in })
    }

    func repair() async throws -> PublicIDRepairReport {
        try await repair(resolutions: [])
    }

    func commitState(for report: PublicIDRepairReport) async throws -> PublicIDRepairCommitState {
        .indeterminate
    }
}

extension PublicIDRepairService {
    func repair() async throws -> PublicIDRepairReport {
        try await repair(resolutions: [])
    }
}
