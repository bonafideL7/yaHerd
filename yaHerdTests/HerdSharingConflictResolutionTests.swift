//
//  HerdSharingConflictResolutionTests.swift
//  yaHerdTests
//

import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingConflictResolutionTests: XCTestCase {
  func testResolutionCopiesReviewSummaryMetadata() {
    let review = HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Manual sync",
      detectedAt: Date(timeIntervalSince1970: 10),
      existingLocalRecordUpdateCount: 2,
      preventedDeleteConflicts: [
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          localModifiedAt: Date(timeIntervalSince1970: 9),
          sharedDeletedAt: Date(timeIntervalSince1970: 8)
        )
      ]
    )

    let resolution = HerdSharingConflictResolution(
      review: review,
      resolvedAt: Date(timeIntervalSince1970: 20),
      choice: .keepLocalRecords
    )

    XCTAssertEqual(resolution.id, review.id)
    XCTAssertEqual(resolution.sourceDescription, "Manual sync")
    XCTAssertEqual(resolution.existingLocalRecordUpdateCount, 2)
    XCTAssertEqual(resolution.preventedDeleteCount, 1)
    XCTAssertEqual(resolution.choice.displayName, "Keep local records")
    XCTAssertTrue(resolution.choice.summary.contains("local records were intentionally kept"))
  }
  func testRestoreLocalFieldsResolutionChoiceHasUserFacingText() {
    XCTAssertEqual(
      HerdSharingConflictResolutionChoice.restoreLocalFields.displayName, "Restore local fields")
    XCTAssertTrue(
      HerdSharingConflictResolutionChoice.restoreLocalFields.summary.contains(
        "Selected pre-import local field values")
    )
  }

}
