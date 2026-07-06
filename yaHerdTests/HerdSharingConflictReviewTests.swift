//
//  HerdSharingConflictReviewTests.swift
//  yaHerdTests
//

import XCTest

@testable import yaHerd

final class HerdSharingConflictReviewTests: XCTestCase {
  func testSummaryReportsExistingLocalUpdatesAndSkippedDeletes() {
    let review = HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Manual import",
      detectedAt: Date(timeIntervalSince1970: 30),
      existingLocalRecordUpdateCount: 2,
      preventedDeleteConflicts: [
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedHealthRecord",
          publicID: UUID(),
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedDeletedAt: Date(timeIntervalSince1970: 10)
        )
      ]
    )

    XCTAssertTrue(review.hasConflicts)
    XCTAssertEqual(review.preventedDeleteCount, 1)
    XCTAssertEqual(
      review.summary,
      "2 existing local record(s) were updated from shared data; 1 shared delete(s) were skipped because local records appear newer."
    )
  }

  func testDisplayEntityNameRemovesBridgePrefixes() {
    let conflict = HerdSharingPreventedDeleteConflict(
      sourceEntityName: "SharedPregnancyCheckRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 20),
      sharedDeletedAt: Date(timeIntervalSince1970: 10)
    )

    XCTAssertEqual(conflict.displayEntityName, "PregnancyCheck")
  }
}
