//
//  HerdSharingCreationStateGuardTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingCreationStateGuardTests: XCTestCase {
  func testNewShareIsReadyForUniqueLocallyOwnedHerdWithoutBridgeState() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .ready)
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  func testActiveOwnerShareRoutesToManagement() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      )
    )

    XCTAssertEqual(access.creationState, .existingOwnerShare)
    XCTAssertFalse(access.creationState.allowsNewShare)
  }

  func testAcceptedParticipantShareRoutesToSynchronization() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .acceptedSharedStore(
        permission: .readWrite,
        participantCount: 2
      )
    )

    XCTAssertEqual(access.creationState, .acceptedParticipantShare)
    XCTAssertEqual(registry.ownership(for: herd.publicID), .participant)
  }

  func testOwnerBridgeWithoutSystemShareIsUnresolved() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )

    XCTAssertEqual(access.creationState, .unresolvedBridgeRecord)
  }

  func testUnfinishedBridgeOperationBlocksNewShare() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let journalURL = makeTemporaryJournalURL()
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    _ = try await journal.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: "accepted shared store"
    )
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: RecordingHerdSharingOwnershipRegistry()
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .pendingBridgeOperation)
  }

  func testParticipantOwnershipMarkerBlocksShareWhenBridgeHasNotLoadedYet() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let registry = RecordingHerdSharingOwnershipRegistry()
    registry.recordParticipant(herdPublicID: herd.publicID)
    let guardService = makeGuard(
      context: container.mainContext,
      registry: registry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .notOwnedByCurrentDevice)
  }

  func testForeignRevisionDeviceBlocksNewShare() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = try insertHerd(in: context)
    context.insert(
      CollaborationRevisionRecord(
        key: herd.collaborationKey,
        herdPublicID: herd.publicID,
        metadata: CollaborationRevisionMetadata(
          modifiedAt: herd.updatedAt,
          revision: 1,
          modifiedByParticipantID: "participant-other",
          modifiedByDeviceID: "device-other",
          baseRevision: 0,
          baseFieldValues: [:],
          currentFieldValues: [:],
          isDeleted: false
        )
      )
    )
    try context.save()
    let guardService = makeGuard(context: context)

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .notOwnedByCurrentDevice)
  }

  func testValidationRejectsExistingOwnerShareBeforeCloudKitCreation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .ownerPrivateStore(
          participantCount: 2,
          hasActiveSystemShare: true
        )
      )
      XCTFail("Expected an existing owner share to be rejected.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareAlreadyExists)
    }
  }

  func testValidationRejectsAcceptedParticipantShareBeforeCloudKitCreation() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    do {
      _ = try await guardService.validateNewShare(
        herd: herd.toSummary(),
        access: .acceptedSharedStore(
          permission: .readOnly,
          participantCount: 2
        )
      )
      XCTFail("Expected an accepted participant share to be rejected.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .acceptedParticipantShareCannotReshare)
    }
  }

  private func insertHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Guard Test Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try context.save()
    return herd
  }

  private func makeGuard(
    context: ModelContext,
    registry: RecordingHerdSharingOwnershipRegistry = RecordingHerdSharingOwnershipRegistry()
  ) -> HerdSharingCreationStateGuard {
    HerdSharingCreationStateGuard(
      context: context,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: registry
    )
  }

  private func makeTemporaryJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}

private final class RecordingHerdSharingOwnershipRegistry: HerdSharingOwnershipRecording {
  private var ownershipByHerdID: [UUID: HerdSharingOwnership] = [:]

  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    ownershipByHerdID[herdPublicID]
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {
    ownershipByHerdID[herdPublicID] = .owner(deviceID: deviceID)
  }

  func recordParticipant(herdPublicID: UUID) {
    ownershipByHerdID[herdPublicID] = .participant
  }
}
