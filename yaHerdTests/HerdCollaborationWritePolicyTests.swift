//
//  HerdCollaborationWritePolicyTests.swift
//  yaHerdTests
//

import XCTest

@testable import yaHerd

final class HerdCollaborationWritePolicyTests: XCTestCase {
  func testNoKnownSharedAccessAllowsLocalWrites() throws {
    let policy = HerdCollaborationWritePolicy()

    XCTAssertNoThrow(try policy.validateCanWrite(reason: .animal))
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
  }

  func testOwnerPrivateStoreAllowsLocalWrites() throws {
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: .ownerPrivateStore(participantCount: 2))

    XCTAssertNoThrow(try policy.validateCanWrite(reason: .pasture))
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
  }

  func testReadWriteSharedStoreAllowsLocalWrites() throws {
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: .acceptedSharedStore(permission: .readWrite, participantCount: 2))

    XCTAssertNoThrow(try policy.validateCanWrite(reason: .working))
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
  }

  func testReadOnlySharedStoreBlocksLocalWrites() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: .acceptedSharedStore(permission: .readOnly, participantCount: 2))

    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .readOnlySharedHerd(reason: .animal, permission: .readOnly)
      )
    }
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertEqual(policy.snapshot.lastBlockedMutationReason, .animal)
  }

  func testUnknownAcceptedSharedStoreBlocksLocalWrites() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: .acceptedSharedStore(permission: .unknown, participantCount: nil))

    XCTAssertFalse(policy.canWrite(reason: .fieldCheck))
    XCTAssertEqual(policy.snapshot.lastBlockedMutationReason, .fieldCheck)
  }
}
