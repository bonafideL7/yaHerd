//
//  HerdSharingBridgeRecordSnapshot.swift
//  yaHerd
//

import CoreData
import Foundation

enum HerdSharingBridgeAttributeValue: Equatable, Sendable {
  case null
  case string(String)
  case date(Date)
  case data(Data)
  case integer(Int64)
  case double(Double)
  case boolean(Bool)

  init(value: Any?, attributeType: NSAttributeType) throws {
    guard let value else {
      self = .null
      return
    }

    switch attributeType {
    case .stringAttributeType:
      guard let value = value as? String else {
        throw HerdSharingBridgeSnapshotError.invalidAttributeValue(
          expected: "String", actual: String(describing: type(of: value)))
      }
      self = .string(value)
    case .dateAttributeType:
      guard let value = value as? Date else {
        throw HerdSharingBridgeSnapshotError.invalidAttributeValue(
          expected: "Date", actual: String(describing: type(of: value)))
      }
      self = .date(value)
    case .binaryDataAttributeType:
      guard let value = value as? Data else {
        throw HerdSharingBridgeSnapshotError.invalidAttributeValue(
          expected: "Data", actual: String(describing: type(of: value)))
      }
      self = .data(value)
    case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
      guard let value = value as? NSNumber else {
        throw HerdSharingBridgeSnapshotError.invalidAttributeValue(
          expected: "NSNumber", actual: String(describing: type(of: value)))
      }
      self = .integer(value.int64Value)
    case .decimalAttributeType, .doubleAttributeType, .floatAttributeType:
      guard let value = value as? NSNumber else {
        throw HerdSharingBridgeSnapshotError.invalidAttributeValue(
          expected: "NSNumber", actual: String(describing: type(of: value)))
      }
      self = .double(value.doubleValue)
    case .booleanAttributeType:
      guard let value = value as? NSNumber else {
        throw HerdSharingBridgeSnapshotError.invalidAttributeValue(
          expected: "NSNumber", actual: String(describing: type(of: value)))
      }
      self = .boolean(value.boolValue)
    default:
      throw HerdSharingBridgeSnapshotError.unsupportedAttributeType(attributeType.rawValue)
    }
  }

  var managedValue: Any? {
    switch self {
    case .null:
      nil
    case .string(let value):
      value
    case .date(let value):
      value
    case .data(let value):
      value
    case .integer(let value):
      NSNumber(value: value)
    case .double(let value):
      NSNumber(value: value)
    case .boolean(let value):
      NSNumber(value: value)
    }
  }
}

struct HerdSharingBridgeRecordSnapshot: Equatable, Sendable {
  let entityName: String
  let publicID: String
  let sourceObjectURI: String
  let attributes: [String: HerdSharingBridgeAttributeValue]

  init(record: NSManagedObject) throws {
    guard let entityName = record.entity.name else {
      throw HerdSharingBridgeSnapshotError.missingEntityName
    }
    guard let publicID = record.value(forKey: "publicID") as? String, !publicID.isEmpty else {
      throw HerdSharingBridgeSnapshotError.missingPublicID(entityName: entityName)
    }

    var attributes: [String: HerdSharingBridgeAttributeValue] = [:]
    attributes.reserveCapacity(record.entity.attributesByName.count)
    for (name, description) in record.entity.attributesByName {
      attributes[name] = try HerdSharingBridgeAttributeValue(
        value: record.value(forKey: name),
        attributeType: description.attributeType
      )
    }

    self.entityName = entityName
    self.publicID = publicID
    sourceObjectURI = record.objectID.uriRepresentation().absoluteString
    self.attributes = attributes
  }

  func apply(to record: NSManagedObject) throws {
    guard record.entity.name == entityName else {
      throw HerdSharingBridgeSnapshotError.entityMismatch(
        expected: entityName,
        actual: record.entity.name ?? "<missing>"
      )
    }

    for (name, description) in record.entity.attributesByName {
      guard let value = attributes[name] else {
        throw HerdSharingBridgeSnapshotError.missingAttribute(
          entityName: entityName,
          attributeName: name
        )
      }
      record.setValue(value.managedValue, forKey: description.name)
    }
  }

