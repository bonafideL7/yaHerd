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
  func testInterruptedShareCannotResumeForForeignDeviceRevision() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Foreign Resume Herd",
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

    let guardService = HerdSharingCreationStateGuard(
      context: context,
      journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
      ownershipRegistry: ResumeOwnershipRegistry()
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )

    XCTAssertEqual(access.creationState, .notOwnedByCurrentDevice)
  }

  private func makeTemporaryJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}

private final class ResumeOwnershipRegistry: HerdSharingOwnershipRecording {
  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? {
    nil
  }

  func recordOwner(herdPublicID: UUID, deviceID: String) {}

  func recordParticipant(herdPublicID: UUID) {}
}
