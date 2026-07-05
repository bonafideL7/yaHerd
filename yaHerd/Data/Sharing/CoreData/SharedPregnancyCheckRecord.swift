//
//  SharedPregnancyCheckRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedPregnancyCheckRecord)
final class SharedPregnancyCheckRecord: NSManagedObject {
    @NSManaged var publicID: String?
    @NSManaged var herdPublicID: String?
    @NSManaged var animalPublicID: String?
    @NSManaged var date: Date?
    @NSManaged var resultRawValue: String?
    @NSManaged var technician: String?
    @NSManaged var estimatedDaysPregnant: NSNumber?
    @NSManaged var dueDate: Date?
    @NSManaged var sireAnimalPublicID: String?
    @NSManaged var workingSessionPublicID: String?
    @NSManaged var lastMirroredAt: Date?
    @NSManaged var herd: SharedHerdRecord?
    @NSManaged var animal: SharedAnimalRecord?
}

extension SharedPregnancyCheckRecord {
    static let entityName = "SharedPregnancyCheckRecord"

    @nonobjc
    class func fetchRequest() -> NSFetchRequest<SharedPregnancyCheckRecord> {
        NSFetchRequest<SharedPregnancyCheckRecord>(entityName: entityName)
    }

    func mirror(_ pregnancyCheck: PregnancyCheck, herdPublicID: UUID, mirroredAt: Date = Date.now) {
        publicID = pregnancyCheck.publicID.uuidString
        self.herdPublicID = herdPublicID.uuidString
        animalPublicID = pregnancyCheck.animal?.publicID.uuidString
        date = pregnancyCheck.date
        resultRawValue = pregnancyCheck.result.rawValue
        technician = pregnancyCheck.technician
        estimatedDaysPregnant = pregnancyCheck.estimatedDaysPregnant.map { NSNumber(value: $0) }
        dueDate = pregnancyCheck.dueDate
        sireAnimalPublicID = pregnancyCheck.sireAnimal?.publicID.uuidString
        workingSessionPublicID = pregnancyCheck.workingSession?.publicID.uuidString
        lastMirroredAt = mirroredAt
    }
}

extension SharedPregnancyCheckRecord {
    var parsedPublicID: UUID? {
        guard let publicID else { return nil }
        return UUID(uuidString: publicID)
    }

    var parsedAnimalPublicID: UUID? {
        guard let animalPublicID else { return nil }
        return UUID(uuidString: animalPublicID)
    }

    var parsedSireAnimalPublicID: UUID? {
        guard let sireAnimalPublicID else { return nil }
        return UUID(uuidString: sireAnimalPublicID)
    }

    var parsedWorkingSessionPublicID: UUID? {
        guard let workingSessionPublicID else { return nil }
        return UUID(uuidString: workingSessionPublicID)
    }

    var parsedResult: PregnancyResult {
        guard let resultRawValue else { return .unknown }
        return PregnancyResult(rawValue: resultRawValue) ?? .unknown
    }
}
