//
//  HerdSharingBridgeConflictReport.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeConflictReport: Equatable {
  static let empty = HerdSharingBridgeConflictReport(
    existingLocalRecordUpdateCount: 0,
    preventedDeleteConflicts: []
  )

  let existingLocalRecordUpdateCount: Int
  let preventedDeleteConflicts: [HerdSharingBridgeConflictDetail]

  var preventedDeleteCount: Int { preventedDeleteConflicts.count }
  var hasConflicts: Bool { existingLocalRecordUpdateCount > 0 || preventedDeleteCount > 0 }

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

struct HerdSharingBridgeConflictDetail: Equatable, Identifiable {
  enum Kind: String, Equatable {
    case preventedSharedDelete
  }

  let id: UUID
  let kind: Kind
  let sourceEntityName: String
  let publicID: UUID
  let localModifiedAt: Date
  let sharedModifiedAt: Date

  init(
    kind: Kind,
    sourceEntityName: String,
    publicID: UUID,
    localModifiedAt: Date,
    sharedModifiedAt: Date
  ) {
    id = UUID()
    self.kind = kind
    self.sourceEntityName = sourceEntityName
    self.publicID = publicID
    self.localModifiedAt = localModifiedAt
    self.sharedModifiedAt = sharedModifiedAt
  }
}
