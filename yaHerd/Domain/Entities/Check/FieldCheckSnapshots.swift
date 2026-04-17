import Foundation

struct FieldCheckSessionStartInput: Hashable {
    let pastureID: UUID
    let title: String
    let startedAt: Date
    let notes: String
    let countMode: FieldCheckCountMode
}

struct FieldCheckAnimalCheckSnapshot: Identifiable, Hashable {
    let id: UUID
    let animalID: UUID?
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let animalName: String
    let animalSex: Sex
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
    let pastureName: String?
    let sessionID: UUID
    let sessionTitle: String
}

struct FieldCheckNewbornSnapshot: Identifiable, Hashable {
    let id: UUID
    let recordedAt: Date
    let sex: Sex?
    let isTagged: Bool
    let tagNumber: String
    let notes: String
    let damID: UUID?
    let damDisplayTagNumber: String?
    let convertedAnimalID: UUID?
}

struct FieldCheckSessionSummary: Identifiable, Hashable {
    let id: UUID
    let title: String
    let startedAt: Date
    let completedAt: Date?
    let pastureID: UUID?
    let pastureName: String?
    let countMode: FieldCheckCountMode
    let expectedHeadCountSnapshot: Int
    let quickTaggedCount: Int
    let quickUntaggedCount: Int
    let animalChecks: [FieldCheckAnimalCheckSnapshot]
    let openFindingsCount: Int

    var isCompleted: Bool {
        completedAt != nil
    }

    var individuallyVerifiedCount: Int {
        animalChecks.filter(\.wasCounted).count
    }

    var totalSeen: Int {
        switch countMode {
        case .individual:
            return individuallyVerifiedCount + max(quickUntaggedCount, 0)
        case .quick:
            return max(quickTaggedCount, 0) + max(quickUntaggedCount, 0)
        case .mixed:
            return individuallyVerifiedCount + max(quickTaggedCount, 0) + max(quickUntaggedCount, 0)
        case .observationOnly:
            return 0
        }
    }
}

struct FieldCheckSessionDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let title: String
    let startedAt: Date
    let completedAt: Date?
    let notes: String
    let countMode: FieldCheckCountMode
    let pastureID: UUID?
    let pastureName: String?
    let expectedHeadCountSnapshot: Int
    let quickTaggedCount: Int
    let quickUntaggedCount: Int
    let animalChecks: [FieldCheckAnimalCheckSnapshot]
    let findings: [FieldCheckFindingSnapshot]
    let newborns: [FieldCheckNewbornSnapshot]

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        if let pastureName, !pastureName.isEmpty {
            return pastureName
        }
        return "Pasture Check"
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var individuallyVerifiedCount: Int {
        animalChecks.filter(\.wasCounted).count
    }

    var totalSeen: Int {
        switch countMode {
        case .individual:
            return individuallyVerifiedCount + max(quickUntaggedCount, 0)
        case .quick:
            return max(quickTaggedCount, 0) + max(quickUntaggedCount, 0)
        case .mixed:
            return individuallyVerifiedCount + max(quickTaggedCount, 0) + max(quickUntaggedCount, 0)
        case .observationOnly:
            return 0
        }
    }

    var countVariance: Int {
        totalSeen - expectedHeadCountSnapshot
    }

    var remainingExpectedCount: Int {
        max(expectedHeadCountSnapshot - totalSeen, 0)
    }

    var openFindingsCount: Int {
        findings.filter { $0.status != .resolved }.count
    }

    var missingAnimalCount: Int {
        animalChecks.filter(\.isMissing).count
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

struct FieldCheckNewbornInput: Hashable {
    let recordedAt: Date
    let sex: Sex?
    let isTagged: Bool
    let tagNumber: String
    let notes: String
    let damID: UUID?
}
