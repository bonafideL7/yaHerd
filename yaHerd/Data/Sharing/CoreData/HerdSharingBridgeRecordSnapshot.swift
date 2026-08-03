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

private enum CollaborationBridgeMetadataAttribute {
  static let modifiedAt = "modifiedAt"
  static let revision = "revision"
  static let modifiedByParticipantID = "modifiedByParticipantID"
  static let modifiedByDeviceID = "modifiedByDeviceID"
  static let baseRevision = "baseRevision"
  static let baseFieldValuesJSON = "baseFieldValuesJSON"
  static let currentFieldValuesJSON = "currentFieldValuesJSON"

  static let all: Set<String> = [
    modifiedAt,
    revision,
    modifiedByParticipantID,
    modifiedByDeviceID,
    baseRevision,
    baseFieldValuesJSON,
    currentFieldValuesJSON,
  ]
}

extension HerdSharingBridgeRecordSnapshot {
  var collaborationAggregateKey: CollaborationAggregateKey? {
    guard let parsedPublicID else { return nil }
    let sourceEntityName: String
    if entityName == SharedDeletedRecord.entityName {
      guard case .string(let deletedSourceEntityName) = attributes["sourceEntityName"] else {
        return nil
      }
      sourceEntityName = deletedSourceEntityName
    } else {
      sourceEntityName = entityName
    }
    guard CollaborationAggregateType(rawValue: sourceEntityName) != nil else { return nil }
    return CollaborationAggregateKey(
      sourceEntityName: sourceEntityName,
      publicID: parsedPublicID
    )
  }

  var collaborationMetadata: CollaborationRevisionMetadata? {
    guard case .integer(let rawRevision) = attributes[CollaborationBridgeMetadataAttribute.revision],
          rawRevision > 0 else {
      return nil
    }

    let modifiedAt: Date
    if case .date(let value) = attributes[CollaborationBridgeMetadataAttribute.modifiedAt] {
      modifiedAt = value
    } else {
      modifiedAt = lastMirroredAt
    }

    let participantID: String
    if case .string(let value) = attributes[CollaborationBridgeMetadataAttribute.modifiedByParticipantID],
       !value.isEmpty {
      participantID = value
    } else {
      participantID = "legacy-unknown"
    }

    let deviceID: String
    if case .string(let value) = attributes[CollaborationBridgeMetadataAttribute.modifiedByDeviceID],
       !value.isEmpty {
      deviceID = value
    } else {
      deviceID = "legacy-unknown"
    }

    let baseRevision: Int
    if case .integer(let value) = attributes[CollaborationBridgeMetadataAttribute.baseRevision] {
      baseRevision = Int(value)
    } else {
      baseRevision = 0
    }

    let baseFieldValuesData: Data?
    if case .data(let value) = attributes[CollaborationBridgeMetadataAttribute.baseFieldValuesJSON] {
      baseFieldValuesData = value
    } else {
      baseFieldValuesData = nil
    }

    let currentFieldValuesData: Data?
    if case .data(let value) = attributes[CollaborationBridgeMetadataAttribute.currentFieldValuesJSON] {
      currentFieldValuesData = value
    } else {
      currentFieldValuesData = nil
    }

    let decodedCurrentValues = CollaborationRevisionMetadata.decodeFieldSnapshot(
      currentFieldValuesData
    )
    return CollaborationRevisionMetadata(
      modifiedAt: modifiedAt,
      revision: Int(rawRevision),
      modifiedByParticipantID: participantID,
      modifiedByDeviceID: deviceID,
      baseRevision: baseRevision,
      baseFieldValues: CollaborationRevisionMetadata.decodeFieldSnapshot(baseFieldValuesData),
      currentFieldValues: decodedCurrentValues.isEmpty ? collaborationDomainFieldSnapshot : decodedCurrentValues,
      isDeleted: entityName == SharedDeletedRecord.entityName
    )
  }

  var collaborationDomainFieldSnapshot: CollaborationFieldSnapshot {
    let excludedNames = CollaborationBridgeMetadataAttribute.all.union([
      "publicID",
      "herdPublicID",
      "lastMirroredAt",
    ])
    return attributes.reduce(into: CollaborationFieldSnapshot()) { result, item in
      guard !excludedNames.contains(item.key) else { return }
      result[item.key] = item.value.conflictValue
    }
  }

