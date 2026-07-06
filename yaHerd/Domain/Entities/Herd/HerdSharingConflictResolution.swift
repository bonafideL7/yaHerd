//
//  HerdSharingConflictResolution.swift
//  yaHerd
//

import Foundation

enum HerdSharingConflictResolutionChoice: String, Codable, Equatable {
  case keepLocalRecords

  var displayName: String {
    switch self {
    case .keepLocalRecords:
      "Keep local records"
    }
  }

  var summary: String {
    switch self {
    case .keepLocalRecords:
      "The local records were intentionally kept. Run shared-data sync so the bridge can re-export the kept local records."
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
