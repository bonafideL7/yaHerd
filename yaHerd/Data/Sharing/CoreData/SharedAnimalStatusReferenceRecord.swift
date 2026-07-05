//
//  SharedAnimalStatusReferenceRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedAnimalStatusReferenceRecord)
final class SharedAnimalStatusReferenceRecord: NSManagedObject {
  @NSManaged var publicID: String?
  @NSManaged var herdPublicID: String?
  @NSManaged var name: String?
  @NSManaged var baseStatusRawValue: String?
  @NSManaged var createdAt: Date?
  @NSManaged var lastMirroredAt: Date?
  @NSManaged var herd: SharedHerdRecord?
}

extension SharedAnimalStatusReferenceRecord {
  static let entityName = "SharedAnimalStatusReferenceRecord"

  @nonobjc
  class func fetchRequest() -> NSFetchRequest<SharedAnimalStatusReferenceRecord> {
    NSFetchRequest<SharedAnimalStatusReferenceRecord>(entityName: entityName)
  }

  func mirror(
    _ statusReference: AnimalStatusReference, herdPublicID: UUID, mirroredAt: Date = Date.now
  ) {
    publicID = statusReference.id.uuidString
    self.herdPublicID = herdPublicID.uuidString
    name = statusReference.name
    baseStatusRawValue = statusReference.baseStatus.rawValue
    createdAt = statusReference.createdAt
    lastMirroredAt = mirroredAt
  }
}

extension SharedAnimalStatusReferenceRecord {
  var parsedPublicID: UUID? {
    guard let publicID else { return nil }
    return UUID(uuidString: publicID)
  }

  var parsedBaseStatus: AnimalStatus {
    guard let baseStatusRawValue else { return .active }
    return AnimalStatus(rawValue: baseStatusRawValue) ?? .active
  }
}