  func applyingCollaborationMetadata(
    _ metadata: CollaborationRevisionMetadata
  ) -> HerdSharingBridgeRecordSnapshot {
    var updatedAttributes = attributes
    updatedAttributes[CollaborationBridgeMetadataAttribute.modifiedAt] = .date(metadata.modifiedAt)
    updatedAttributes[CollaborationBridgeMetadataAttribute.revision] = .integer(Int64(metadata.revision))
    updatedAttributes[CollaborationBridgeMetadataAttribute.modifiedByParticipantID] =
      .string(metadata.modifiedByParticipantID)
    updatedAttributes[CollaborationBridgeMetadataAttribute.modifiedByDeviceID] =
      .string(metadata.modifiedByDeviceID)
    updatedAttributes[CollaborationBridgeMetadataAttribute.baseRevision] =
      .integer(Int64(metadata.baseRevision))
    if let baseData = CollaborationRevisionMetadata.encodeFieldSnapshot(metadata.baseFieldValues) {
      updatedAttributes[CollaborationBridgeMetadataAttribute.baseFieldValuesJSON] = .data(baseData)
    }
    if let currentData = CollaborationRevisionMetadata.encodeFieldSnapshot(metadata.currentFieldValues) {
      updatedAttributes[CollaborationBridgeMetadataAttribute.currentFieldValuesJSON] = .data(currentData)
    }
    return HerdSharingBridgeRecordSnapshot(
      entityName: entityName,
      publicID: publicID,
      sourceObjectURI: sourceObjectURI,
      attributes: updatedAttributes
    )
  }
}

private extension HerdSharingBridgeAttributeValue {
  var conflictValue: HerdSharingBridgeConflictValue {
    switch self {
    case .null:
      return .null
    case .string(let value):
      return HerdSharingBridgeConflictValue(type: .string, encodedValue: value)
    case .date(let value):
      return HerdSharingBridgeConflictValue(
        type: .date,
        encodedValue: ISO8601DateFormatter().string(from: value)
      )
    case .data(let value):
      return HerdSharingBridgeConflictValue(
        type: .string,
        encodedValue: value.base64EncodedString()
      )
    case .integer(let value):
      return HerdSharingBridgeConflictValue(type: .int, encodedValue: String(value))
    case .double(let value):
      return HerdSharingBridgeConflictValue(type: .double, encodedValue: String(value))
    case .boolean(let value):
      return HerdSharingBridgeConflictValue(
        type: .bool,
        encodedValue: value ? "true" : "false"
      )
    }
  }
}

struct HerdSharingBridgeStoreSnapshot: Sendable {
  let herdPublicID: UUID
  let storeDescription: String
  let recordsByStep: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]]

  init(
    herdPublicID: UUID,
    storeDescription: String,
    recordsByStep: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]]
  ) {
    self.herdPublicID = herdPublicID
    self.storeDescription = storeDescription
    self.recordsByStep = recordsByStep.mapValues { records in
      records.map(Self.prepareCollaborationMetadata)
    }
  }

  private static func prepareCollaborationMetadata(
    for record: HerdSharingBridgeRecordSnapshot
  ) -> HerdSharingBridgeRecordSnapshot {
    guard let key = record.collaborationAggregateKey else { return record }

    if record.sourceObjectURI.hasPrefix("yaherd-snapshot://") {
      let metadata = record.collaborationMetadata
        ?? CollaborationRevisionRegistry.localMetadata(for: key)
        ?? CollaborationRevisionMetadata.localBootstrap(
          fieldValues: record.collaborationDomainFieldSnapshot,
          isDeleted: record.entityName == SharedDeletedRecord.entityName
        )
      CollaborationRevisionRegistry.registerLocal(metadata, for: key)
      CollaborationRevisionRegistry.registerIncoming(metadata, for: key)
      return record.applyingCollaborationMetadata(metadata)
    }

    let metadata: CollaborationRevisionMetadata
    if let storedMetadata = record.collaborationMetadata {
      metadata = storedMetadata
    } else if record.entityName == SharedDeletedRecord.entityName,
              let localMetadata = CollaborationRevisionRegistry.localMetadata(for: key),
              localMetadata.isDeleted {
      metadata = localMetadata
    } else {
      metadata = CollaborationRevisionMetadata.legacySharedBootstrap(
        fieldValues: record.collaborationDomainFieldSnapshot,
        isDeleted: record.entityName == SharedDeletedRecord.entityName,
        modifiedAt: record.lastMirroredAt
      )
    }

    CollaborationRevisionRegistry.registerObservedShared(metadata, for: key)
    return record.applyingCollaborationMetadata(metadata)
  }

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
