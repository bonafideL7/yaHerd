//
//  HerdSharingBridgeConflictReport.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeConflictReport: Codable, Equatable, Sendable {
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

  /// Preserves conflict evidence from an interrupted prior attempt while preferring a freshly
  /// captured snapshot for any record that was compared again.
  func recoveringMissingConflicts(
    from interruptedReport: HerdSharingBridgeConflictReport?
  ) -> HerdSharingBridgeConflictReport {
    guard let interruptedReport else { return self }

    let freshUpdateKeys = Set(updatedRecordConflicts.map(\.recordKey))
    let recoveredUpdates = interruptedReport.updatedRecordConflicts.filter {
      !freshUpdateKeys.contains($0.recordKey)
    }
    let mergedUpdates = updatedRecordConflicts + recoveredUpdates

    let freshDeleteKeys = Set(preventedDeleteConflicts.map(\.recordKey))
    let recoveredDeletes = interruptedReport.preventedDeleteConflicts.filter {
      !freshDeleteKeys.contains($0.recordKey)
    }
    let mergedDeletes = preventedDeleteConflicts + recoveredDeletes

    return HerdSharingBridgeConflictReport(
      existingLocalRecordUpdateCount: mergedUpdates.count,
      updatedRecordConflicts: mergedUpdates,
      preventedDeleteConflicts: mergedDeletes
    )
  }
}

struct HerdSharingBridgeConflictValue: Codable, Equatable, Sendable {
  enum ValueType: String, Codable, Equatable, Sendable {
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

struct HerdSharingBridgeFieldChange: Codable, Equatable, Identifiable, Sendable {
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
      localValue: HerdSharingBridgeConflictValue(
        type: .string, encodedValue: localValueDescription),
      sharedValue: HerdSharingBridgeConflictValue(
        type: .string, encodedValue: sharedValueDescription)
    )
  }

  var localValueDescription: String { localValue.displayDescription }
  var sharedValueDescription: String { sharedValue.displayDescription }
}

struct HerdSharingBridgeConflictDetail: Codable, Equatable, Identifiable, Sendable {
  enum Kind: String, Codable, Equatable, Sendable {
    case existingLocalRecordUpdate
    case preventedSharedDelete
  }

  enum RevisionComparison: String, Codable, Equatable, Sendable {
    case metadataUnavailable
    case sameRevisionMismatch
    case localOnly
    case sharedOnly
    case divergent
  }

  let id: UUID
  let kind: Kind
  let sourceEntityName: String
  let publicID: UUID
  let localModifiedAt: Date
  let sharedModifiedAt: Date
  var fieldChanges: [HerdSharingBridgeFieldChange]

  /// Optional for backward-compatible decoding of conflict reports written
  /// before revision metadata was introduced.
  let lastCommonRevision: Int?
  let localRevision: Int?
  let sharedRevision: Int?
  let localBaseRevision: Int?
  let sharedBaseRevision: Int?
  let localModifiedByParticipantID: String?
  let localModifiedByDeviceID: String?
  let sharedModifiedByParticipantID: String?
  let sharedModifiedByDeviceID: String?
  let revisionComparison: RevisionComparison?
  let localChangedFields: [String]?
  let sharedChangedFields: [String]?
  let canMergeAutomatically: Bool?

  fileprivate var recordKey: String {
    "\(kind.rawValue)|\(sourceEntityName)|\(publicID.uuidString)"
  }

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
    self.fieldChanges = fieldChanges

    let key = CollaborationAggregateKey(
      sourceEntityName: sourceEntityName,
      publicID: publicID
    )
    let localMetadata = CollaborationRevisionRegistry.localMetadata(for: key)
    let sharedMetadata = CollaborationRevisionRegistry.incomingMetadata(for: key)
    self.localModifiedAt = localMetadata?.modifiedAt ?? localModifiedAt
    self.sharedModifiedAt = sharedMetadata?.modifiedAt ?? sharedModifiedAt
    localRevision = localMetadata?.revision
    sharedRevision = sharedMetadata?.revision
    localBaseRevision = localMetadata?.baseRevision
    sharedBaseRevision = sharedMetadata?.baseRevision
    localModifiedByParticipantID = localMetadata?.modifiedByParticipantID
    localModifiedByDeviceID = localMetadata?.modifiedByDeviceID
    sharedModifiedByParticipantID = sharedMetadata?.modifiedByParticipantID
    sharedModifiedByDeviceID = sharedMetadata?.modifiedByDeviceID