  var parsedPublicID: UUID? {
    UUID(uuidString: publicID)
  }

  var lastMirroredAt: Date {
    guard case .date(let value) = attributes["lastMirroredAt"] else {
      return .distantPast
    }
    return value
  }
}

struct HerdSharingBridgeStoreSnapshot: Sendable {
  let herdPublicID: UUID
  let storeDescription: String
  let recordsByStep: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]]

  func records(for step: HerdSharingBridgeStep) -> [HerdSharingBridgeRecordSnapshot] {
    recordsByStep[step, default: []]
  }

  var publicIDsByStep: [HerdSharingBridgeStep: [UUID]] {
    Dictionary(
      uniqueKeysWithValues: HerdSharingBridgeStep.entitySteps.map { step in
        (step, records(for: step).compactMap(\.parsedPublicID))
      }
    )
  }

  var deletionTombstoneCount: Int {
    records(for: .deletions).count
  }
}

struct HerdSharingBridgeWriteResult: Sendable {
  let snapshot: HerdSharingBridgeStoreSnapshot
  let managedObjectURIs: [String]
}

enum HerdSharingBridgeSnapshotError: LocalizedError {
  case missingEntityName
  case missingPublicID(entityName: String)
  case unsupportedAttributeType(UInt)
  case invalidAttributeValue(expected: String, actual: String)
  case entityMismatch(expected: String, actual: String)
  case missingAttribute(entityName: String, attributeName: String)
  case missingEntityDescription(String)
  case missingPersistentStore(URL)
  case missingHerdRecord(UUID?)

  var errorDescription: String? {
    switch self {
    case .missingEntityName:
      "A Core Data bridge record is missing its entity name."
    case .missingPublicID(let entityName):
      "A \(entityName) bridge record is missing its public ID."
    case .unsupportedAttributeType(let rawValue):
      "The bridge contains an unsupported Core Data attribute type (\(rawValue))."
    case .invalidAttributeValue(let expected, let actual):
      "The bridge expected \(expected) but received \(actual)."
    case .entityMismatch(let expected, let actual):
      "The bridge snapshot targets \(expected), but the destination record is \(actual)."
    case .missingAttribute(let entityName, let attributeName):
      "The \(entityName) bridge snapshot is missing \(attributeName)."
    case .missingEntityDescription(let entityName):
      "The Core Data bridge model does not contain \(entityName)."
    case .missingPersistentStore(let url):
      "The Core Data bridge store at \(url.path) is not loaded."
    case .missingHerdRecord(let publicID):
      if let publicID {
        "No Core Data bridge herd record exists for \(publicID.uuidString)."
      } else {
        "No Core Data bridge herd records are available."
      }
    }
  }
}

extension HerdSharingBridgeStep {
  var coreDataEntityName: String? {
    switch self {
    case .herd: SharedHerdRecord.entityName
    case .tagColorDefinitions: SharedTagColorDefinitionRecord.entityName
    case .statusReferences: SharedAnimalStatusReferenceRecord.entityName
    case .pastureGroups: SharedPastureGroupRecord.entityName
    case .pastures: SharedPastureRecord.entityName
    case .animals: SharedAnimalRecord.entityName
    case .animalTags: SharedAnimalTagRecord.entityName
    case .movements: SharedMovementRecord.entityName
    case .statusRecords: SharedStatusRecord.entityName
    case .workingProtocolTemplates: SharedWorkingProtocolTemplateRecord.entityName
    case .workingSessions: SharedWorkingSessionRecord.entityName
    case .workingQueueItems: SharedWorkingQueueItemRecord.entityName
    case .workingTreatmentRecords: SharedWorkingTreatmentRecord.entityName
    case .healthRecords: SharedHealthRecord.entityName
    case .pregnancyChecks: SharedPregnancyCheckRecord.entityName
    case .fieldCheckSessions: SharedFieldCheckSessionRecord.entityName
    case .fieldCheckAnimalChecks: SharedFieldCheckAnimalCheckRecord.entityName
    case .fieldCheckFindings: SharedFieldCheckFindingRecord.entityName
    case .deletions: SharedDeletedRecord.entityName
    case .persistentStoreCommit, .cloudKitShareUpdate, .reconciliation: nil
    }
  }
}
