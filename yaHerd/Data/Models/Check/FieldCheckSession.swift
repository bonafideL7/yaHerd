import Foundation
import SwiftData

@Model
final class FieldCheckSession {
    var publicID: UUID = UUID()
    var startedAt: Date = Date.now
    var completedAt: Date?
    var notes: String = ""
    var expectedHeadCountSnapshot: Int = 0
    var quickCowCount: Int = 0
    var quickHeiferCount: Int = 0
    var quickCalfCount: Int = 0
    var quickBullCount: Int = 0
    var quickSteerCount: Int = 0

    @Relationship(deleteRule: .nullify)
    var pasture: Pasture?
    var pastureID: UUID?
    
    @Relationship(deleteRule: .cascade, inverse: \FieldCheckAnimalCheck.session)
    var animalCheckStorage: [FieldCheckAnimalCheck]?

    @Relationship(deleteRule: .cascade, inverse: \FieldCheckFinding.session)
    var findingStorage: [FieldCheckFinding]?

    var animalChecks: [FieldCheckAnimalCheck] {
        get { animalCheckStorage ?? [] }
        set { animalCheckStorage = newValue }
    }

    var findings: [FieldCheckFinding] {
        get { findingStorage ?? [] }
        set { findingStorage = newValue }
    }

    init(
        publicID: UUID = UUID(),
        startedAt: Date = Date.now,
        completedAt: Date? = nil,
        notes: String = "",
        expectedHeadCountSnapshot: Int = 0,
        quickCowCount: Int = 0,
        quickHeiferCount: Int = 0,
        quickCalfCount: Int = 0,
        quickBullCount: Int = 0,
        quickSteerCount: Int = 0,
        pastureID: UUID? = nil,
        pasture: Pasture? = nil
    ) {
        self.publicID = publicID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.expectedHeadCountSnapshot = expectedHeadCountSnapshot
        self.quickCowCount = quickCowCount
        self.quickHeiferCount = quickHeiferCount
        self.quickCalfCount = quickCalfCount
        self.quickBullCount = quickBullCount
        self.quickSteerCount = quickSteerCount
        self.pastureID = pastureID
        self.pasture = pasture
    }

}

@Model
final class FieldCheckAnimalCheck {
    var publicID: UUID = UUID()
    var rosterTagNumber: String = ""
    var rosterTagColorID: UUID?
    var animalName: String = ""
    var animalSexRawValue: String = Sex.unknown.rawValue
    var wasExpectedAtStart: Bool = true
    var countedAt: Date?
    var missingConfirmedAt: Date?
    var needsAttention: Bool = false
    var note: String = ""

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    @Relationship(deleteRule: .nullify)
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
    var publicID: UUID = UUID()
    var recordedAt: Date = Date.now
    var typeRawValue: String = FieldCheckFindingType.generalObservation.rawValue
    var severityRawValue: String = FieldCheckFindingSeverity.warning.rawValue
    var statusRawValue: String = FieldCheckFindingStatus.open.rawValue
    var note: String = ""

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    @Relationship(deleteRule: .nullify)
    var session: FieldCheckSession?

    init(
        publicID: UUID = UUID(),
        recordedAt: Date = Date.now,
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
