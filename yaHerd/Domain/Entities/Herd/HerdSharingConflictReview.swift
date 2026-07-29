//
//  HerdSharingConflictReview.swift
//  yaHerd
//

import Foundation

struct HerdSharingConflictReview: Codable, Equatable, Identifiable {
  var id: String { "\(detectedAt.timeIntervalSince1970)-\(sourceDescription)-\(title)" }

  let title: String
  let sourceDescription: String
  let detectedAt: Date
  let existingLocalRecordUpdateCount: Int
  var updatedRecordConflicts: [HerdSharingUpdatedRecordConflict] = []
  let preventedDeleteConflicts: [HerdSharingPreventedDeleteConflict]

  enum CodingKeys: String, CodingKey {
    case title
    case sourceDescription
    case detectedAt
    case existingLocalRecordUpdateCount
    case updatedRecordConflicts
    case preventedDeleteConflicts
  }

  init(
    title: String,
    sourceDescription: String,
    detectedAt: Date,
    existingLocalRecordUpdateCount: Int,
    updatedRecordConflicts: [HerdSharingUpdatedRecordConflict] = [],
    preventedDeleteConflicts: [HerdSharingPreventedDeleteConflict]
  ) {
    self.title = title
    self.sourceDescription = sourceDescription
    self.detectedAt = detectedAt
    self.existingLocalRecordUpdateCount = existingLocalRecordUpdateCount
    self.updatedRecordConflicts = updatedRecordConflicts
    self.preventedDeleteConflicts = preventedDeleteConflicts
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    sourceDescription = try container.decode(String.self, forKey: .sourceDescription)
    detectedAt = try container.decode(Date.self, forKey: .detectedAt)
    existingLocalRecordUpdateCount = try container.decode(
      Int.self,
      forKey: .existingLocalRecordUpdateCount
    )
    updatedRecordConflicts =
      try container.decodeIfPresent(
        [HerdSharingUpdatedRecordConflict].self,
        forKey: .updatedRecordConflicts
      ) ?? []
    preventedDeleteConflicts = try container.decode(
      [HerdSharingPreventedDeleteConflict].self,
      forKey: .preventedDeleteConflicts
    )
  }

  var updatedRecordConflictCount: Int { updatedRecordConflicts.count }
  var preventedDeleteCount: Int { preventedDeleteConflicts.count }
  var hasConflicts: Bool {
    existingLocalRecordUpdateCount > 0 || updatedRecordConflictCount > 0 || preventedDeleteCount > 0
  }

  var updatedRecordEntitySummaries: [HerdSharingUpdatedRecordEntitySummary] {
    Dictionary(grouping: updatedRecordConflicts, by: \.displayEntityName)
      .map { entityName, conflicts in
        HerdSharingUpdatedRecordEntitySummary(
          displayEntityName: entityName,
          count: conflicts.count
        )
      }
      .sorted { lhs, rhs in
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.displayEntityName < rhs.displayEntityName
      }
  }

  var preventedDeleteEntitySummaries: [HerdSharingPreventedDeleteEntitySummary] {
    Dictionary(grouping: preventedDeleteConflicts, by: \.displayEntityName)
      .map { entityName, conflicts in
        HerdSharingPreventedDeleteEntitySummary(
          displayEntityName: entityName,
          count: conflicts.count
        )
      }
      .sorted { lhs, rhs in
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.displayEntityName < rhs.displayEntityName
      }
  }

  var latestLocalModifiedAt: Date? {
    preventedDeleteConflicts.map(\.localModifiedAt).max()
  }

  var earliestSharedDeletedAt: Date? {
    preventedDeleteConflicts.map(\.sharedDeletedAt).min()
  }

  var recommendedAction: String {
    guard hasConflicts else {
      return "No action is needed."
    }

    if preventedDeleteCount > 0 {
      return
        "Choose Keep Local Records to preserve local edits, or Accept Shared Deletes to delete the affected local records by public ID."
    }

    if updatedRecordConflictCount > 0 {
      return
        "Choose Accept Shared Updates if the imported shared values are correct. Restore selected local fields when only specific pre-import values should be kept, then mark the report resolved after the selected restores fully address the conflict."
    }

    return "Review the affected records if the shared update was unexpected."
  }

