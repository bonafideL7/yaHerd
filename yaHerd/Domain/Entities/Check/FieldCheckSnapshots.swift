import Foundation

struct FieldCheckSessionStartInput: Hashable {
    let pastureID: UUID
    let startedAt: Date
    let notes: String
}

struct FieldCheckAnimalCheckSnapshot: Identifiable, Hashable {
    let id: UUID
    let animalID: UUID?
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let damDisplayTagNumber: String?
    let damDisplayTagColorID: UUID?
    let animalName: String
    let animalSex: Sex
    let animalType: AnimalType
    let wasExpectedAtStart: Bool
    let wasCounted: Bool
    let needsAttention: Bool
    let isMissing: Bool
}

struct FieldCheckFindingSnapshot: Identifiable, Hashable {
    let id: UUID
    let recordedAt: Date
    let type: FieldCheckFindingType
    let severity: FieldCheckFindingSeverity
    let status: FieldCheckFindingStatus
    let note: String
    let animalID: UUID?
    let animalDisplayTagNumber: String?
    let animalDisplayTagColorID: UUID?
    let pastureName: String?
    let sessionID: UUID
}

struct FieldCheckSessionSummary: Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let pastureID: UUID?
    let pastureName: String?
    let expectedHeadCountSnapshot: Int
    let quickCowCount: Int
    let quickHeiferCount: Int
    let quickCalfCount: Int
    let quickBullCount: Int
    let quickSteerCount: Int
    let animalChecks: [FieldCheckAnimalCheckSnapshot]
    let openFindingsCount: Int

    var displayTitle: String {
        let trimmedPastureName = pastureName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedPastureName.isEmpty ? "Pasture Check" : trimmedPastureName
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var individuallyVerifiedCount: Int {
        animalChecks.filter(\.wasCounted).count
    }

    var totalSeen: Int {
        individuallyVerifiedCount + quickAnimalTypeCounts.values.reduce(0, +)
    }

    var flaggedAnimalCount: Int {
        animalChecks.filter(\.needsAttention).count
    }

    var missingAnimalCount: Int {
        animalChecks.filter(\.isMissing).count
    }

    var remainingExpectedCount: Int {
        max(expectedHeadCountSnapshot - totalSeen, 0)
    }

    var quickAnimalTypeCounts: [AnimalType: Int] {
        [
            .cow: max(quickCowCount, 0),
            .heifer: max(quickHeiferCount, 0),
            .calf: max(quickCalfCount, 0),
            .bull: max(quickBullCount, 0),
            .steer: max(quickSteerCount, 0)
        ]
    }
}

struct FieldCheckSessionDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let notes: String
    let pastureID: UUID?
    let pastureName: String?
    let expectedHeadCountSnapshot: Int
    let quickCowCount: Int
    let quickHeiferCount: Int
    let quickCalfCount: Int
    let quickBullCount: Int
    let quickSteerCount: Int
    let animalChecks: [FieldCheckAnimalCheckSnapshot]
    let findings: [FieldCheckFindingSnapshot]

    var displayTitle: String {
        let trimmedPastureName = pastureName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedPastureName.isEmpty ? "Pasture Check" : trimmedPastureName
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var individuallyVerifiedCount: Int {
        animalChecks.filter(\.wasCounted).count
    }

    var totalSeen: Int {
        individuallyVerifiedCount + quickAnimalTypeCounts.values.reduce(0, +)
    }

    var flaggedAnimalCount: Int {
        animalChecks.filter(\.needsAttention).count
    }

    var missingAnimalCount: Int {
        animalChecks.filter(\.isMissing).count
    }

    var remainingExpectedCount: Int {
        max(expectedHeadCountSnapshot - totalSeen, 0)
    }

    var quickAnimalTypeCounts: [AnimalType: Int] {
        [
            .cow: max(quickCowCount, 0),
            .heifer: max(quickHeiferCount, 0),
            .calf: max(quickCalfCount, 0),
            .bull: max(quickBullCount, 0),
            .steer: max(quickSteerCount, 0)
        ]
    }

    var countVariance: Int {
        totalSeen - expectedHeadCountSnapshot
    }

    var openFindingsCount: Int {
        findings.filter { $0.status != .resolved }.count
    }
}

struct FieldCheckFindingInput: Hashable {
    let recordedAt: Date
    let type: FieldCheckFindingType
    let severity: FieldCheckFindingSeverity
    let status: FieldCheckFindingStatus
    let note: String
    let animalID: UUID?
}
