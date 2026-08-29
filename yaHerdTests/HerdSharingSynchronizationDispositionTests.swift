import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingSynchronizationDispositionTests: XCTestCase {
  func testCleanReadOnlyAcceptedShareUsesImportOnlySynchronization() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    let disposition = try await guardService.synchronizationDisposition(
      herd: herd.toSummary(),
      access: .acceptedSharedStore(permission: .readOnly, participantCount: 2)
    )

    XCTAssertEqual(disposition, .importOnly)
  }

  func testCleanReadWriteAcceptedShareKeepsFullSynchronization() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let guardService = makeGuard(context: container.mainContext)

    let disposition = try await guardService.synchronizationDisposition(
      herd: herd.toSummary(),
      access: .acceptedSharedStore(permission: .readWrite, participantCount: 2)
    )

    XCTAssertEqual(disposition, .fullSync)
  }

  private func insertHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Synchronization Disposition Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try PersistenceLog.save(
      context,
      operation: "HerdSharingSynchronizationDispositionTests.insertHerd"
    )
    return herd
  }

  private func makeGuard(context: ModelContext) -> HerdSharingCreationStateGuard {
    HerdSharingCreationStateGuard(
      context: context,
      journal: HerdSharingBridgeJournal(
        fileURL: FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString, isDirectory: true)
          .appendingPathComponent("HerdSharingSyncJournal.json")
      ),
      ownershipRegistry: SynchronizationDispositionOwnershipRegistry(),
      accountOwnershipRegistry: SynchronizationDispositionAccountOwnershipRegistry()
    )
  }
}

private final class SynchronizationDispositionOwnershipRegistry: HerdSharingOwnershipRecording {
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

  func clearOwnership(for herdPublicID: UUID) {
    ownershipByHerdID.removeValue(forKey: herdPublicID)
  }
}

private final class SynchronizationDispositionAccountOwnershipRegistry:
  HerdSharingAccountOwnershipRecording
{
  private var establishedHerdIDs: Set<UUID> = []

  func hasEstablishedOwnerShare(for herdPublicID: UUID) -> Bool {
    establishedHerdIDs.contains(herdPublicID)
  }

  func recordEstablishedOwnerShare(for herdPublicID: UUID) {
    establishedHerdIDs.insert(herdPublicID)
  }

  func clearEstablishedOwnerShare(for herdPublicID: UUID) {
    establishedHerdIDs.remove(herdPublicID)
  }
}
