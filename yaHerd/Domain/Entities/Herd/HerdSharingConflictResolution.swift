//
//  HerdSharingConflictResolution.swift
//  yaHerd
//

import Foundation

enum HerdSharingConflictResolutionChoice: String, Codable, Equatable {
  case keepLocalRecords
  case restoreLocalFields
  case acceptSharedUpdates
  case acceptSharedDeletes

  var displayName: String {
    switch self {
    case .keepLocalRecords:
      "Keep local records"
    case .restoreLocalFields:
      "Restore local fields"
    case .acceptSharedUpdates:
      "Accept shared updates"
    case .acceptSharedDeletes:
      "Accept shared deletes"
    }
  }

  var summary: String {
    switch self {
    case .keepLocalRecords:
      "The local records were intentionally kept. Run shared-data sync so the bridge can re-export the kept local records."
    case .restoreLocalFields:
      "Selected pre-import local field values were restored into SwiftData. Run shared-data sync so the bridge can export those restored values."
    case .acceptSharedUpdates:
      "The shared updates that were already imported into SwiftData were accepted. No additional data write is required."
    case .acceptSharedDeletes:
      "The skipped shared deletes were accepted and the affected local SwiftData records were deleted. Run shared-data sync so the bridge stays aligned."
    }
  }
}

struct HerdSharingConflictResolution: Codable, Equatable, Identifiable {
  var id: String { reviewID }

  let reviewID: String
  let resolvedAt: Date
  let choice: HerdSharingConflictResolutionChoice
  let sourceDescription: String
  let conflictSummary: String
  let preventedDeleteCount: Int
  let existingLocalRecordUpdateCount: Int
  let updatedRecordConflicts: [HerdSharingUpdatedRecordConflict]
  let preventedDeleteConflicts: [HerdSharingPreventedDeleteConflict]
  let restoredLocalFieldSelections: [HerdSharingLocalFieldRestoreSelection]

  enum CodingKeys: String, CodingKey {
    case reviewID
    case resolvedAt
    case choice
    case sourceDescription
    case conflictSummary
    case preventedDeleteCount
    case existingLocalRecordUpdateCount
    case updatedRecordConflicts
    case preventedDeleteConflicts
    case restoredLocalFieldSelections
  }

  init(
    review: HerdSharingConflictReview,
    resolvedAt: Date = .now,
    choice: HerdSharingConflictResolutionChoice,
    restoredLocalFieldSelections: [HerdSharingLocalFieldRestoreSelection] = []
  ) {
    self.reviewID = review.id
    self.resolvedAt = resolvedAt
    self.choice = choice
    self.sourceDescription = review.sourceDescription
    self.conflictSummary = review.summary
    self.preventedDeleteCount = review.preventedDeleteCount
    self.existingLocalRecordUpdateCount = review.existingLocalRecordUpdateCount
    self.updatedRecordConflicts = review.updatedRecordConflicts
    self.preventedDeleteConflicts = review.preventedDeleteConflicts
    self.restoredLocalFieldSelections = restoredLocalFieldSelections
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    reviewID = try container.decode(String.self, forKey: .reviewID)
    resolvedAt = try container.decode(Date.self, forKey: .resolvedAt)
    choice = try container.decode(HerdSharingConflictResolutionChoice.self, forKey: .choice)
    sourceDescription = try container.decode(String.self, forKey: .sourceDescription)
    conflictSummary = try container.decode(String.self, forKey: .conflictSummary)
    preventedDeleteCount = try container.decode(Int.self, forKey: .preventedDeleteCount)
    existingLocalRecordUpdateCount = try container.decode(
      Int.self,
      forKey: .existingLocalRecordUpdateCount
    )
    updatedRecordConflicts =
      try container.decodeIfPresent(
        [HerdSharingUpdatedRecordConflict].self,
        forKey: .updatedRecordConflicts
      ) ?? []
    preventedDeleteConflicts =
      try container.decodeIfPresent(
        [HerdSharingPreventedDeleteConflict].self,
        forKey: .preventedDeleteConflicts
      ) ?? []
    restoredLocalFieldSelections =
      try container.decodeIfPresent(
        [HerdSharingLocalFieldRestoreSelection].self,
        forKey: .restoredLocalFieldSelections
      ) ?? []
  }

  var affectedRecordCount: Int {
    switch choice {
    case .keepLocalRecords:
      return existingLocalRecordUpdateCount + preventedDeleteCount
    case .restoreLocalFields, .acceptSharedUpdates:
      return max(existingLocalRecordUpdateCount, updatedRecordConflicts.count)
    case .acceptSharedDeletes:
      return max(preventedDeleteCount, preventedDeleteConflicts.count)
    }
  }

  var restoredLocalFieldCount: Int { restoredLocalFieldSelections.count }
}
