//
//  CloudKitShareAdapterTests.swift
//  yaHerdTests
//

import CloudKit
import XCTest
@testable import yaHerd

@MainActor
final class CloudKitShareAdapterTests: XCTestCase {
  func testSystemShareRegistrationUsesNeutralRequestAndOpaqueLookup() {
    let zoneID = CKRecordZone.ID(
      zoneName: "test-sharing-zone",
      ownerName: CKCurrentUserDefaultName
    )
    let share = CKShare(recordZoneID: zoneID)
    let systemShare = CloudKitSystemShare(
      title: "Test Herd",
      share: share,
      containerProvider: {
        preconditionFailure("Adapter registration must not construct or present CloudKit UI.")
      },
      persistUpdatedShareHandler: { _ in },
      stopSharingHandler: { _ in }
    )
    let adapter = CloudKitShareAdapter()

    let request = adapter.registerSystemShare(systemShare)

    XCTAssertEqual(request.title, "Test Herd")
    XCTAssertEqual(request.shareIdentifier, share.recordID.recordName)
    XCTAssertTrue(adapter.systemShare(for: request) === systemShare)

    adapter.discardSystemShare(for: request)

    XCTAssertNil(adapter.systemShare(for: request))
  }

  func testStopSharingNotifiesBeforeAndAfterBridgeCleanup() async throws {
    let zoneID = CKRecordZone.ID(
      zoneName: "test-stop-sharing-zone",
      ownerName: CKCurrentUserDefaultName
    )
    let share = CKShare(recordZoneID: zoneID)
    var events: [String] = []
    let systemShare = CloudKitSystemShare(
      title: "Test Herd",
      share: share,
      containerProvider: {
        preconditionFailure("Stop-sharing lifecycle tests must not construct or present CloudKit UI.")
      },
      persistUpdatedShareHandler: { _ in },
      stopSharingHandler: { _ in
        events.append("cleanup")
      }
    )
    systemShare.observeStopSharing { event in
      switch event {
      case .started:
        events.append("started")
      case .completed:
        events.append("completed")
      }
    }

    try await systemShare.stopSharing()

    XCTAssertEqual(events, ["started", "cleanup", "completed"])
  }

  func testStopSharingDoesNotEmitCompletionWhenBridgeCleanupFails() async {
    let zoneID = CKRecordZone.ID(
      zoneName: "test-stop-sharing-failure-zone",
      ownerName: CKCurrentUserDefaultName
    )
    let share = CKShare(recordZoneID: zoneID)
    var events: [String] = []
    let expectedError = HerdSharingActionError.bridgeConsistencyFailed("purge failed")
    let systemShare = CloudKitSystemShare(
      title: "Test Herd",
      share: share,
      containerProvider: {
        preconditionFailure("Stop-sharing lifecycle tests must not construct or present CloudKit UI.")
      },
      persistUpdatedShareHandler: { _ in },
      stopSharingHandler: { _ in
        events.append("cleanup")
        throw expectedError
      }
    )
    systemShare.observeStopSharing { event in
      switch event {
      case .started:
        events.append("started")
      case .completed:
        events.append("completed")
      }
    }

    do {
      try await systemShare.stopSharing()
      XCTFail("Expected failed bridge cleanup to propagate.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, expectedError)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(events, ["started", "cleanup"])
  }
}
