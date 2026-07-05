//
//  SharedFieldCheckAnimalCheckRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedFieldCheckAnimalCheckRecord)
final class SharedFieldCheckAnimalCheckRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var sessionPublicID: String?
    @NSManaged var animalPublicID: String?
    @NSManaged var animalIDSnapshot: String?
    @NSManaged var rosterTagNumber: String?
    @NSManaged var rosterTagColorID: String?
    @NSManaged var damRosterTagNumber: String?
    @NSManaged var damRosterTagColorID: String?
    @NSManaged var animalName: String?
    @NSManaged var animalSexRawValue: String?
    @NSManaged var animalTypeRawValue: String?
    @NSManaged var wasExpectedAtStart: NSNumber?
    @NSManaged var countedAt: Date?
    @NSManaged var missingConfirmedAt: Date?
    @NSManaged var note: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var session: SharedFieldCheckSessionRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedFieldCheckAnimalCheckRecord {
    static let entityName = "SharedFieldCheckAnimalCheckRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedFieldCheckAnimalCheckRecord> {
        NSFetchRequest<SharedFieldCheckAnimalCheckRecord>(entityName: entityName)
    }

    func mirror(_ check: FieldCheckAnimalCheck, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = check.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        sessionPublicID = check.session?.publicID.uuidString
        animalPublicID = check.animal?.publicID.uuidString
        animalIDSnapshot = check.animalIDSnapshot?.uuidString
        rosterTagNumber = check.rosterTagNumber
        rosterTagColorID = check.rosterTagColorID?.uuidString
        damRosterTagNumber = check.damRosterTagNumber
        damRosterTagColorID = check.damRosterTagColorID?.uuidString
        animalName = check.animalName
        animalSexRawValue = check.animalSex.rawValue
        animalTypeRawValue = check.animalTypeSnapshot.rawValue
        wasExpectedAtStart = NSNumber(value: check.wasExpectedAtStart)
        countedAt = check.countedAt
        missingConfirmedAt = check.missingConfirmedAt
        note = check.note
        lastMirroredAt = mirroredAt
    }
}

extension SharedFieldCheckAnimalCheckRecord {
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

    var parsedRosterTagColorID: UUID? {
        guard let rosterTagColorID else { return nil }
        return UUID(uuidString: rosterTagColorID)
    }

    var parsedDamRosterTagColorID: UUID? {
        guard let damRosterTagColorID else { return nil }
        return UUID(uuidString: damRosterTagColorID)
    }

    var parsedAnimalSex: Sex {
        guard let animalSexRawValue else { return .unknown }
        return Sex(rawValue: animalSexRawValue) ?? .unknown
    }

    var parsedAnimalType: AnimalType? {
        guard let animalTypeRawValue else { return nil }
        return AnimalType(rawValue: animalTypeRawValue)
    }
}
