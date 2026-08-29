import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingConflictResolutionCommitBoundaryTests: XCTestCase {
  func testKeepAcceptedCleanupCommitsBeforePostDiscardFailure() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeJournalURL())
    let ownershipRegistry = ConflictResolutionBoundaryOwnershipRegistry()
    ownershipRegistry.recordOwner(herdPublicID: herd.publicID, deviceID: "owner-device")
    let accountRegistry = ConflictResolutionBoundaryAccountRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: ownershipRegistry,
      accountOwnershipRegistry: accountRegistry
    )
    let base = ConflictResolutionBoundaryRepository()
    let resolver = ConflictResolutionBoundaryResolver(commitBeforeFailure: true)
    var ownerReferenceCleared = false
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: guardService,
      conflictResolver: resolver,
      discardedOwnerShareProvenanceCleanup: { herdPublicID in
        accountRegistry.clearEstablishedOwnerShare(for: herdPublicID)
        ownerReferenceCleared = true
      }
    )

    do {
      _ = try await repository.resolveBridgeConflict(
        herd: herd.toSummary(),
        keeping: .keepAcceptedShare,
        storageMode: .iCloud
      )
      XCTFail("Expected post-discard verification failure.")
    } catch {
      XCTAssertEqual(
        error as? ConflictResolutionBoundaryError,
        .postDiscardVerificationFailed
      )
    }

    XCTAssertEqual(resolver.callCount, 1)
    XCTAssertTrue(resolver.didInvokeCommitCallback)
    XCTAssertTrue(ownerReferenceCleared)
    XCTAssertFalse(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
    XCTAssertEqual(ownershipRegistry.ownership(for: herd.publicID), .participant)
    let unfinished = await journal.unfinishedOperations(for: herd.publicID)
    XCTAssertEqual(unfinished.count, 1)
    XCTAssertEqual(unfinished.first?.direction, .importFromBridge)
    XCTAssertEqual(
      unfinished.first?.bridgeLocation,
      HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
  }

  func testKeepAcceptedCleanupDoesNotRunWhenDiscardFailsBeforeCommit() async throws {
    let container = try TestSupport.makeModelContainer()
    let herd = try insertHerd(in: container.mainContext)
    let journal = HerdSharingBridgeJournal(fileURL: makeJournalURL())
    let ownershipRegistry = ConflictResolutionBoundaryOwnershipRegistry()
    ownershipRegistry.recordOwner(herdPublicID: herd.publicID, deviceID: "owner-device")
    let accountRegistry = ConflictResolutionBoundaryAccountRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: ownershipRegistry,
      accountOwnershipRegistry: accountRegistry
    )
    let base = ConflictResolutionBoundaryRepository()
    let resolver = ConflictResolutionBoundaryResolver(commitBeforeFailure: false)
    var ownerReferenceCleared = false
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: guardService,
      conflictResolver: resolver,
      discardedOwnerShareProvenanceCleanup: { herdPublicID in
        accountRegistry.clearEstablishedOwnerShare(for: herdPublicID)
        ownerReferenceCleared = true
      }
    )

    do {
      _ = try await repository.resolveBridgeConflict(
        herd: herd.toSummary(),
        keeping: .keepAcceptedShare,
        storageMode: .iCloud
      )
      XCTFail("Expected pre-commit discard failure.")
    } catch {
      XCTAssertEqual(error as? ConflictResolutionBoundaryError, .discardFailed)
    }

    XCTAssertEqual(resolver.callCount, 1)
    XCTAssertFalse(resolver.didInvokeCommitCallback)
    XCTAssertFalse(ownerReferenceCleared)
    XCTAssertTrue(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
  }

  private func insertHerd(in context: ModelContext) throws -> Herd {
    let herd = Herd(
      publicID: UUID(),
      name: "Conflict Commit Boundary Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herd)
    try context.save()
    return herd
  }

  private func makeJournalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("HerdSharingSyncJournal.json")
  }
}

private enum ConflictResolutionBoundaryError: Error, Equatable {
  case discardFailed
  case postDiscardVerificationFailed
}

@MainActor
private final class ConflictResolutionBoundaryResolver: HerdSharingBridgeConflictResolving {
  private let commitBeforeFailure: Bool
  private(set) var callCount = 0
  private(set) var didInvokeCommitCallback = false

  init(commitBeforeFailure: Bool) {
    self.commitBeforeFailure = commitBeforeFailure
  }

  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution
  ) async throws -> HerdSharingAccess {
    throw commitBeforeFailure
      ? ConflictResolutionBoundaryError.postDiscardVerificationFailed
      : ConflictResolutionBoundaryError.discardFailed
  }

  func resolveBridgeConflict(
    for herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution,
    discardedRelationshipDidCommit: @escaping @MainActor () -> Void
  ) async throws -> HerdSharingAccess {
    callCount += 1
    if commitBeforeFailure {
      discardedRelationshipDidCommit()
      didInvokeCommitCallback = true
      throw ConflictResolutionBoundaryError.postDiscardVerificationFailed
    }
    throw ConflictResolutionBoundaryError.discardFailed
  }
}

@MainActor
private final class ConflictResolutionBoundaryRepository: HerdSharingRepository {
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
    .conflictingStores(ownerHasActiveSystemShare: true, participantCount: 2)
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
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

private final class ConflictResolutionBoundaryOwnershipRegistry: HerdSharingOwnershipRecording {
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

private final class ConflictResolutionBoundaryAccountRegistry: HerdSharingAccountOwnershipRecording {
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