    let analysis = Self.analyzeRevisions(
      local: localMetadata,
      shared: sharedMetadata,
      fieldChanges: fieldChanges
    )
    lastCommonRevision = analysis.lastCommonRevision
    revisionComparison = analysis.comparison
    localChangedFields = analysis.localChangedFields
    sharedChangedFields = analysis.sharedChangedFields
    canMergeAutomatically = analysis.canMergeAutomatically
  }

  private struct RevisionAnalysis {
    let lastCommonRevision: Int?
    let comparison: RevisionComparison
    let localChangedFields: [String]
    let sharedChangedFields: [String]
    let canMergeAutomatically: Bool
  }

  private static func analyzeRevisions(
    local: CollaborationRevisionMetadata?,
    shared: CollaborationRevisionMetadata?,
    fieldChanges: [HerdSharingBridgeFieldChange]
  ) -> RevisionAnalysis {
    guard let local, let shared else {
      return RevisionAnalysis(
        lastCommonRevision: nil,
        comparison: .metadataUnavailable,
        localChangedFields: fieldChanges.map(\.fieldName).sorted(),
        sharedChangedFields: fieldChanges.map(\.fieldName).sorted(),
        canMergeAutomatically: false
      )
    }

    let comparison: RevisionComparison
    let lastCommonRevision: Int?
    let baseFields: CollaborationFieldSnapshot?

    if local.revision == shared.revision {
      if local.currentFieldValues != shared.currentFieldValues,
        local.baseRevision == shared.baseRevision,
        local.baseRevision > 0,
        local.baseRevision < local.revision
      {
        comparison = .divergent
        lastCommonRevision = local.baseRevision
        baseFields = commonBaseFields(local: local, shared: shared)
      } else {
        comparison = .sameRevisionMismatch
        lastCommonRevision = local.baseRevision == shared.baseRevision && local.baseRevision > 0
          ? local.baseRevision
          : nil
        baseFields = nil
      }
    } else if local.revision == shared.baseRevision {
      comparison = .sharedOnly
      lastCommonRevision = local.revision
      baseFields = local.currentFieldValues
    } else if shared.revision == local.baseRevision {
      comparison = .localOnly
      lastCommonRevision = shared.revision
      baseFields = shared.currentFieldValues
    } else if local.baseRevision == shared.baseRevision, local.baseRevision > 0 {
      comparison = .divergent
      lastCommonRevision = local.baseRevision
      baseFields = commonBaseFields(local: local, shared: shared)
    } else {
      comparison = .divergent
      lastCommonRevision = nil
      baseFields = nil
    }

    let localChangedFields: [String]
    let sharedChangedFields: [String]
    if let baseFields {
      localChangedFields = changedFieldNames(
        from: baseFields,
        to: local.currentFieldValues
      )
      sharedChangedFields = changedFieldNames(
        from: baseFields,
        to: shared.currentFieldValues
      )
    } else {
      let differingFields = fieldChanges.map(\.fieldName).sorted()
      localChangedFields = differingFields
      sharedChangedFields = differingFields
    }

    let localSet = Set(localChangedFields)
    let sharedSet = Set(sharedChangedFields)
    let canMergeAutomatically: Bool
    switch comparison {
    case .localOnly, .sharedOnly:
      canMergeAutomatically = true
    case .divergent:
      canMergeAutomatically = baseFields != nil && localSet.isDisjoint(with: sharedSet)
    case .metadataUnavailable, .sameRevisionMismatch:
      canMergeAutomatically = false
    }

    return RevisionAnalysis(
      lastCommonRevision: lastCommonRevision,
      comparison: comparison,
      localChangedFields: localChangedFields,
      sharedChangedFields: sharedChangedFields,
      canMergeAutomatically: canMergeAutomatically
    )
  }

  private static func commonBaseFields(
    local: CollaborationRevisionMetadata,
    shared: CollaborationRevisionMetadata
  ) -> CollaborationFieldSnapshot? {
    let localBase = local.baseFieldValues
    let sharedBase = shared.baseFieldValues
    if !localBase.isEmpty, !sharedBase.isEmpty {
      return localBase == sharedBase ? localBase : nil
    }
    if !localBase.isEmpty { return localBase }
    if !sharedBase.isEmpty { return sharedBase }
    return nil
  }

  private static func changedFieldNames(
    from base: CollaborationFieldSnapshot,
    to current: CollaborationFieldSnapshot
  ) -> [String] {
    Set(base.keys).union(current.keys).filter { fieldName in
      (base[fieldName] ?? .null) != (current[fieldName] ?? .null)
    }.sorted()
  }
}
