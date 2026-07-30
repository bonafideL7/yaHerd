import Foundation

struct FieldCheckSessionStartInput: Hashable {
    let pastureID: UUID
    let startedAt: Date
    let notes: String
}

struct FieldCheckAnimalCheckSnapshot: Identifiable, Hashable, Sendable {
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

struct FieldCheckFindingSnapshot: Identifiable, Hashable, Sendable {
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

struct FieldCheckSessionSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let pastureID: UUID?
    let pastureName: String?
    let pastureArchivedAt: Date?
    let isPastureArchived: Bool
    let expectedHeadCountSnapshot: Int
    let quickCowCount: Int
    let quickHeiferCount: Int
    let quickCalfCount: Int
    let quickBullCount: Int
    let quickSteerCount: Int
    let animalChecks: [FieldCheckAnimalCheckSnapshot]
    let openFindingsCount: Int

    init(
        id: UUID,
        startedAt: Date,
        completedAt: Date?,
        pastureID: UUID?,
        pastureName: String?,
        pastureArchivedAt: Date? = nil,
        isPastureArchived: Bool = false,
        expectedHeadCountSnapshot: Int,
        quickCowCount: Int,
        quickHeiferCount: Int,
        quickCalfCount: Int,
        quickBullCount: Int,
        quickSteerCount: Int,
        animalChecks: [FieldCheckAnimalCheckSnapshot],
        openFindingsCount: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.pastureID = pastureID
        self.pastureName = pastureName
        self.pastureArchivedAt = pastureArchivedAt
        self.isPastureArchived = isPastureArchived
        self.expectedHeadCountSnapshot = expectedHeadCountSnapshot
        self.quickCowCount = quickCowCount
        self.quickHeiferCount = quickHeiferCount
        self.quickCalfCount = quickCalfCount
        self.quickBullCount = quickBullCount
        self.quickSteerCount = quickSteerCount
        self.animalChecks = animalChecks
        self.openFindingsCount = openFindingsCount
    }

    var displayTitle: String {
        let trimmedPastureName = pastureName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedPastureName.isEmpty ? "Pasture Check" : trimmedPastureName
    }

    var pastureStatusLabel: String? {
        isPastureArchived ? "Archived pasture" : nil
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var individuallyVerifiedCount: Int {
        FieldCheckQuickCountRules.individuallyVerifiedCount(in: quickCountRosterEntries)
    }

    var totalSeen: Int {
        FieldCheckQuickCountRules.totalSeen(
            quickCounts: storedQuickAnimalTypeCounts,
            rosterEntries: quickCountRosterEntries
        )
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
        FieldCheckQuickCountRules.normalizedCounts(
            storedQuickAnimalTypeCounts,
            rosterEntries: quickCountRosterEntries
        )
    }

    private var storedQuickAnimalTypeCounts: [AnimalType: Int] {
        [
            .cow: max(quickCowCount, 0),
            .heifer: max(quickHeiferCount, 0),
            .calf: max(quickCalfCount, 0),
            .bull: max(quickBullCount, 0),
            .steer: max(quickSteerCount, 0)
        ]
    }

    private var quickCountRosterEntries: [FieldCheckQuickCountRosterEntry] {
        animalChecks.map(\.quickCountRosterEntry)
    }
}

struct FieldCheckSessionDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let notes: String
    let pastureID: UUID?
    let pastureName: String?
    let pastureArchivedAt: Date?
    let isPastureArchived: Bool
    let expectedHeadCountSnapshot: Int
    let quickCowCount: Int
    let quickHeiferCount: Int
    let quickCalfCount: Int
    let quickBullCount: Int
    let quickSteerCount: Int
    let animalChecks: [FieldCheckAnimalCheckSnapshot]
    let findings: [FieldCheckFindingSnapshot]

    init(
        id: UUID,
        startedAt: Date,
        completedAt: Date?,
        notes: String,
        pastureID: UUID?,
        pastureName: String?,
        pastureArchivedAt: Date? = nil,
        isPastureArchived: Bool = false,
        expectedHeadCountSnapshot: Int,
        quickCowCount: Int,
        quickHeiferCount: Int,
        quickCalfCount: Int,
        quickBullCount: Int,
        quickSteerCount: Int,
        animalChecks: [FieldCheckAnimalCheckSnapshot],
        findings: [FieldCheckFindingSnapshot]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.pastureID = pastureID
        self.pastureName = pastureName
        self.pastureArchivedAt = pastureArchivedAt
        self.isPastureArchived = isPastureArchived
        self.expectedHeadCountSnapshot = expectedHeadCountSnapshot
        self.quickCowCount = quickCowCount
        self.quickHeiferCount = quickHeiferCount
        self.quickCalfCount = quickCalfCount
        self.quickBullCount = quickBullCount
        self.quickSteerCount = quickSteerCount
        self.animalChecks = animalChecks
        self.findings = findings
    }

    var displayTitle: String {
        let trimmedPastureName = pastureName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedPastureName.isEmpty ? "Pasture Check" : trimmedPastureName
    }

    var pastureStatusLabel: String? {
        isPastureArchived ? "Archived pasture" : nil
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var individuallyVerifiedCount: Int {
        FieldCheckQuickCountRules.individuallyVerifiedCount(in: quickCountRosterEntries)
    }

    var totalSeen: Int {
        FieldCheckQuickCountRules.totalSeen(
            quickCounts: storedQuickAnimalTypeCounts,
            rosterEntries: quickCountRosterEntries
        )
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
        FieldCheckQuickCountRules.normalizedCounts(
            storedQuickAnimalTypeCounts,
            rosterEntries: quickCountRosterEntries
        )
    }

    private var storedQuickAnimalTypeCounts: [AnimalType: Int] {
        [
            .cow: max(quickCowCount, 0),
            .heifer: max(quickHeiferCount, 0),
            .calf: max(quickCalfCount, 0),
            .bull: max(quickBullCount, 0),
            .steer: max(quickSteerCount, 0)
        ]
    }

    private var quickCountRosterEntries: [FieldCheckQuickCountRosterEntry] {
        animalChecks.map(\.quickCountRosterEntry)
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
