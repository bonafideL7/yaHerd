//
//  SharedAnimalTagRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedAnimalTagRecord)
final class SharedAnimalTagRecord: NSManagedObject {
  @NSManaged var publicID: String?
  @NSManaged var herdPublicID: String?
  @NSManaged var animalPublicID: String?
  @NSManaged var number: String?
  @NSManaged var colorID: String?
  @NSManaged var isPrimary: NSNumber?
  @NSManaged var isActive: NSNumber?
  @NSManaged var assignedAt: Date?
  @NSManaged var removedAt: Date?
  @NSManaged var lastMirroredAt: Date?
  @NSManaged var herd: SharedHerdRecord?
  @NSManaged var animal: SharedAnimalRecord?
}

extension SharedAnimalTagRecord {
  static let entityName = "SharedAnimalTagRecord"

  @nonobjc
  class func fetchRequest() -> NSFetchRequest<SharedAnimalTagRecord> {
    NSFetchRequest<SharedAnimalTagRecord>(entityName: entityName)
  }

  func mirror(_ tag: AnimalTag, herdPublicID: UUID, mirroredAt: Date = Date.now) {
    publicID = tag.publicID.uuidString
    self.herdPublicID = herdPublicID.uuidString
    animalPublicID = tag.animal?.publicID.uuidString
    number = tag.number
    colorID = tag.colorID?.uuidString
    isPrimary = NSNumber(value: tag.isPrimary)
    isActive = NSNumber(value: tag.isActive)
    assignedAt = tag.assignedAt
    removedAt = tag.removedAt
    lastMirroredAt = mirroredAt
  }
}

extension SharedAnimalTagRecord {
  var parsedPublicID: UUID? {
    guard let publicID else { return nil }
    return UUID(uuidString: publicID)
  }

  var parsedAnimalPublicID: UUID? {
    guard let animalPublicID else { return nil }
    return UUID(uuidString: animalPublicID)
  }

  var parsedColorID: UUID? {
    guard let colorID else { return nil }
    return UUID(uuidString: colorID)
  }
}
