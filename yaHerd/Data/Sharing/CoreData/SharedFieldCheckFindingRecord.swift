//
//  SharedFieldCheckFindingRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedFieldCheckFindingRecord)
final class SharedFieldCheckFindingRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var sessionPublicID: String?
    @NSManaged var animalPublicID: String?
    @NSManaged var recordedAt: Date?
    @NSManaged var typeRawValue: String?
    @NSManaged var severityRawValue: String?
    @NSManaged var statusRawValue: String?
    @NSManaged var note: String?
    @NSManaged var animalIDSnapshot: String?
    @NSManaged var animalDisplayTagNumberSnapshot: String?
    @NSManaged var animalDisplayTagColorIDSnapshot: String?
    @NSManaged var animalNameSnapshot: String?
    @NSManaged var pastureNameSnapshot: String?
    @NSManaged var sessionIDSnapshot: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var session: SharedFieldCheckSessionRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedFieldCheckFindingRecord {
    static let entityName = "SharedFieldCheckFindingRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedFieldCheckFindingRecord> {
        NSFetchRequest<SharedFieldCheckFindingRecord>(entityName: entityName)
    }

    func mirror(_ finding: FieldCheckFinding, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = finding.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        sessionPublicID = finding.session?.publicID.uuidString
        animalPublicID = finding.animal?.publicID.uuidString
        recordedAt = finding.recordedAt
        typeRawValue = finding.type.rawValue
        severityRawValue = finding.severity.rawValue
        statusRawValue = finding.status.rawValue
        note = finding.note
        animalIDSnapshot = finding.animalIDSnapshot?.uuidString
        animalDisplayTagNumberSnapshot = finding.animalDisplayTagNumberSnapshot
        animalDisplayTagColorIDSnapshot = finding.animalDisplayTagColorIDSnapshot?.uuidString
        animalNameSnapshot = finding.animalNameSnapshot
        pastureNameSnapshot = finding.pastureNameSnapshot
        sessionIDSnapshot = finding.sessionIDSnapshot?.uuidString
        lastMirroredAt = mirroredAt
    }
}

extension SharedFieldCheckFindingRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedSessionPublicID: UUID? {
        guard let sessionPublicID else { return nil }
        return UUID(uuidString: sessionPublicID)
    }

    var parsedAnimalPublicID: UUID? {
        guard let animalPublicID else { return nil }
        return UUID(uuidString: animalPublicID)
    }

    var parsedAnimalIDSnapshot: UUID? {
        guard let animalIDSnapshot else { return nil }
        return UUID(uuidString: animalIDSnapshot)
    }

    var parsedAnimalDisplayTagColorIDSnapshot: UUID? {
        guard let animalDisplayTagColorIDSnapshot else { return nil }
        return UUID(uuidString: animalDisplayTagColorIDSnapshot)
    }

    var parsedSessionIDSnapshot: UUID? {
        guard let sessionIDSnapshot else { return nil }
        return UUID(uuidString: sessionIDSnapshot)
    }

    var parsedType: FieldCheckFindingType {
        guard let typeRawValue else { return .generalObservation }
        return FieldCheckFindingType(rawValue: typeRawValue) ?? .generalObservation
    }

    var parsedSeverity: FieldCheckFindingSeverity {
        guard let severityRawValue else { return .warning }
        return FieldCheckFindingSeverity(rawValue: severityRawValue) ?? .warning
    }

    var parsedStatus: FieldCheckFindingStatus {
        guard let statusRawValue else { return .open }
        return FieldCheckFindingStatus(rawValue: statusRawValue) ?? .open
    }
}
