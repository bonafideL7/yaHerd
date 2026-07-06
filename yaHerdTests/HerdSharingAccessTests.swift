//
//  HerdSharingAccessTests.swift
//  yaHerdTests
//

import XCTest

@testable import yaHerd

final class HerdSharingAccessTests: XCTestCase {
  func testOwnerCanExportLocalChangesToBridge() {
    let access = HerdSharingAccess.ownerPrivateStore(participantCount: 2)

    XCTAssertTrue(access.canExportLocalChangesToBridge)
    XCTAssertEqual(access.locationDescription, "owner private store")
    XCTAssertEqual(access.permissionDescription, "owner")
    XCTAssertEqual(access.participantDescription, "2 participants")
  }

  func testReadOnlySharedParticipantCannotExportLocalChangesToBridge() {
    let access = HerdSharingAccess.acceptedSharedStore(
      permission: .readOnly,
      participantCount: 2
    )

    XCTAssertFalse(access.canExportLocalChangesToBridge)
    XCTAssertEqual(access.locationDescription, "accepted shared store")
    XCTAssertEqual(access.permissionDescription, "read-only")
  }

  func testUnknownSharedPermissionDoesNotExportLocalChangesToBridge() {
    let access = HerdSharingAccess.acceptedSharedStore(
      permission: .unknown,
      participantCount: nil
    )

    XCTAssertFalse(access.canExportLocalChangesToBridge)
    XCTAssertEqual(access.participantDescription, "unknown participants")
  }

  func testReadWriteSharedParticipantCanExportLocalChangesToBridge() {
    let access = HerdSharingAccess.acceptedSharedStore(
      permission: .readWrite,
      participantCount: 3
    )

    XCTAssertTrue(access.canExportLocalChangesToBridge)
    XCTAssertEqual(access.permissionDescription, "read/write")
    XCTAssertEqual(access.participantDescription, "3 participants")
  }
}
