//
//  HerdSharingConflictingStoreTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingConflictingStoreTests: XCTestCase {
  func testConflictingStoresBlockShareCreationAndLocalMutations() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let access = HerdSharingAccess.conflictingStores(
      ownerHasActiveSystemShare: true,
      participantCount: 2
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: ConflictingStoreOwnershipRegistry()
    )

    let evaluatedAccess = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: access
    )

    XCTAssertEqual(evaluatedAccess.creationState, .conflictingBridgeRecords)
    XCTAssertFalse(evaluatedAccess.creationState.allowsNewShare)
    XCTAssertFalse(evaluatedAccess.allowsLocalMutations)
    XCTAssertEqual(evaluatedAccess.bridgeLocation, .conflictingStores)
  }

  func testConflictingStoresAreRejectedBeforeNewShareCreation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: ConflictingStoreOwnershipRegistry()
    )

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .conflictingStores(
          ownerHasActiveSystemShare: false,
          participantCount: 2
        )
      )
      XCTFail("Expected conflicting bridge records to block share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .unresolvedSharingBridge)
    }
  }

  func testWritePolicyReportsConflictingStoresAsBlocked() {
    let policy = HerdCollaborationWritePolicy()
    policy.update(
      access: .conflictingStores(
        ownerHasActiveSystemShare: true,
        participantCount: 2
      )
    )

    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertTrue(policy.snapshot.statusDescription.contains("both owner and accepted shared"))
  }

  private func insertHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Conflicting Store Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try context.save()
    return herd
  }

  private func makeTemporaryJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}

private final class ConflictingStoreOwnershipRegistry: HerdSharingOwnershipRecording {
  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    nil
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {}

  func recordParticipant(herdPublicID: UUID) {}
}