  var summary: String {
    guard hasConflicts else {
      return "No shared-data conflicts were detected."
    }

    var parts: [String] = []
    if existingLocalRecordUpdateCount > 0 {
      parts.append(
        "\(existingLocalRecordUpdateCount) existing local record(s) were updated from shared data")
    }
    if preventedDeleteCount > 0 {
      parts.append(
        "\(preventedDeleteCount) shared delete(s) were skipped because local records appear newer")
    }
    return parts.joined(separator: "; ") + "."
  }
}

struct HerdSharingConflictStoredValue: Codable, Equatable {
  enum ValueType: String, Codable {
    case null
    case string
    case bool
    case int
    case double
    case date
    case uuid
  }

  let type: ValueType
  let encodedValue: String?

  init(type: ValueType, encodedValue: String?) {
    self.type = type
    self.encodedValue = encodedValue
  }

  static let null = HerdSharingConflictStoredValue(type: .null, encodedValue: nil)

  static func string(_ value: String) -> HerdSharingConflictStoredValue {
    HerdSharingConflictStoredValue(type: .string, encodedValue: value)
  }

  static func bool(_ value: Bool) -> HerdSharingConflictStoredValue {
    HerdSharingConflictStoredValue(type: .bool, encodedValue: value ? "true" : "false")
  }

  static func int(_ value: Int) -> HerdSharingConflictStoredValue {
    HerdSharingConflictStoredValue(type: .int, encodedValue: String(value))
  }

  static func double(_ value: Double) -> HerdSharingConflictStoredValue {
    HerdSharingConflictStoredValue(type: .double, encodedValue: String(value))
  }

  static func date(_ value: Date) -> HerdSharingConflictStoredValue {
    HerdSharingConflictStoredValue(
      type: .date,
      encodedValue: ISO8601DateFormatter().string(from: value)
    )
  }

  static func uuid(_ value: UUID) -> HerdSharingConflictStoredValue {
    HerdSharingConflictStoredValue(type: .uuid, encodedValue: value.uuidString)
  }

  var stringValue: String? {
    guard type == .string else { return nil }
    return encodedValue
  }

  var boolValue: Bool? {
    guard type == .bool, let encodedValue else { return nil }
    return Bool(encodedValue)
  }

  var intValue: Int? {
    guard type == .int, let encodedValue else { return nil }
    return Int(encodedValue)
  }

  var doubleValue: Double? {
    guard let encodedValue else { return nil }
    switch type {
    case .double:
      return Double(encodedValue)
    case .int:
      return Double(encodedValue)
    default:
      return nil
    }
  }

  var dateValue: Date? {
    guard type == .date, let encodedValue else { return nil }
    return ISO8601DateFormatter().date(from: encodedValue)
  }

  var uuidValue: UUID? {
    guard type == .uuid, let encodedValue else { return nil }
    return UUID(uuidString: encodedValue)
  }

  var isNull: Bool { type == .null }

  var displayDescription: String {
    guard let encodedValue else { return "nil" }
    return encodedValue
  }

  var displayType: String { type.rawValue }
}

struct HerdSharingLocalFieldRestoreSelection: Codable, Equatable, Hashable, Identifiable {
  var id: String { "\(sourceEntityName)-\(publicID.uuidString)-\(fieldName)" }

  let sourceEntityName: String
  let publicID: UUID
  let fieldName: String

  init(sourceEntityName: String, publicID: UUID, fieldName: String) {
    self.sourceEntityName = sourceEntityName
    self.publicID = publicID
    self.fieldName = fieldName
  }
}

struct HerdSharingLocalFieldRestoreResult: Codable, Equatable {
  let requestedFieldCount: Int
  let restoredFieldCount: Int
  let skippedFieldCount: Int

