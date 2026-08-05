//
//  DeferredHerdSharingStateGuardTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class DeferredHerdSharingStateGuardTests: XCTestCase {
  func testRepositoryRejectsExistingOwnerShareBeforeCallingBaseStart() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      )
    )
    let repository = makeRepository(
      context: container.mainContext,
      base: base
    )

    do {
      _ = try await repository.startSharing(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected the repository guard to reject the existing owner share.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareAlreadyExists)
    }

    XCTAssertEqual(base.startSharingCallCount, 0)
  }

  func testRepositoryRejectsAcceptedParticipantBeforeCallingBaseStart() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .acceptedSharedStore(
        permission: .readWrite,
        participantCount: 2
      )
    )
    let repository = makeRepository(
      context: container.mainContext,
      base: base
    )

    do {
      _ = try await repository.startSharing(
        herd: herd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected the repository guard to reject the participant share.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .acceptedParticipantShareCannotReshare)
    }

    XCTAssertEqual(base.startSharingCallCount, 0)
  }

  func testRepositoryDelegatesStartAfterAllGuardChecksPass() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(access: .localOwnerBridgePending)
    let repository = makeRepository(
      context: container.mainContext,
      base: base
    )

    let result = try await repository.startSharing(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(result.title, "Base Start")
  }

  func testRepositoryOpensExistingOwnerShareThroughBaseStartPath() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      )
    )
    let repository = makeRepository(
      context: container.mainContext,
      base: base
    )

    let result = try await repository.manageExistingShare(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(result.title, "Base Start")
  }

  func testRepositoryResumesInterruptedShareFromExistingBridgeRoot() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let base = RecordingGuardedBaseRepository(
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )
    let repository = makeRepository(
      context: container.mainContext,
      base: base
    )

    let result = try await repository.manageExistingShare(
      herd: herd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(result.title, "Base Start")
  }

  private func makeRepository(
    context: ModelContext,
    base: RecordingGuardedBaseRepository
  ) -> DeferredCoreDataHerdSharingRepository {
    DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: HerdSharingCreationStateGuard(
        context: context,
        journal: HerdSharingBridgeJournal(fileURL: makeTemporaryJournalURL()),
        ownershipRegistry: RecordingDeferredGuardOwnershipRegistry()
      )
    )
  }

  private func insertHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Repository Guard Herd",
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

@MainActor
private final class RecordingGuardedBaseRepository: HerdSharingRepository {
  let access: HerdSharingAccess
  private(set) var startSharingCallCount = 0

  init(access: HerdSharingAccess) {
    self.access = access
  }

  func fetchSharingReadiness(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) -> HerdSharingReadiness {
    .sharingAdapterAvailable
  }

  func fetchSharingAccess(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess {
    access
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    startSharingCallCount += 1
    return HerdSharingActionResult(
      title: "Base Start",
      message: "Base repository was called."
    )
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }
}

private final class RecordingDeferredGuardOwnershipRegistry: HerdSharingOwnershipRecording {
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
