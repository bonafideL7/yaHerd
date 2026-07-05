//
//  HerdShareInvitationSummaryTests.swift
//  yaHerdTests
//

import Foundation
import XCTest
@testable import yaHerd

final class HerdShareInvitationSummaryTests: XCTestCase {
    func testDisplayValuesFallbackWhenCloudKitMetadataIsSparse() {
        let summary = HerdShareInvitationSummary(
            receivedAt: Date(timeIntervalSince1970: 0),
            containerIdentifier: nil,
            shareRecordName: "share-record",
            rootRecordName: nil,
            ownerDisplayName: "  "
        )

        XCTAssertEqual(summary.displayOwnerName, "Unknown Owner")
        XCTAssertEqual(summary.displayContainerIdentifier, "Unknown iCloud Container")
        XCTAssertEqual(summary.displayRootRecordName, "Unknown Root Record")
    }
}
