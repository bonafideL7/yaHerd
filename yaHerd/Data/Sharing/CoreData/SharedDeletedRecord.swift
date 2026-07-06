//
//  SharedDeletedRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedDeletedRecord)
final class SharedDeletedRecord: NSManagedObject {
  @NSManaged var publicID: String?
  @NSManaged var herdPublicID: String?
  @NSManaged var sourceEntityName: String?
  @NSManaged var deletedAt: Date?
  @NSManaged var lastMirroredAt: Date?
  @NSManaged var herd: SharedHerdRecord?
}

extension SharedDeletedRecord {
  static let entityName = "SharedDeletedRecord"

  @nonobjc
  class func fetchRequest() -> NSFetchRequest<SharedDeletedRecord> {
    NSFetchRequest<SharedDeletedRecord>(entityName: entityName)
  }

  func mirrorDeletion(
    publicID: String,
    herdPublicID: UUID,
    sourceEntityName: String,
    deletedAt: Date = Date.now,
    mirroredAt: Date = Date.now
  ) {
    self.publicID = publicID
    self.herdPublicID = herdPublicID.uuidString
    self.sourceEntityName = sourceEntityName
    self.deletedAt = deletedAt
    self.lastMirroredAt = mirroredAt
  }
}

extension SharedDeletedRecord {
  var parsedPublicID: UUID? {
    guard let publicID else { return nil }
    return UUID(uuidString: publicID)
  }
}
