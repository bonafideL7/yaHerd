import CloudKit
import XCTest

@testable import yaHerd

final class HerdSharingAcceptedConflictDiscardTests: XCTestCase {
  func testPresentParticipantRelationshipDiscardsOnlyExactVerifiedZone() throws {
    let recordID = CKRecord.ID(
      recordName: "accepted-root",
      zoneID: CKRecordZone.ID(zoneName: "accepted-zone", ownerName: "owner-account")
    )

    let zoneID = try HerdSharingAcceptedConflictDiscardPlan.zoneID(
      for: recordID,
      remoteStatus: .present(permission: .readOnly)
    )

    XCTAssertEqual(zoneID, recordID.zoneID)
  }

  func testReadWriteParticipantRelationshipDiscardsOnlyExactVerifiedZone() throws {
    let recordID = CKRecord.ID(
      recordName: "accepted-root",
      zoneID: CKRecordZone.ID(zoneName: "accepted-zone", ownerName: "owner-account")
    )

    let zoneID = try HerdSharingAcceptedConflictDiscardPlan.zoneID(
      for: recordID,
      remoteStatus: .present(permission: .readWrite)
    )

    XCTAssertEqual(zoneID, recordID.zoneID)
  }

  func testAlreadyAbsentParticipantRelationshipStillCleansOnlyExactVerifiedZone() throws {
    let recordID = CKRecord.ID(
      recordName: "accepted-root",
      zoneID: CKRecordZone.ID(zoneName: "accepted-zone", ownerName: "owner-account")
    )

    let zoneID = try HerdSharingAcceptedConflictDiscardPlan.zoneID(
      for: recordID,
      remoteStatus: .absent
    )

    XCTAssertEqual(zoneID, recordID.zoneID)
  }

  func testUnknownParticipantPermissionCannotAuthorizeDestructiveConflictResolution() {
    let recordID = CKRecord.ID(
      recordName: "accepted-root",
      zoneID: CKRecordZone.ID(zoneName: "accepted-zone", ownerName: "owner-account")
    )

    XCTAssertThrowsError(
      try HerdSharingAcceptedConflictDiscardPlan.zoneID(
        for: recordID,
        remoteStatus: .present(permission: .unknown)
      )
    ) { error in
      guard let actionError = error as? HerdSharingActionError,
            case .bridgeConsistencyFailed = actionError
      else {
        return XCTFail("Expected a bridge consistency failure, got \(error)")
      }
    }
  }
}
