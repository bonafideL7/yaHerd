//
//  HerdSharingConflictResolution.swift
//  yaHerd
//

import Foundation

enum HerdSharingConflictResolutionChoice: String, Codable, Equatable {
  case keepLocalRecords
  case acceptSharedDeletes

  var displayName: String {
    switch self {
    case .keepLocalRecords:
      "Keep local records"
    case .acceptSharedDeletes:
      "Accept shared deletes"
    }
  }

  var summary: String {
    switch self {
    case .keepLocalRecords:
      "The local records were intentionally kept. Run shared-data sync so the bridge can re-export the kept local records."
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

  init(
    review: HerdSharingConflictReview,
    resolvedAt: Date = .now,
    choice: HerdSharingConflictResolutionChoice
  ) {
    self.reviewID = review.id
    self.resolvedAt = resolvedAt
    self.choice = choice
    self.sourceDescription = review.sourceDescription
    self.conflictSummary = review.summary
    self.preventedDeleteCount = review.preventedDeleteCount
    self.existingLocalRecordUpdateCount = review.existingLocalRecordUpdateCount
  }
}
