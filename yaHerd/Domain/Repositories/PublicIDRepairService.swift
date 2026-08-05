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

struct PublicIDRepairEntityAssessment: Identifiable, Codable, Equatable, Sendable {
    let entityType: PublicIDRepairEntityType
    let scannedRecordCount: Int
    let duplicateGroupCount: Int
    let duplicateRecordCount: Int

    var id: PublicIDRepairEntityType { entityType }
}

struct PublicIDRepairAssessment: Codable, Equatable, Sendable {
    let scannedAt: Date
    let entities: [PublicIDRepairEntityAssessment]

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

protocol PublicIDRepairService: Sendable {
    func scan() async throws -> PublicIDRepairAssessment
    func repair() async throws -> PublicIDRepairReport
}
