//
//  HerdSharingBridgeConflictReport.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeConflictReport: Equatable {
  static let empty = HerdSharingBridgeConflictReport(
    existingLocalRecordUpdateCount: 0,
    updatedRecordConflicts: [],
    preventedDeleteConflicts: []
  )

  let existingLocalRecordUpdateCount: Int
  var updatedRecordConflicts: [HerdSharingBridgeConflictDetail] = []
  let preventedDeleteConflicts: [HerdSharingBridgeConflictDetail]

  var updatedRecordConflictCount: Int { updatedRecordConflicts.count }
  var preventedDeleteCount: Int { preventedDeleteConflicts.count }
  var hasConflicts: Bool {
    existingLocalRecordUpdateCount > 0 || updatedRecordConflictCount > 0 || preventedDeleteCount > 0
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

struct HerdSharingBridgeConflictValue: Equatable {
  enum ValueType: String, Equatable {
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

  static let null = HerdSharingBridgeConflictValue(type: .null, encodedValue: nil)

  var displayDescription: String {
    guard let encodedValue else { return "nil" }
    return encodedValue
  }
}

struct HerdSharingBridgeFieldChange: Equatable, Identifiable {
  var id: String { fieldName }

  let fieldName: String
  let localValue: HerdSharingBridgeConflictValue
  let sharedValue: HerdSharingBridgeConflictValue

  init(
    fieldName: String,
    localValue: HerdSharingBridgeConflictValue,
    sharedValue: HerdSharingBridgeConflictValue
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
      localValue: HerdSharingBridgeConflictValue(type: .string, encodedValue: localValueDescription),
      sharedValue: HerdSharingBridgeConflictValue(type: .string, encodedValue: sharedValueDescription)
    )
  }

  var localValueDescription: String { localValue.displayDescription }
  var sharedValueDescription: String { sharedValue.displayDescription }
}

struct HerdSharingBridgeConflictDetail: Equatable, Identifiable {
  enum Kind: String, Equatable {
    case existingLocalRecordUpdate
    case preventedSharedDelete
  }

  let id: UUID
  let kind: Kind
  let sourceEntityName: String
  let publicID: UUID
  let localModifiedAt: Date
  let sharedModifiedAt: Date
  var fieldChanges: [HerdSharingBridgeFieldChange]

  init(
    kind: Kind,
    sourceEntityName: String,
    publicID: UUID,
    localModifiedAt: Date,
    sharedModifiedAt: Date,
    fieldChanges: [HerdSharingBridgeFieldChange] = []
  ) {
    id = UUID()
    self.kind = kind
    self.sourceEntityName = sourceEntityName
    self.publicID = publicID
    self.localModifiedAt = localModifiedAt
    self.sharedModifiedAt = sharedModifiedAt
    self.fieldChanges = fieldChanges
  }
}
