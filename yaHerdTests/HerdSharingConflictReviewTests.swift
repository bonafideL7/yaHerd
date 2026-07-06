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
  func testPreventedDeleteEntitySummariesSortByCountThenName() {
    let review = HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Manual sync",
      detectedAt: Date(timeIntervalSince1970: 30),
      existingLocalRecordUpdateCount: 0,
      preventedDeleteConflicts: [
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedPastureRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedDeletedAt: Date(timeIntervalSince1970: 10)
        ),
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          localModifiedAt: Date(timeIntervalSince1970: 21),
          sharedDeletedAt: Date(timeIntervalSince1970: 11)
        ),
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
          localModifiedAt: Date(timeIntervalSince1970: 22),
          sharedDeletedAt: Date(timeIntervalSince1970: 12)
        ),
      ]
    )

    XCTAssertEqual(
      review.preventedDeleteEntitySummaries,
      [
        HerdSharingPreventedDeleteEntitySummary(displayEntityName: "Animal", count: 2),
        HerdSharingPreventedDeleteEntitySummary(displayEntityName: "Pasture", count: 1),
      ]
    )
    XCTAssertEqual(review.latestLocalModifiedAt, Date(timeIntervalSince1970: 22))
    XCTAssertEqual(review.earliestSharedDeletedAt, Date(timeIntervalSince1970: 10))
    XCTAssertEqual(
      review.recommendedAction,
      "Review skipped shared deletes before making more edits to the affected records."
    )
  }

}
