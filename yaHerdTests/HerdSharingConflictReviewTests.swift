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
      updatedRecordConflicts: [
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedModifiedAt: Date(timeIntervalSince1970: 25)
        ),
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedHealthRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
          localModifiedAt: Date(timeIntervalSince1970: 21),
          sharedModifiedAt: Date(timeIntervalSince1970: 26)
        ),
      ],
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
    XCTAssertEqual(review.updatedRecordConflictCount, 2)
    XCTAssertEqual(review.preventedDeleteCount, 1)
    XCTAssertEqual(
      review.summary,
      "2 existing local record(s) were updated from shared data; 1 shared delete(s) were skipped because local records appear newer."
    )
  }

  func testUpdatedRecordEntitySummariesSortByCountThenName() {
    let review = HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Manual sync",
      detectedAt: Date(timeIntervalSince1970: 30),
      existingLocalRecordUpdateCount: 3,
      updatedRecordConflicts: [
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedPastureRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedModifiedAt: Date(timeIntervalSince1970: 30)
        ),
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          localModifiedAt: Date(timeIntervalSince1970: 21),
          sharedModifiedAt: Date(timeIntervalSince1970: 31)
        ),
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
          localModifiedAt: Date(timeIntervalSince1970: 22),
          sharedModifiedAt: Date(timeIntervalSince1970: 32)
        ),
      ],
      preventedDeleteConflicts: []
    )

    XCTAssertEqual(
      review.updatedRecordEntitySummaries,
      [
        HerdSharingUpdatedRecordEntitySummary(displayEntityName: "Animal", count: 2),
        HerdSharingUpdatedRecordEntitySummary(displayEntityName: "Pasture", count: 1),
      ]
    )
    XCTAssertEqual(
      review.recommendedAction,
      "Review the updated record IDs by entity. Keep local records only if the shared update was unexpected."
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
      "Choose Keep Local Records to preserve local edits, or Accept Shared Deletes to delete the affected local records by public ID."
    )
  }

  func testUpdatedRecordConflictDecodesMissingFieldChangesAsEmpty() throws {
    let json = """
    {
      "sourceEntityName": "SharedAnimalRecord",
      "publicID": "00000000-0000-0000-0000-000000000004",
      "localModifiedAt": 20,
      "sharedModifiedAt": 30
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let conflict = try decoder.decode(HerdSharingUpdatedRecordConflict.self, from: json)

    XCTAssertEqual(conflict.changedFieldCount, 0)
    XCTAssertTrue(conflict.fieldChanges.isEmpty)
  }

  func testUpdatedRecordConflictStoresFieldChanges() {
    let conflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedAnimalRecord",
      publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
      localModifiedAt: Date(timeIntervalSince1970: 20),
      sharedModifiedAt: Date(timeIntervalSince1970: 30),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "tagNumber",
          localValueDescription: "12",
          sharedValueDescription: "14"
        )
      ]
    )

    XCTAssertEqual(conflict.changedFieldCount, 1)
    XCTAssertEqual(conflict.fieldChanges.first?.fieldName, "tagNumber")
  }

}
