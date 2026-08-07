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

    init(
        kind: PublicIDRepairUnresolvedReferenceKind = .lookupReference,
        entityType: PublicIDRepairEntityType,
        recordDescription: String,
        stableRecordIdentifier: String,
        fieldName: String,
        referencedPublicID: UUID,
        reason: String,
        candidates: [PublicIDRepairResolutionCandidate] = []
    ) {
        self.kind = kind
        self.entityType = entityType
        self.recordDescription = recordDescription
        self.stableRecordIdentifier = stableRecordIdentifier
        self.fieldName = fieldName
        self.referencedPublicID = referencedPublicID
        self.reason = reason
        self.candidates = candidates
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

    var id: String {
        "\(entityType.rawValue)|\(stableRecordIdentifier)|\(fieldName)"
    }
}

struct PublicIDRepairReport: Codable, Equatable, Sendable {
    let completedAt: Date
    let assessment: PublicIDRepairAssessment
    let replacements: [PublicIDRepairReplacement]
    let referenceUpdates: [PublicIDRepairReferenceUpdate]
    let backupFilename: String
    let backupPath: String
    let validationIssueCount: Int

    var repairedRecordCount: Int { replacements.count }
    var updatedReferenceCount: Int { referenceUpdates.count }
    var validationPassed: Bool { validationIssueCount == 0 }

    var userReadableSummary: String {
        var lines = [
            "Duplicate public-ID repair completed.",
            "Reassigned records: \(repairedRecordCount.formatted())",
            "Updated stored references: \(updatedReferenceCount.formatted())",
            "Validation: \(validationPassed ? "Passed" : "Failed")",
            "Backup: \(backupFilename)",
        ]

        let repairedEntities = Dictionary(grouping: replacements, by: \.entityType)
        for entityType in PublicIDRepairEntityType.allCases {
            guard let entityReplacements = repairedEntities[entityType], !entityReplacements.isEmpty else {
                continue
            }
            lines.append("\(entityType.displayName): \(entityReplacements.count.formatted()) reassigned")
        }

        return lines.joined(separator: "\n")
    }
}

/// Main-actor façade consumed by diagnostics/UI orchestration.
@MainActor
protocol PublicIDRepairService: AnyObject, Sendable {
    func scan() async throws -> PublicIDRepairAssessment
    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport
}

typealias PublicIDRepairWillCommit = @MainActor @Sendable (PublicIDRepairReport) throws -> Void

/// Sendable persistence worker. Its persistence details stay behind this domain abstraction,
/// and it crosses to the main actor only at the durable pre-commit callback boundary.
protocol PublicIDRepairTransactionalService: Sendable {
    func scan() async throws -> PublicIDRepairAssessment
    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport
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
}

extension PublicIDRepairService {
    func repair() async throws -> PublicIDRepairReport {
        try await repair(resolutions: [])
    }
}
