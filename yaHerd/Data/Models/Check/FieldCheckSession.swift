import Foundation
import SwiftData

@Model
final class FieldCheckSession {
    @Attribute(.unique) var publicID: UUID
    var startedAt: Date
    var completedAt: Date?
    var notes: String
    var countModeRawValue: String
    var expectedHeadCountSnapshot: Int
    var quickTaggedCount: Int
    var quickUntaggedCount: Int

    @Relationship(deleteRule: .nullify)
    var pasture: Pasture?

    @Relationship(deleteRule: .cascade)
    var animalChecks: [FieldCheckAnimalCheck] = []

    @Relationship(deleteRule: .cascade)
    var findings: [FieldCheckFinding] = []

    init(
        publicID: UUID = UUID(),
        startedAt: Date = .now,
        completedAt: Date? = nil,
        notes: String = "",
        countMode: FieldCheckCountMode = .individual,
        expectedHeadCountSnapshot: Int = 0,
        quickTaggedCount: Int = 0,
        quickUntaggedCount: Int = 0,
        pasture: Pasture? = nil
    ) {
        self.publicID = publicID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.countModeRawValue = countMode.rawValue
        self.expectedHeadCountSnapshot = expectedHeadCountSnapshot
        self.quickTaggedCount = quickTaggedCount
        self.quickUntaggedCount = quickUntaggedCount
        self.pasture = pasture
    }

    var countMode: FieldCheckCountMode {
        get { FieldCheckCountMode(rawValue: countModeRawValue) ?? .individual }
        set { countModeRawValue = newValue.rawValue }
    }
}

@Model
final class FieldCheckAnimalCheck {
    @Attribute(.unique) var publicID: UUID
    var rosterTagNumber: String
    var rosterTagColorID: UUID?
    var animalName: String
    var animalSexRawValue: String
    var wasExpectedAtStart: Bool
    var countedAt: Date?
    var missingConfirmedAt: Date?
    var needsAttention: Bool
    var note: String

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    @Relationship(inverse: \FieldCheckSession.animalChecks)
    var session: FieldCheckSession?

    init(
        publicID: UUID = UUID(),
        rosterTagNumber: String,
        rosterTagColorID: UUID? = nil,
        animalName: String = "",
        animalSex: Sex = .unknown,
        wasExpectedAtStart: Bool = true,
        countedAt: Date? = nil,
        missingConfirmedAt: Date? = nil,
        needsAttention: Bool = false,
        note: String = "",
        animal: Animal? = nil,
        session: FieldCheckSession? = nil
    ) {
        self.publicID = publicID
        self.rosterTagNumber = rosterTagNumber
        self.rosterTagColorID = rosterTagColorID
        self.animalName = animalName
        self.animalSexRawValue = animalSex.rawValue
        self.wasExpectedAtStart = wasExpectedAtStart
        self.countedAt = countedAt
        self.missingConfirmedAt = missingConfirmedAt
        self.needsAttention = needsAttention
        self.note = note
        self.animal = animal
        self.session = session
    }

    var animalSex: Sex {
        get { Sex(rawValue: animalSexRawValue) ?? .unknown }
        set { animalSexRawValue = newValue.rawValue }
    }

    var displayTagNumber: String {
        let trimmedAnimalTag = animal?.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedAnimalTag.isEmpty {
            return trimmedAnimalTag
        }

        let trimmedRosterTag = rosterTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRosterTag.isEmpty ? "UT" : trimmedRosterTag
    }

    var wasCounted: Bool {
        countedAt != nil
    }

    var isMissing: Bool {
        missingConfirmedAt != nil
    }
}

@Model
final class FieldCheckFinding {
    @Attribute(.unique) var publicID: UUID
    var recordedAt: Date
    var typeRawValue: String
    var severityRawValue: String
    var statusRawValue: String
    var note: String

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    @Relationship(inverse: \FieldCheckSession.findings)
    var session: FieldCheckSession?

    init(
        publicID: UUID = UUID(),
        recordedAt: Date = .now,
        type: FieldCheckFindingType,
        severity: FieldCheckFindingSeverity,
        status: FieldCheckFindingStatus = .open,
        note: String = "",
        animal: Animal? = nil,
        session: FieldCheckSession? = nil
    ) {
        self.publicID = publicID
        self.recordedAt = recordedAt
        self.typeRawValue = type.rawValue
        self.severityRawValue = severity.rawValue
        self.statusRawValue = status.rawValue
        self.note = note
        self.animal = animal
        self.session = session
    }

    var type: FieldCheckFindingType {
        get { FieldCheckFindingType(rawValue: typeRawValue) ?? .generalObservation }
        set { typeRawValue = newValue.rawValue }
    }

    var severity: FieldCheckFindingSeverity {
        get { FieldCheckFindingSeverity(rawValue: severityRawValue) ?? .warning }
        set { severityRawValue = newValue.rawValue }
    }

    var status: FieldCheckFindingStatus {
        get { FieldCheckFindingStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }
}

enum FieldCheckCountMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case individual
    case quick
    case mixed
    case observationOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .individual:
            return "Individual"
        case .quick:
            return "Quick"
        case .mixed:
            return "Mixed"
        case .observationOnly:
            return "Observation Only"
        }
    }

}

enum FieldCheckFindingType: String, Codable, CaseIterable, Identifiable, Hashable {
    case generalObservation
    case pinkEye
    case limping
    case coughing
    case offFeed
    case injury
    case medicalAttention
    case calvingInProgress
    case missingAnimal
    case fenceIssue
    case waterIssue
    case movedOutOfPlace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .generalObservation: return "Observation"
        case .pinkEye: return "Pink Eye"
        case .limping: return "Limping"
        case .coughing: return "Coughing"
        case .offFeed: return "Off Feed"
        case .injury: return "Injury"
        case .medicalAttention: return "Needs Treatment"
        case .calvingInProgress: return "Calving"
        case .missingAnimal: return "Missing Animal"
        case .fenceIssue: return "Fence Issue"
        case .waterIssue: return "Water Issue"
        case .movedOutOfPlace: return "Wrong Pasture"
        }
    }

    var systemImage: String {
        switch self {
        case .generalObservation: return "note.text"
        case .pinkEye: return "eye"
        case .limping: return "figure.walk.motion"
        case .coughing: return "wind"
        case .offFeed: return "fork.knife"
        case .injury: return "bandage"
        case .medicalAttention: return "cross.case"
        case .calvingInProgress: return "hourglass"
        case .missingAnimal: return "questionmark.circle"
        case .fenceIssue: return "square.dashed"
        case .waterIssue: return "drop"
        case .movedOutOfPlace: return "arrow.left.arrow.right"
        }
    }
}

enum FieldCheckFindingSeverity: String, Codable, CaseIterable, Identifiable, Hashable {
    case info
    case warning
    case critical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Watch"
        case .critical: return "Urgent"
        }
    }
}

enum FieldCheckFindingStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case open
    case monitoring
    case resolved

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Open"
        case .monitoring: return "Monitoring"
        case .resolved: return "Resolved"
        }
    }
}
