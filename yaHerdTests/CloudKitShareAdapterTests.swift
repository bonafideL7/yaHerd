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
      container: CKContainer(identifier: ModelContainerFactory.cloudKitContainerIdentifier),
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
}
