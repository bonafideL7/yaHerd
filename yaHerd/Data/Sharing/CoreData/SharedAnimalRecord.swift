//
//  SharedAnimalRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedAnimalRecord)
final class SharedAnimalRecord: NSManagedObject {
  @NSManaged var publicID: String?
  @NSManaged var herdPublicID: String?
  @NSManaged var name: String?
  @NSManaged var tagNumber: String?
  @NSManaged var tagColorID: String?
  @NSManaged var sexRawValue: String?
  @NSManaged var birthDate: Date?
  @NSManaged var statusRawValue: String?
  @NSManaged var saleDate: Date?
  @NSManaged var salePrice: NSNumber?
  @NSManaged var reasonSold: String?
  @NSManaged var deathDate: Date?
  @NSManaged var causeOfDeath: String?
  @NSManaged var statusReferenceID: String?
  @NSManaged var isSoftDeleted: NSNumber?
  @NSManaged var softDeletedAt: Date?
  @NSManaged var softDeleteReason: String?
  @NSManaged var locationRawValue: String?
  @NSManaged var pasturePublicID: String?
  @NSManaged var sireAnimalPublicID: String?
  @NSManaged var damAnimalPublicID: String?
  @NSManaged var distinguishingFeaturesJSON: Data?
  @NSManaged var lastMirroredAt: Date?
  @NSManaged var herd: SharedHerdRecord?
  @NSManaged var animalTags: Set<SharedAnimalTagRecord>?
  @NSManaged var movements: Set<SharedMovementRecord>?
  @NSManaged var statusRecords: Set<SharedStatusRecord>?
  @NSManaged var healthRecords: Set<SharedHealthRecord>?
  @NSManaged var pregnancyChecks: Set<SharedPregnancyCheckRecord>?
  @NSManaged var workingQueueItems: Set<SharedWorkingQueueItemRecord>?
  @NSManaged var workingTreatmentRecords: Set<SharedWorkingTreatmentRecord>?
  @NSManaged var fieldCheckAnimalChecks: Set<SharedFieldCheckAnimalCheckRecord>?
  @NSManaged var fieldCheckFindings: Set<SharedFieldCheckFindingRecord>?
}

extension SharedAnimalRecord {
  static let entityName = "SharedAnimalRecord"

  @nonobjc
  class func fetchRequest() -> NSFetchRequest<SharedAnimalRecord> {
    NSFetchRequest<SharedAnimalRecord>(entityName: entityName)
  }

  func mirror(_ animal: Animal, herdPublicID: UUID, mirroredAt: Date = Date.now) {
    publicID = animal.publicID.uuidString
    self.herdPublicID = herdPublicID.uuidString
    name = animal.name
    tagNumber = animal.tagNumber
    tagColorID = animal.tagColorID?.uuidString
    sexRawValue = animal.sex?.rawValue
    birthDate = animal.birthDate
    statusRawValue = animal.status.rawValue
    saleDate = animal.saleDate
    salePrice = animal.salePrice.map { NSNumber(value: $0) }
    reasonSold = animal.reasonSold
    deathDate = animal.deathDate
    causeOfDeath = animal.causeOfDeath
    statusReferenceID = animal.statusReferenceID?.uuidString
    isSoftDeleted = NSNumber(value: animal.isSoftDeleted)
    softDeletedAt = animal.softDeletedAt
    softDeleteReason = animal.softDeleteReason
    locationRawValue = animal.location.rawValue
    pasturePublicID = animal.pasture?.publicID.uuidString
    sireAnimalPublicID = animal.sireAnimal?.publicID.uuidString
    damAnimalPublicID = animal.damAnimal?.publicID.uuidString
    do {
      distinguishingFeaturesJSON = try JSONEncoder().encode(
        animal.distinguishingFeatures.normalizedDistinguishingFeatureOrder)
    } catch {
      distinguishingFeaturesJSON = nil
      PersistenceLog.decodeFailure("SharedAnimalRecord.distinguishingFeaturesJSON.encode", error: error)
    }
    lastMirroredAt = mirroredAt
  }
}
