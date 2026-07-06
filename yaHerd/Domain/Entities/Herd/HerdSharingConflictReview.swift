//
//  HerdSharingConflictReview.swift
//  yaHerd
//

import Foundation

struct HerdSharingConflictReview: Equatable {
  let title: String
  let sourceDescription: String
  let detectedAt: Date
  let existingLocalRecordUpdateCount: Int
  let preventedDeleteConflicts: [HerdSharingPreventedDeleteConflict]

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

struct HerdSharingPreventedDeleteConflict: Equatable, Identifiable {
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
