//
//  HerdSharingBridgeConflictReportTests.swift
//  yaHerdTests
//

import XCTest

@testable import yaHerd

final class HerdSharingBridgeConflictReportTests: XCTestCase {
  func testEmptyReportHasNoConflicts() {
    let report = HerdSharingBridgeConflictReport.empty

    XCTAssertFalse(report.hasConflicts)
    XCTAssertEqual(report.summary, "No shared-data conflicts were detected.")
  }

  func testExistingLocalRecordUpdateCountIsReported() {
    let report = HerdSharingBridgeConflictReport(
      existingLocalRecordUpdateCount: 3,
      preventedDeleteConflicts: []
    )

    XCTAssertTrue(report.hasConflicts)
    XCTAssertEqual(
      report.summary,
      "3 existing local record(s) were updated from shared data."
    )
  }

  func testPreventedDeletesAreReported() {
    let detail = HerdSharingBridgeConflictDetail(
      kind: .preventedSharedDelete,
      sourceEntityName: SharedHealthRecord.entityName,
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 20),
      sharedModifiedAt: Date(timeIntervalSince1970: 10)
    )
    let report = HerdSharingBridgeConflictReport(
      existingLocalRecordUpdateCount: 0,
      preventedDeleteConflicts: [detail]
    )

    XCTAssertTrue(report.hasConflicts)
    XCTAssertEqual(
      report.summary,
      "1 shared delete(s) were skipped because local records appear newer."
    )
  }
}
