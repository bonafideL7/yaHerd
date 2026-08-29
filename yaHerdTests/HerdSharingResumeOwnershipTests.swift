//
//  HerdSharingResumeOwnershipTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingResumeOwnershipTests: XCTestCase {
  func testInterruptedShareOnReplacementDeviceRequiresExplicitOwnershipConfirmation() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Replacement Device Resume Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    context.insert(
      CollaborationRevisionRecord(
        key: herd.collaborationKey,
        herdPublicID: herd.publicID,
        metadata: CollaborationRevisionMetadata(
          modifiedAt: herd.updatedAt,
          revision: 1,
          modifiedByParticipantID: "participant-from-previous-installation",
          modifiedByDeviceID: "device-from-previous-installation",
          baseRevision: 0,
          baseFieldValues: [:],
          currentFieldValues: [:],
          isDeleted: false
        )
      )
    )
    try context.save()

    let registry = ResumeOwnershipRegistry()
    let guardService = HerdSharingCreationStateGuard(
      context: context,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: registry
    )
    let rawAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: nil,
      hasActiveSystemShare: false
    )

    let before = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: rawAccess
    )
    XCTAssertEqual(before.creationState, .ownershipConfirmationRequired)

    let after = try await guardService.confirmLocalOwnership(
      herd: herd.toSummary(),
      access: rawAccess
    )
    XCTAssertEqual(after.creationState, .unresolvedBridgeRecord)
    XCTAssertEqual(
      registry.ownership(for: herd.publicID),
      .owner(deviceID: CollaborationIdentityProvider.current().deviceID)
    )
  }

  private func makeTemporaryJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}
private final class ResumeOwnershipRegistry: HerdSharingOwnershipRecording {
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

// MARK: - Synchronization guard regression coverage