  var restoredAnyFields: Bool { restoredFieldCount > 0 }
}

struct HerdSharingUpdatedRecordFieldChange: Codable, Equatable, Identifiable {
  var id: String { fieldName }

  let fieldName: String
  let localValue: HerdSharingConflictStoredValue
  let sharedValue: HerdSharingConflictStoredValue

  enum CodingKeys: String, CodingKey {
    case fieldName
    case localValue
    case sharedValue
    case localValueDescription
    case sharedValueDescription
  }

  init(
    fieldName: String,
    localValue: HerdSharingConflictStoredValue,
    sharedValue: HerdSharingConflictStoredValue
  ) {
    self.fieldName = fieldName
    self.localValue = localValue
    self.sharedValue = sharedValue
  }

  init(
    fieldName: String,
    localValueDescription: String,
    sharedValueDescription: String
  ) {
    self.init(
      fieldName: fieldName,
      localValue: .string(localValueDescription),
      sharedValue: .string(sharedValueDescription)
    )
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fieldName = try container.decode(String.self, forKey: .fieldName)

    if let localValue = try container.decodeIfPresent(
      HerdSharingConflictStoredValue.self,
      forKey: .localValue
    ),
      let sharedValue = try container.decodeIfPresent(
        HerdSharingConflictStoredValue.self,
        forKey: .sharedValue
      )
    {
      self.localValue = localValue
      self.sharedValue = sharedValue
    } else {
      localValue = .string(
        try container.decodeIfPresent(String.self, forKey: .localValueDescription) ?? "nil"
      )
      sharedValue = .string(
        try container.decodeIfPresent(String.self, forKey: .sharedValueDescription) ?? "nil"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(fieldName, forKey: .fieldName)
    try container.encode(localValue, forKey: .localValue)
    try container.encode(sharedValue, forKey: .sharedValue)
    try container.encode(localValueDescription, forKey: .localValueDescription)
    try container.encode(sharedValueDescription, forKey: .sharedValueDescription)
  }

  var restoreSelectionID: String { fieldName }
  var localValueDescription: String { localValue.displayDescription }
  var sharedValueDescription: String { sharedValue.displayDescription }
}


enum HerdSharingLocalFieldRestoreSupportCategory: String, Codable, Equatable {
  case restorable
  case relationship
  case complex
  case unsupported

  var displayName: String {
    switch self {
    case .restorable:
      return "Restorable"
    case .relationship:
      return "Relationship"
    case .complex:
      return "Complex"
    case .unsupported:
      return "Unsupported"
    }
  }

  var reviewExplanation: String {
    switch self {
    case .restorable:
      return "This scalar field can be restored from the conflict report."
    case .relationship:
      return "Relationship fields are review-only because the linked record may have changed, been deleted, or not exist locally."
    case .complex:
      return "Complex fields are review-only because restoring part of the stored structure could corrupt the record."
    case .unsupported:
      return "This field is not currently supported for local restore."
    }
  }
}

struct HerdSharingUpdatedRecordConflict: Codable, Equatable, Identifiable {
  var id: String { "\(sourceEntityName)-\(publicID.uuidString)" }

  let sourceEntityName: String
  let publicID: UUID
  let localModifiedAt: Date
  let sharedModifiedAt: Date
  var fieldChanges: [HerdSharingUpdatedRecordFieldChange]

  enum CodingKeys: String, CodingKey {
    case sourceEntityName
    case publicID
    case localModifiedAt
    case sharedModifiedAt
    case fieldChanges
  }

  init(
    sourceEntityName: String,
    publicID: UUID,
    localModifiedAt: Date,
    sharedModifiedAt: Date,
    fieldChanges: [HerdSharingUpdatedRecordFieldChange] = []
  ) {
    self.sourceEntityName = sourceEntityName
    self.publicID = publicID
    self.localModifiedAt = localModifiedAt
    self.sharedModifiedAt = sharedModifiedAt
    self.fieldChanges = fieldChanges
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sourceEntityName = try container.decode(String.self, forKey: .sourceEntityName)
    publicID = try container.decode(UUID.self, forKey: .publicID)
    localModifiedAt = try container.decode(Date.self, forKey: .localModifiedAt)
    sharedModifiedAt = try container.decode(Date.self, forKey: .sharedModifiedAt)
    fieldChanges =
      try container.decodeIfPresent(
        [HerdSharingUpdatedRecordFieldChange].self,
        forKey: .fieldChanges
      ) ?? []
  }

  var changedFieldCount: Int { fieldChanges.count }

  var supportedLocalRestoreFieldChanges: [HerdSharingUpdatedRecordFieldChange] {
    fieldChanges.filter { localFieldRestoreSupportCategory(for: $0) == .restorable }
  }

  var reviewOnlyFieldChanges: [HerdSharingUpdatedRecordFieldChange] {
    fieldChanges.filter { localFieldRestoreSupportCategory(for: $0) != .restorable }
  }

  var relationshipFieldChanges: [HerdSharingUpdatedRecordFieldChange] {
    fieldChanges.filter { localFieldRestoreSupportCategory(for: $0) == .relationship }
  }

  var complexFieldChanges: [HerdSharingUpdatedRecordFieldChange] {
    fieldChanges.filter { localFieldRestoreSupportCategory(for: $0) == .complex }
  }

  var unsupportedFieldChanges: [HerdSharingUpdatedRecordFieldChange] {
    fieldChanges.filter { localFieldRestoreSupportCategory(for: $0) == .unsupported }
  }

  var supportsLocalFieldRestore: Bool { !supportedLocalRestoreFieldChanges.isEmpty }
  var hasReviewOnlyFieldChanges: Bool { !reviewOnlyFieldChanges.isEmpty }
  var hasRelationshipFieldChanges: Bool { !relationshipFieldChanges.isEmpty }
  var hasComplexFieldChanges: Bool { !complexFieldChanges.isEmpty }
  var hasUnsupportedFieldChanges: Bool { !unsupportedFieldChanges.isEmpty }

  func localFieldRestoreSupportCategory(
    for fieldChange: HerdSharingUpdatedRecordFieldChange
  ) -> HerdSharingLocalFieldRestoreSupportCategory {
    localFieldRestoreSupportCategory(fieldName: fieldChange.fieldName)
  }

  func restoreSelection(for fieldChange: HerdSharingUpdatedRecordFieldChange)
    -> HerdSharingLocalFieldRestoreSelection
  {
    HerdSharingLocalFieldRestoreSelection(
      sourceEntityName: sourceEntityName,
      publicID: publicID,
      fieldName: fieldChange.fieldName
    )
  }

  private func localFieldRestoreSupportCategory(
    fieldName: String
  ) -> HerdSharingLocalFieldRestoreSupportCategory {
    if Self.relationshipFieldNames.contains(fieldName) {
      return .relationship
    }

    if Self.complexFieldNames.contains(fieldName) {
      return .complex
    }

    if restorableScalarFieldNames.contains(fieldName) {
      return .restorable
    }

    return .unsupported
  }

  private var restorableScalarFieldNames: Set<String> {
    switch sourceEntityName {
    case "SharedAnimalRecord":
      return [
        "name", "tagNumber", "tagColorID", "sex", "birthDate", "status", "saleDate",
        "salePrice", "reasonSold", "deathDate", "causeOfDeath", "statusReferenceID",
        "isSoftDeleted", "softDeletedAt", "softDeleteReason", "location",
      ]
    case "SharedPastureRecord":
      return [
        "name", "sortOrder", "acreage", "usableAcreage", "targetAcresPerHead",
        "lastGrazedDate",
      ]
    case "SharedTagColorDefinitionRecord":
      return [
        "name", "prefix", "red", "green", "blue", "alpha", "sortOrder",
        "isHidden", "isDefault", "createdAt", "updatedAt",
      ]
    case "SharedAnimalStatusReferenceRecord":
      return ["name", "baseStatus", "createdAt"]
    case "SharedPastureGroupRecord":
      return ["name", "grazeDays", "restDays"]
    case "SharedHealthRecord":
      return ["date", "treatment", "notes"]
    case "SharedMovementRecord":
      return ["date", "fromPasture", "toPasture"]
    case "SharedPregnancyCheckRecord":
      return ["date", "result", "technician", "estimatedDaysPregnant", "dueDate"]
    case "SharedStatusRecord":
      return [
        "date", "oldStatus", "newStatus", "oldStatusReferenceID",
        "newStatusReferenceID",
      ]
    case "SharedAnimalTagRecord":
      return [
        "number", "colorID", "isPrimary", "isActive", "assignedAt", "removedAt",
      ]
    case "SharedWorkingProtocolTemplateRecord":
      return ["name"]
    case "SharedWorkingSessionRecord":
      return [
        "date", "status", "protocolName", "currentQueueIndex", "notes",
      ]
    case "SharedWorkingQueueItemRecord":
      return [
        "queueOrder", "status", "completedAt", "workNotes",
      ]
    case "SharedWorkingTreatmentRecord":
      return [
        "date", "itemName", "given", "quantity", "doseAmount", "doseUnit",
        "administrationRoute",
      ]
    case "SharedFieldCheckSessionRecord":
      return [
        "startedAt", "completedAt", "notes", "expectedHeadCountSnapshot",
        "quickCowCount", "quickHeiferCount", "quickCalfCount", "quickBullCount",
        "quickSteerCount", "pastureNameSnapshot", "pastureArchivedAt", "pastureID",
      ]
    case "SharedFieldCheckAnimalCheckRecord":
      return [
        "animalIDSnapshot", "rosterTagNumber", "rosterTagColorID",
        "damRosterTagNumber", "damRosterTagColorID", "animalName", "animalSex",
        "animalTypeSnapshot", "wasExpectedAtStart", "countedAt", "missingConfirmedAt",
        "note",
      ]
    case "SharedFieldCheckFindingRecord":
      return [
        "recordedAt", "type", "severity", "status", "note", "animalIDSnapshot",
        "animalDisplayTagNumberSnapshot", "animalDisplayTagColorIDSnapshot",
        "animalNameSnapshot", "pastureNameSnapshot", "sessionIDSnapshot",
      ]
    default:
      return []
    }
  }

  private static let relationshipFieldNames: Set<String> = [
    "animalPublicID",
    "herdPublicID",
    "pasturePublicID",
    "groupPublicID",
    "workingSessionPublicID",
    "sireAnimalPublicID",
    "sourcePasturePublicID",
    "destinationPasturePublicID",
    "collectedFromPasturePublicID",
    "sessionPublicID",
    "fieldCheckSessionPublicID",
  ]

  private static let complexFieldNames: Set<String> = [
    "distinguishingFeatures",
    "items",
    "protocolItems",
  ]


  var displayEntityName: String {
    sourceEntityName
      .replacingOccurrences(of: "Shared", with: "")
      .replacingOccurrences(of: "Record", with: "")
  }
}

struct HerdSharingUpdatedRecordEntitySummary: Equatable, Identifiable {
  var id: String { displayEntityName }

  let displayEntityName: String
  let count: Int
}

struct HerdSharingPreventedDeleteConflict: Codable, Equatable, Identifiable {
  var id: String { "\(sourceEntityName)-\(publicID.uuidString)" }

  let sourceEntityName: String
  let publicID: UUID
  let localModifiedAt: Date
  let sharedDeletedAt: Date

  var displayEntityName: String {
    sourceEntityName
      .replacingOccurrences(of: "Shared", with: "")
      .replacingOccurrences(of: "Record", with: "")
  }
}

struct HerdSharingPreventedDeleteEntitySummary: Equatable, Identifiable {
  var id: String { displayEntityName }

  let displayEntityName: String
  let count: Int
}
