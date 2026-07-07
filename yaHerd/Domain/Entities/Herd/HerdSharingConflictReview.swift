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
    updatedRecordConflicts = try container.decodeIfPresent(
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
      return "Choose Keep Local Records to preserve local edits, or Accept Shared Deletes to delete the affected local records by public ID."
    }

    if updatedRecordConflictCount > 0 {
      return "Review the updated record IDs by entity. Keep local records only if the shared update was unexpected."
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

struct HerdSharingUpdatedRecordFieldChange: Codable, Equatable, Identifiable {
  var id: String { fieldName }

  let fieldName: String
  let localValueDescription: String
  let sharedValueDescription: String
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
    fieldChanges = try container.decodeIfPresent(
      [HerdSharingUpdatedRecordFieldChange].self,
      forKey: .fieldChanges
    ) ?? []
  }

  var changedFieldCount: Int { fieldChanges.count }

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
