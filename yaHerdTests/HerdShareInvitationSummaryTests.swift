//
//  HerdShareInvitationSummaryTests.swift
//  yaHerdTests
//

import Foundation
import XCTest
@testable import yaHerd

final class HerdShareInvitationSummaryTests: XCTestCase {
  func testDisplayValuesFallbackWhenInvitationDetailsAreSparse() {
    let summary = HerdShareInvitationSummary(
      receivedAt: Date(timeIntervalSince1970: 0),
      containerIdentifier: nil,
      shareRecordName: "share-record",
      rootRecordName: nil,
      ownerDisplayName: "  "
    )

    XCTAssertEqual(summary.displayOwnerName, "Unknown Owner")
    XCTAssertEqual(summary.displayContainerIdentifier, "Unknown Sharing Container")
    XCTAssertEqual(summary.displayRootRecordName, "Unknown Root Record")
  }

  func testNeutralInvitationBuildsSummaryWithoutPlatformTypes() {
    let invitation = HerdShareInvitation(
      token: HerdShareToken(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!),
      receivedAt: Date(timeIntervalSince1970: 10),
      containerIdentifier: "iCloud.com.example.yaHerd",
      shareIdentifier: "share-record",
      rootIdentifier: "herd-root",
      ownerIdentifier: "owner-record",
      ownerDisplayName: "Herd Owner",
      participantRole: .privateUser,
      permission: .readWrite,
      status: .pending,
      shareURL: URL(string: "https://www.icloud.com/share/example")
    )

    XCTAssertEqual(invitation.summary.id, invitation.id)
    XCTAssertEqual(invitation.summary.shareRecordName, "share-record")
    XCTAssertEqual(invitation.summary.rootRecordName, "herd-root")
    XCTAssertEqual(invitation.summary.displayOwnerName, "Herd Owner")
    XCTAssertEqual(invitation.participantRole, .privateUser)
    XCTAssertEqual(invitation.permission, .readWrite)
    XCTAssertEqual(invitation.status, .pending)
  }
}
