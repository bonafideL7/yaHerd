import Foundation
import SwiftData

enum FieldCheckHistoricalSnapshotMigrator {
    private static let currentMigrationVersion = 1
    private static let migrationVersionKeyPrefix = "FieldCheckHistoricalSnapshotMigrator.completedMigrationVersion"

    static func runIfNeeded(
        in context: ModelContext,
        storageScope: String,
        migrationState: UserDefaults = .standard
    ) throws {
        let migrationVersionKey = "\(migrationVersionKeyPrefix).\(storageScope)"
        guard migrationState.integer(forKey: migrationVersionKey) < currentMigrationVersion else { return }

        var changed = false

        let sessionDescriptor = FetchDescriptor<FieldCheckSession>()
        let sessions = try context.fetch(sessionDescriptor)
        for session in sessions {
            changed = backfillHistoricalSnapshots(in: session) || changed
        }

        let findingDescriptor = FetchDescriptor<FieldCheckFinding>()
        let findings = try context.fetch(findingDescriptor)
        for finding in findings {
            changed = backfillHistoricalSnapshots(in: finding.session) || changed
            changed = backfillHistoricalSnapshots(for: finding) || changed
        }

        if changed || context.hasChanges {
            try context.save()
        }

        migrationState.set(currentMigrationVersion, forKey: migrationVersionKey)
    }

    @discardableResult
    private static func backfillHistoricalSnapshots(in session: FieldCheckSession?) -> Bool {
        guard let session else { return false }
        var didChange = false

        if isBlank(session.pastureNameSnapshot), let pastureName = trimmed(session.pasture?.name) {
            session.pastureNameSnapshot = pastureName
            didChange = true
        }

        for check in session.animalChecks {
            didChange = backfillHistoricalSnapshots(for: check) || didChange
        }

        for finding in session.findings {
            didChange = backfillHistoricalSnapshots(for: finding) || didChange
        }

        return didChange
    }

    @discardableResult
    private static func backfillHistoricalSnapshots(for check: FieldCheckAnimalCheck) -> Bool {
        var didChange = false
        let animal = check.animal

        if check.animalIDSnapshot == nil, let animalID = animal?.publicID {
            check.animalIDSnapshot = animalID
            didChange = true
        }
        if isBlank(check.rosterTagNumber), let displayTagNumber = trimmed(animal?.displayTagNumber) {
            check.rosterTagNumber = displayTagNumber
            didChange = true
        }
        if check.rosterTagColorID == nil, let tagColorID = animal?.displayTagColorID {
            check.rosterTagColorID = tagColorID
            didChange = true
        }
        if isBlank(check.damRosterTagNumber), let damDisplayTagNumber = AnimalDisplayTagFormatter.displayTagNumber(for: animal?.damAnimal) {
            check.damRosterTagNumber = damDisplayTagNumber
            didChange = true
        }
        if check.damRosterTagColorID == nil, let damTagColorID = animal?.damAnimal?.displayTagColorID {
            check.damRosterTagColorID = damTagColorID
            didChange = true
        }
        if isBlank(check.animalName), let animalName = trimmed(animal?.name) {
            check.animalName = animalName
            didChange = true
        }
        if !Sex.allCases.map(\.rawValue).contains(check.animalSexRawValue), let sex = animal?.sex {
            check.animalSex = sex
            didChange = true
        }
        if AnimalType(rawValue: check.animalTypeRawValue) == nil {
            check.animalTypeSnapshot = animal?.animalType ?? fallbackAnimalType(for: check.animalSex)
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private static func backfillHistoricalSnapshots(for finding: FieldCheckFinding) -> Bool {
        var didChange = false
        let session = finding.session
        let existingAnimalID = animalID(for: finding)
        let check = existingAnimalID.flatMap { id in
            session.flatMap { animalCheck(for: id, in: $0) }
        }
        let animal = finding.animal

        if finding.sessionIDSnapshot == nil, let sessionID = session?.publicID {
            finding.sessionIDSnapshot = sessionID
            didChange = true
        }
        if isBlank(finding.pastureNameSnapshot) {
            if let pastureName = trimmed(session?.pastureNameSnapshot) ?? trimmed(session?.pasture?.name) {
                finding.pastureNameSnapshot = pastureName
                didChange = true
            }
        }
        if finding.animalIDSnapshot == nil, let animalID = animal?.publicID {
            finding.animalIDSnapshot = animalID
            didChange = true
        }
        if isBlank(finding.animalDisplayTagNumberSnapshot) {
            if let tagNumber = trimmed(check?.rosterTagNumber) ?? trimmed(animal?.displayTagNumber) {
                finding.animalDisplayTagNumberSnapshot = tagNumber
                didChange = true
            }
        }
        if finding.animalDisplayTagColorIDSnapshot == nil {
            if let tagColorID = check?.rosterTagColorID ?? animal?.displayTagColorID {
                finding.animalDisplayTagColorIDSnapshot = tagColorID
                didChange = true
            }
        }
        if isBlank(finding.animalNameSnapshot) {
            if let animalName = trimmed(check?.animalName) ?? trimmed(animal?.name) {
                finding.animalNameSnapshot = animalName
                didChange = true
            }
        }

        return didChange
    }

    private static func animalCheck(for animalID: UUID, in session: FieldCheckSession) -> FieldCheckAnimalCheck? {
        session.animalChecks.first { check in
            self.animalID(for: check) == animalID
        }
    }

    private static func animalID(for check: FieldCheckAnimalCheck) -> UUID? {
        check.animalIDSnapshot ?? check.animal?.publicID
    }

    private static func animalID(for finding: FieldCheckFinding) -> UUID? {
        finding.animalIDSnapshot ?? finding.animal?.publicID
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func fallbackAnimalType(for sex: Sex) -> AnimalType {
        switch sex {
        case .female:
            return .cow
        case .male:
            return .bull
        case .unknown:
            return .bull
        }
    }
}
