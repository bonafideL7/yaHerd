//
//  SharedTagColorDefinitionRecord.swift
//  yaHerd
//

import CoreData
import Foundation

@objc(SharedTagColorDefinitionRecord)
final class SharedTagColorDefinitionRecord: NSManagedObject {
  @NSManaged var publicID: String?
  @NSManaged var herdPublicID: String?
  @NSManaged var name: String?
  @NSManaged var prefix: String?
  @NSManaged var red: NSNumber?
  @NSManaged var green: NSNumber?
  @NSManaged var blue: NSNumber?
  @NSManaged var alpha: NSNumber?
  @NSManaged var sortOrder: NSNumber?
  @NSManaged var isHidden: NSNumber?
  @NSManaged var isDefault: NSNumber?
  @NSManaged var createdAt: Date?
  @NSManaged var updatedAt: Date?
  @NSManaged var lastMirroredAt: Date?
  @NSManaged var herd: SharedHerdRecord?
}

extension SharedTagColorDefinitionRecord {
  static let entityName = "SharedTagColorDefinitionRecord"

  @nonobjc
  class func fetchRequest() -> NSFetchRequest<SharedTagColorDefinitionRecord> {
    NSFetchRequest<SharedTagColorDefinitionRecord>(entityName: entityName)
  }

  func mirror(_ definition: TagColorDefinition, herdPublicID: UUID, mirroredAt: Date = Date.now) {
    publicID = definition.id.uuidString
    self.herdPublicID = herdPublicID.uuidString
    name = definition.name
    prefix = definition.prefix
    red = NSNumber(value: definition.red)
    green = NSNumber(value: definition.green)
    blue = NSNumber(value: definition.blue)
    alpha = NSNumber(value: definition.alpha)
    sortOrder = NSNumber(value: definition.sortOrder)
    isHidden = NSNumber(value: definition.isHidden)
    isDefault = NSNumber(value: definition.isDefault)
    createdAt = definition.createdAt
    updatedAt = definition.updatedAt
    lastMirroredAt = mirroredAt
  }
}

extension SharedTagColorDefinitionRecord {
  var parsedPublicID: UUID? {
    guard let publicID else { return nil }
    return UUID(uuidString: publicID)
  }

  var parsedRGBA: RGBAColor {
    RGBAColor(
      r: red?.doubleValue ?? 1,
      g: green?.doubleValue ?? 1,
      b: blue?.doubleValue ?? 1,
      a: alpha?.doubleValue ?? 1
    )
  }
}
