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
  let preventedDeleteConflicts: [HerdSharingPreventedDeleteConflict]

  var preventedDeleteCount: Int { preventedDeleteConflicts.count }
  var hasConflicts: Bool { existingLocalRecordUpdateCount > 0 || preventedDeleteCount > 0 }

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
      return "Choose Keep Local Records to preserve local edits, or Accept Shared Deletes to delete the affected local records by public ID."
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
