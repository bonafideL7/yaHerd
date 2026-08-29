//
//  GatedHerdSharingRepositoryTests.swift
//  yaHerdTests
//

import CloudKit
@preconcurrency import CoreData
import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class GatedHerdSharingRepositoryTests: XCTestCase {
  func testManageExistingShareDelegatesThroughSynchronizationGate() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(base: base, mutationGate: gate)

    let result = try await repository.manageExistingShare(
      herd: makeHerd(),
      storageMode: .iCloud
    )

    XCTAssertEqual(base.manageExistingShareCallCount, 1)
    XCTAssertEqual(result.title, "Managed")
  }

  func testManageExistingShareIsBlockedDuringPublicIDRepair() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(base: base, mutationGate: gate)
    let repairToken = try gate.beginPublicIDRepair()
    defer { gate.endPublicIDRepair(repairToken) }

    do {
      _ = try await repository.manageExistingShare(
        herd: makeHerd(),
        storageMode: .iCloud
      )
      XCTFail("Expected share management to be blocked during public-ID repair.")
    } catch {
      XCTAssertEqual(base.manageExistingShareCallCount, 0)
    }
  }

  func testOwnershipConfirmationRecoveryAndBridgeResolutionUseSynchronizationGate() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let base = GatedSharingRecordingRepository()
    let herd = makeHerd()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    referenceStore.record(makeRemoteOwnerShareReference(), for: herd.publicID)
    let participantReferenceStore = RecordingAcceptedParticipantReferenceStore()
    participantReferenceStore.record(makeAcceptedParticipantReference(), for: herd.publicID)
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: StubRemoteOwnerShareVerifier(status: .absent),
      acceptedParticipantReferenceStore: participantReferenceStore,
      remoteAcceptedParticipantVerifier: StubRemoteAcceptedParticipantVerifier(status: .absent)
    )

    _ = try await repository.confirmLocalHerdOwnership(
      herd: herd,
      storageMode: .iCloud
    )
    _ = try await repository.resetStaleOwnerSharingState(
      herd: herd,
      storageMode: .iCloud
    )
    _ = try await repository.detachStaleParticipantState(
      herd: herd,
      storageMode: .iCloud
    )
    _ = try await repository.resolveBridgeConflict(
      herd: herd,
      keeping: .keepAcceptedShare,
      storageMode: .iCloud
    )

    XCTAssertEqual(base.confirmOwnershipCallCount, 1)
    XCTAssertEqual(base.resetStaleOwnerCallCount, 1)
    XCTAssertEqual(base.detachStaleParticipantCallCount, 1)
    XCTAssertEqual(base.resolveBridgeConflictCallCount, 1)
  }

  func testRecoveryMutationsAreBlockedDuringPublicIDRepair() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(base: base, mutationGate: gate)
    let repairToken = try gate.beginPublicIDRepair()
    defer { gate.endPublicIDRepair(repairToken) }
    let herd = makeHerd()

    do {
      _ = try await repository.resetStaleOwnerSharingState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected stale owner reset to be blocked during public-ID repair.")
    } catch {
      XCTAssertEqual(base.resetStaleOwnerCallCount, 0)
    }

    do {
      _ = try await repository.detachStaleParticipantState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected stale participant detach to be blocked during public-ID repair.")
    } catch {
      XCTAssertEqual(base.detachStaleParticipantCallCount, 0)
    }
  }

  func testBridgeResolutionIsBlockedDuringPublicIDRepair() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(base: base, mutationGate: gate)
    let repairToken = try gate.beginPublicIDRepair()
    defer { gate.endPublicIDRepair(repairToken) }

    do {
      _ = try await repository.resolveBridgeConflict(
        herd: makeHerd(),
        keeping: .keepAcceptedShare,
        storageMode: .iCloud
      )
      XCTFail("Expected bridge conflict resolution to be blocked during public-ID repair.")
    } catch {
      XCTAssertEqual(base.resolveBridgeConflictCallCount, 0)
    }
  }

  func testRemoteOwnerResetIsBlockedWhenExactOwnerShareStillExists() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeRemoteOwnerShareReference()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteOwnerShareVerifier(status: .present)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    do {
      _ = try await repository.resetStaleOwnerSharingState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected an existing remote owner share to block stale-owner reset.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(verifier.lastReference, reference)
    XCTAssertEqual(base.resetStaleOwnerCallCount, 0)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  func testRemoteOwnerResetFailsClosedWhenRemoteVerificationCannotComplete() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeRemoteOwnerShareReference()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteOwnerShareVerifier(
      status: .absent,
      error: RemoteOwnerVerificationTestError.unavailable
    )
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    do {
      _ = try await repository.resetStaleOwnerSharingState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected unavailable remote verification to block stale-owner reset.")
    } catch RemoteOwnerVerificationTestError.unavailable {
      // Expected: no local provenance is changed when CloudKit cannot be verified.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.resetStaleOwnerCallCount, 0)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  func testRemoteOwnerResetDelegatesOnlyAfterAuthoritativeRemoteAbsence() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeRemoteOwnerShareReference()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteOwnerShareVerifier(status: .absent)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    let result = try await repository.resetStaleOwnerSharingState(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Reset")
    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.resetStaleOwnerCallCount, 1)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  func testRemoteOwnerResetRetainsReferenceWhenLocalResetFailsAfterRemoteAbsence() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeRemoteOwnerShareReference()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteOwnerShareVerifier(status: .absent)
    let base = GatedSharingRecordingRepository(failReset: true)
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    do {
      _ = try await repository.resetStaleOwnerSharingState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected the underlying stale-owner reset to fail.")
    } catch RemoteOwnerVerificationTestError.resetFailed {
      // Expected: remote absence alone must not discard the prior share reference.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.resetStaleOwnerCallCount, 1)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  func testRemoteOwnerResetWithoutRecordedShareReferenceFailsClosed() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    let verifier = StubRemoteOwnerShareVerifier(status: .absent)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    do {
      _ = try await repository.resetStaleOwnerSharingState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected stale-owner reset without remote share provenance to fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(verifier.callCount, 0)
    XCTAssertEqual(base.resetStaleOwnerCallCount, 0)
  }

  func testStaleParticipantDetachIsBlockedWhenAcceptedRootStillExistsRemotely() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeAcceptedParticipantReference()
    let referenceStore = RecordingAcceptedParticipantReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteAcceptedParticipantVerifier(
      status: .present(permission: .readWrite)
    )
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      acceptedParticipantReferenceStore: referenceStore,
      remoteAcceptedParticipantVerifier: verifier
    )

    do {
      _ = try await repository.detachStaleParticipantState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected the still-active accepted root to block local participant detachment.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Unexpected action error: \(error)")
        return
      }
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(verifier.lastReference, reference)
    XCTAssertEqual(base.detachStaleParticipantCallCount, 0)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  func testStaleParticipantDetachWithoutRecordedRootFailsClosed() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let referenceStore = RecordingAcceptedParticipantReferenceStore()
    let verifier = StubRemoteAcceptedParticipantVerifier(status: .absent)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      acceptedParticipantReferenceStore: referenceStore,
      remoteAcceptedParticipantVerifier: verifier
    )

    do {
      _ = try await repository.detachStaleParticipantState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected participant detach without exact CloudKit provenance to fail closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Unexpected action error: \(error)")
        return
      }
    }

    XCTAssertEqual(verifier.callCount, 0)
    XCTAssertEqual(base.detachStaleParticipantCallCount, 0)
  }

  func testStaleParticipantDetachFailsClosedWhenRemoteVerificationCannotComplete() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeAcceptedParticipantReference()
    let referenceStore = RecordingAcceptedParticipantReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteAcceptedParticipantVerifier(
      status: .absent,
      error: RemoteAcceptedParticipantVerificationTestError.unavailable
    )
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      acceptedParticipantReferenceStore: referenceStore,
      remoteAcceptedParticipantVerifier: verifier
    )

    do {
      _ = try await repository.detachStaleParticipantState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected unavailable CloudKit verification to block participant detachment.")
    } catch RemoteAcceptedParticipantVerificationTestError.unavailable {
      // Expected: a transient remote failure must not authorize a destructive local detach.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.detachStaleParticipantCallCount, 0)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  func testStaleParticipantDetachDelegatesOnlyAfterAuthoritativeRemoteAbsence() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeAcceptedParticipantReference()
    let referenceStore = RecordingAcceptedParticipantReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteAcceptedParticipantVerifier(status: .absent)
    let base = GatedSharingRecordingRepository()
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      acceptedParticipantReferenceStore: referenceStore,
      remoteAcceptedParticipantVerifier: verifier
    )

    let result = try await repository.detachStaleParticipantState(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Detached")
    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.detachStaleParticipantCallCount, 1)
    XCTAssertNil(referenceStore.reference(for: herd.publicID))
  }

  func testStaleParticipantReferenceIsRetainedWhenLocalDetachFailsAfterRemoteAbsence() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeAcceptedParticipantReference()
    let referenceStore = RecordingAcceptedParticipantReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteAcceptedParticipantVerifier(status: .absent)
    let base = GatedSharingRecordingRepository(failDetach: true)
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      acceptedParticipantReferenceStore: referenceStore,
      remoteAcceptedParticipantVerifier: verifier
    )

    do {
      _ = try await repository.detachStaleParticipantState(
        herd: herd,
        storageMode: .iCloud
      )
      XCTFail("Expected the underlying participant detach to fail.")
    } catch RemoteAcceptedParticipantVerificationTestError.detachFailed {
      // Expected: provenance remains available until the local detach actually commits.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.detachStaleParticipantCallCount, 1)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  func testOwnerShareActionRecordsShareURLForFutureResetVerification() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    let verifier = StubRemoteOwnerShareVerifier(status: .present)
    let base = GatedSharingRecordingRepository(
      startResult: makeOwnerShareActionResult()
    )
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    _ = try await repository.startSharing(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), makeRemoteOwnerShareReference())
  }

  func testOwnerShareWithoutVerifiableIdentityClearsOlderReferenceAndFailsClosed() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let priorReference = makeRemoteOwnerShareReference()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    referenceStore.record(priorReference, for: herd.publicID)
    let verifier = StubRemoteOwnerShareVerifier(status: .absent)
    let base = GatedSharingRecordingRepository(
      startResult: HerdSharingActionResult(
        title: "Share sheet ready",
        message: "Ready",
        sharePresentation: HerdSharePresentationRequest(
          token: HerdShareToken(),
          title: "Gate Test Herd",
          shareIdentifier: "replacement-share",
          shareURL: nil
        )
      )
    )
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Owner-share creation without durable verifiable identity must fail closed.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertNil(referenceStore.reference(for: herd.publicID))
  }

  func testReplacementShareReverifiesPriorShareImmediatelyBeforeCreation() async throws {
    let defaults = isolatedDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = makeHerd()
    let reference = makeRemoteOwnerShareReference()
    let referenceStore = RecordingRemoteOwnerShareReferenceStore()
    referenceStore.record(reference, for: herd.publicID)
    let verifier = StubRemoteOwnerShareVerifier(status: .present)
    let base = GatedSharingRecordingRepository(
      startResult: makeOwnerShareActionResult()
    )
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected the restored remote owner share to block replacement share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(base.startSharingCallCount, 0)
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), reference)
  }

  private func makeHerd() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Gate Test Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }

  private func makeRemoteOwnerShareReference() -> HerdSharingRemoteOwnerShareReference {
    HerdSharingRemoteOwnerShareReference(
      shareURL: URL(string: "https://www.icloud.com/share/owner-share-record")!,
      shareIdentifier: "owner-share-record",
      shareOwnerAccountRecordName: "owner-account"
    )
  }

  private func makeAcceptedParticipantReference() -> HerdSharingAcceptedParticipantReference {
    HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-herd-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner"
    )
  }

  private func makeOwnerShareActionResult() -> HerdSharingActionResult {
    HerdSharingActionResult(
      title: "Share sheet ready",
      message: "Ready",
      sharePresentation: HerdSharePresentationRequest(
        token: HerdShareToken(),
        title: "Gate Test Herd",
        shareIdentifier: "owner-share-record",
        shareURL: URL(string: "https://www.icloud.com/share/owner-share-record")!,
        shareOwnerAccountRecordName: "owner-account"
      )
    )
  }

  private func isolatedDefaults() -> UserDefaults {
    let suiteName = "GatedHerdSharingRepositoryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}

private enum RemoteOwnerVerificationTestError: Error {
  case unavailable
  case resetFailed
}

private enum RemoteAcceptedParticipantVerificationTestError: Error {
  case unavailable
  case detachFailed
}

@MainActor
private final class RecordingRemoteOwnerShareReferenceStore: HerdSharingOwnerShareReferenceRecording {
  private var references: [UUID: HerdSharingRemoteOwnerShareReference] = [:]

  func reference(for herdPublicID: UUID) -> HerdSharingRemoteOwnerShareReference? {
    references[herdPublicID]
  }

  func record(
    _ reference: HerdSharingRemoteOwnerShareReference,
    for herdPublicID: UUID
  ) {
    references[herdPublicID] = reference
  }

  func clearReference(for herdPublicID: UUID) {
    references.removeValue(forKey: herdPublicID)
  }
}

@MainActor
private final class StubRemoteOwnerShareVerifier: HerdSharingRemoteOwnerShareVerifying {
  private let resolvedStatus: HerdSharingRemoteOwnerShareStatus
  private let error: Error?
  private(set) var callCount = 0
  private(set) var lastReference: HerdSharingRemoteOwnerShareReference?

  init(
    status: HerdSharingRemoteOwnerShareStatus,
    error: Error? = nil
  ) {
    resolvedStatus = status
    self.error = error
  }

  func status(
    for reference: HerdSharingRemoteOwnerShareReference
  ) async throws -> HerdSharingRemoteOwnerShareStatus {
    callCount += 1
    lastReference = reference
    if let error { throw error }
    return resolvedStatus
  }
}

@MainActor
private final class RecordingAcceptedParticipantReferenceStore:
  HerdSharingAcceptedParticipantReferenceRecording
{
  private var references: [UUID: HerdSharingAcceptedParticipantReference] = [:]

  func reference(for herdPublicID: UUID) -> HerdSharingAcceptedParticipantReference? {
    references[herdPublicID]
  }

  func record(
    _ reference: HerdSharingAcceptedParticipantReference,
    for herdPublicID: UUID
  ) {
    references[herdPublicID] = reference
  }

  func clearReference(for herdPublicID: UUID) {
    references.removeValue(forKey: herdPublicID)
  }
}

@MainActor
private final class StubRemoteAcceptedParticipantVerifier:
  HerdSharingRemoteAcceptedParticipantVerifying
{
  private let resolvedStatus: HerdSharingRemoteAcceptedParticipantStatus
  private let error: Error?
  private(set) var callCount = 0
  private(set) var lastReference: HerdSharingAcceptedParticipantReference?

  init(
    status: HerdSharingRemoteAcceptedParticipantStatus,
    error: Error? = nil
  ) {
    resolvedStatus = status
    self.error = error
  }

  func status(
    for reference: HerdSharingAcceptedParticipantReference
  ) async throws -> HerdSharingRemoteAcceptedParticipantStatus {
    callCount += 1
    lastReference = reference
    if let error { throw error }
    return resolvedStatus
  }
}

@MainActor
private final class GatedSharingRecordingRepository: HerdSharingRepository {
  private let failReset: Bool
  private let failDetach: Bool
  private let startResult: HerdSharingActionResult
  private(set) var startSharingCallCount = 0
  private(set) var manageExistingShareCallCount = 0
  private(set) var confirmOwnershipCallCount = 0
  private(set) var resetStaleOwnerCallCount = 0
  private(set) var detachStaleParticipantCallCount = 0
  private(set) var resolveBridgeConflictCallCount = 0

  init(
    failReset: Bool = false,
    failDetach: Bool = false,
    startResult: HerdSharingActionResult = HerdSharingActionResult(title: "Unused", message: "Unused")
  ) {
    self.failReset = failReset
    self.failDetach = failDetach
    self.startResult = startResult
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
    .localOwnerBridgePending
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    startSharingCallCount += 1
    return startResult
  }

  func manageExistingShare(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    manageExistingShareCallCount += 1
    return HerdSharingActionResult(title: "Managed", message: "Managed existing share")
  }

  func confirmLocalHerdOwnership(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    confirmOwnershipCallCount += 1
    return HerdSharingActionResult(title: "Confirmed", message: "Confirmed")
  }

  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    resetStaleOwnerCallCount += 1
    if failReset {
      throw RemoteOwnerVerificationTestError.resetFailed
    }
    return HerdSharingActionResult(title: "Reset", message: "Reset")
  }

  func detachStaleParticipantState(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    detachStaleParticipantCallCount += 1
    if failDetach {
      throw RemoteAcceptedParticipantVerificationTestError.detachFailed
    }
    return HerdSharingActionResult(title: "Detached", message: "Detached")
  }

  func resolveBridgeConflict(
    herd: HerdSummary,
    keeping resolution: HerdSharingBridgeConflictResolution,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    resolveBridgeConflictCallCount += 1
    return HerdSharingActionResult(title: "Resolved", message: "Resolved")
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


@MainActor
extension GatedHerdSharingRepositoryTests {
  func testMissingBridgeParticipantMarkerPrecedesEstablishedOwnerShareProvenance() async throws {
    let suiteName = "HerdSharingParticipantPrecedence.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let container = try TestSupport.makeModelContainer()
    let herd = Herd(
      publicID: UUID(),
      name: "Participant Before Owner Recovery",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    container.mainContext.insert(herd)
    try container.mainContext.save()

    let ownershipRegistry = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: "ParticipantPrecedenceOwnership"
    )
    ownershipRegistry.recordParticipant(herdPublicID: herd.publicID)
    let accountRegistry = ParticipantProvenanceAccountOwnershipRegistry()
    accountRegistry.recordEstablishedOwnerShare(for: herd.publicID)
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: HerdSharingBridgeJournal(
        fileURL: participantProvenanceDirectory(named: "participant-precedence")
          .appendingPathComponent("journal.json")
      ),
      ownershipRegistry: ownershipRegistry,
      accountOwnershipRegistry: accountRegistry
    )

    let access = try await guardService.evaluate(
      herd: herd.toSummary(),
      access: .localOwnerBridgePending
    )

    XCTAssertEqual(access.creationState, .notOwnedByCurrentDevice)
    do {
      _ = try await guardService.confirmLocalOwnership(
        herd: herd.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected participant provenance to block owner confirmation before detachment.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .herdOwnershipRequired)
    }
    XCTAssertEqual(ownershipRegistry.ownership(for: herd.publicID), .participant)
    XCTAssertTrue(accountRegistry.hasEstablishedOwnerShare(for: herd.publicID))
  }

  func testCorruptParticipantReferenceRecoversFromRedundantExactCopyBeforeDetachVerification() async throws {
    let suiteName = "HerdSharingParticipantReferenceRecovery.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let herdPublicID = UUID()
    let keyPrefix = "ParticipantReferenceRecovery"
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let reference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-root",
      rootZoneName: "accepted-zone",
      rootZoneOwnerName: "accepted-owner",
      participantAccountRecordName: "participant-account"
    )
    referenceStore.record(reference, for: herdPublicID)

    let primaryKey = "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
    let corruptData = Data("corrupt-participant-reference".utf8)
    defaults.set(corruptData, forKey: primaryKey)
    let remoteVerifier = ParticipantProvenanceRemoteVerifier(status: .absent)

    try await HerdSharingAcceptedParticipantProvenance.verifyRecordedShareIsAbsent(
      for: herdPublicID,
      referenceStore: referenceStore,
      remoteVerifier: remoteVerifier
    )

    XCTAssertEqual(remoteVerifier.references, [reference])
    XCTAssertEqual(try referenceStore.recoverableReference(for: herdPublicID), reference)
    let backupKeys = defaults.dictionaryRepresentation().keys.filter {
      $0.hasPrefix(
        "\(keyPrefix).corrupt-backup.\(herdPublicID.uuidString.lowercased()).primary."
      )
    }
    XCTAssertEqual(backupKeys.count, 1)
    XCTAssertEqual(defaults.data(forKey: try XCTUnwrap(backupKeys.first)), corruptData)
  }

  func testConflictingValidParticipantReferencesFailClosedBeforeDetachVerification() async throws {
    let suiteName = "HerdSharingParticipantReferenceConflict.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let herdPublicID = UUID()
    let keyPrefix = "ParticipantReferenceConflict"
    let referenceStore = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let primaryReference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-root-a",
      rootZoneName: "accepted-zone-a",
      rootZoneOwnerName: "accepted-owner-a",
      participantAccountRecordName: "participant-account-a"
    )
    let recoveryReference = HerdSharingAcceptedParticipantReference(
      rootRecordName: "accepted-root-b",
      rootZoneName: "accepted-zone-b",
      rootZoneOwnerName: "accepted-owner-b",
      participantAccountRecordName: "participant-account-b"
    )
    let primaryData = try JSONEncoder().encode(primaryReference)
    let recoveryData = try JSONEncoder().encode(recoveryReference)
    let primaryKey = "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
    let recoveryKey = "\(primaryKey).recovery"
    defaults.set(primaryData, forKey: primaryKey)
    defaults.set(recoveryData, forKey: recoveryKey)
    let remoteVerifier = ParticipantProvenanceRemoteVerifier(status: .absent)

    do {
      try await HerdSharingAcceptedParticipantProvenance.verifyRecordedShareIsAbsent(
        for: herdPublicID,
        referenceStore: referenceStore,
        remoteVerifier: remoteVerifier
      )
      XCTFail("Conflicting valid participant provenance must not select a detachment target.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        return XCTFail("Unexpected sharing error: \(error)")
      }
      XCTAssertTrue(message.contains("identify different CloudKit relationships"))
    }

    XCTAssertTrue(remoteVerifier.references.isEmpty)
    XCTAssertEqual(defaults.data(forKey: primaryKey), primaryData)
    XCTAssertEqual(defaults.data(forKey: recoveryKey), recoveryData)
    let backupPrefix =
      "\(keyPrefix).corrupt-backup.\(herdPublicID.uuidString.lowercased()).conflicting-"
    let backupKeys = defaults.dictionaryRepresentation().keys.filter {
      $0.hasPrefix(backupPrefix)
    }
    XCTAssertEqual(backupKeys.count, 2)
  }

  func testCorruptInvitationRecoveryRequiresSameExplicitCandidateTwice() throws {
    let suiteName = "HerdSharingCorruptInvitationConfirmation.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let storageKey = "pending-scopes"
    let corruptData = Data("not-valid-json".utf8)
    defaults.set(corruptData, forKey: storageKey)
    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: storageKey,
      currentAccountRecordNameProvider: { "participant-account" }
    )
    let firstCandidate = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "share-a",
      rootRecordName: "same-root",
      rootZoneName: "same-zone",
      rootZoneOwnerName: "same-owner",
      acceptedAt: Date(timeIntervalSince1970: 1),
      participantAccountRecordName: "account-a",
      acceptanceState: .pending
    )

    do {
      try scopeStore.record(firstCandidate)
      XCTFail("Expected the first candidate to be staged without clearing corrupt recovery.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridge consistency failure, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("staged as the proposed recovery target"))
    }
    XCTAssertTrue(scopeStore.hasCorruptRecoveryPending)

    let differentCandidate = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "share-b",
      rootRecordName: "same-root",
      rootZoneName: "same-zone",
      rootZoneOwnerName: "same-owner",
      acceptedAt: Date(timeIntervalSince1970: 2),
      participantAccountRecordName: "account-b",
      acceptanceState: .pending
    )
    do {
      try scopeStore.record(differentCandidate)
      XCTFail("Expected a different invitation identity to remain staged and fail closed.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Expected bridge consistency failure, got \(error)")
        return
      }
    }
    XCTAssertTrue(scopeStore.hasCorruptRecoveryPending)
    XCTAssertTrue(try scopeStore.pendingScopes().isEmpty)

    let confirmedCandidate = HerdSharingAcceptedShareImportScope(
      shareIdentifier: "share-b",
      rootRecordName: "same-root",
      rootZoneName: "same-zone",
      rootZoneOwnerName: "same-owner",
      acceptedAt: Date(timeIntervalSince1970: 3),
      participantAccountRecordName: "account-b",
      acceptanceState: .pending
    )
    try scopeStore.record(confirmedCandidate)

    XCTAssertFalse(scopeStore.hasCorruptRecoveryPending)
    XCTAssertEqual(scopeStore.immediateImportScope, confirmedCandidate)
    XCTAssertEqual(try scopeStore.pendingScopes(), [confirmedCandidate])
    let backupKeys = defaults.dictionaryRepresentation().keys.filter {
      $0.hasPrefix("\(storageKey).corrupt-backup-")
    }
    XCTAssertEqual(backupKeys.count, 1)
    XCTAssertEqual(defaults.data(forKey: try XCTUnwrap(backupKeys.first)), corruptData)
  }

  func testAcceptedSharedImportPersistsParticipantProvenanceOnSuccess() async throws {
    let directory = participantProvenanceDirectory(named: "success")
    let journalURL = directory.appendingPathComponent("journal.json")
    let suiteName = "HerdSharingParticipantProvenance.success.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let keyPrefix = "ParticipantProvenance"
    let registry = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let store = try await makeParticipantProvenanceStore(
      directory: directory,
      journalURL: journalURL,
      defaults: defaults,
      recorder: { herdPublicID in
        registry.recordParticipant(herdPublicID: herdPublicID)
      }
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let sourceContainer = try TestSupport.makeModelContainer()
    let sourceContext = sourceContainer.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Accepted Participant Success",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    sourceContext.insert(herd)
    try sourceContext.save()
    let sourceActor = SwiftDataHerdSharingActor(modelContainer: sourceContainer)
    let export = try await sourceActor.makeExport(
      for: herd.toSummary(),
      storeDescription: "participant provenance seed"
    )
    _ = try await store.writeBridgeSnapshot(export.snapshot, to: sharedStore)

    let targetContainer = try TestSupport.makeModelContainer()
    let targetActor = SwiftDataHerdSharingActor(modelContainer: targetContainer)
    let result = try await store.importSharedRecordsIntoSwiftData(importer: targetActor)

    XCTAssertEqual(result.herdName, herd.name)
    let reloadedRegistry = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    XCTAssertEqual(reloadedRegistry.ownership(for: herd.publicID), .participant)

    let herdPublicID = herd.publicID
    let importedHerds = try targetContainer.mainContext.fetch(
      FetchDescriptor<Herd>(
        predicate: #Predicate<Herd> { candidate in
          candidate.publicID == herdPublicID
        }
      )
    )
    XCTAssertEqual(importedHerds.count, 1)
    XCTAssertEqual(importedHerds.first?.name, herd.name)
    let unfinished = await HerdSharingBridgeJournal(fileURL: journalURL)
      .unfinishedOperations(for: herd.publicID)
    XCTAssertTrue(unfinished.isEmpty)
  }

  func testAcceptedSharedImportPersistsParticipantProvenanceBeforeRevisionHydrationFailure() async throws {
    let directory = participantProvenanceDirectory(named: "revision-hydration-failure")
    let journalURL = directory.appendingPathComponent("journal.json")
    let suiteName = "HerdSharingParticipantProvenance.revisionHydrationFailure.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let keyPrefix = "ParticipantProvenance"
    let registry = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let store = try await makeParticipantProvenanceStore(
      directory: directory,
      journalURL: journalURL,
      defaults: defaults,
      recorder: { herdPublicID in
        registry.recordParticipant(herdPublicID: herdPublicID)
      }
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let sourceContainer = try TestSupport.makeModelContainer()
    let sourceContext = sourceContainer.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Accepted Participant Hydration Failure",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    sourceContext.insert(herd)
    try sourceContext.save()
    let sourceActor = SwiftDataHerdSharingActor(modelContainer: sourceContainer)
    let export = try await sourceActor.makeExport(
      for: herd.toSummary(),
      storeDescription: "participant provenance hydration failure seed"
    )
    _ = try await store.writeBridgeSnapshot(export.snapshot, to: sharedStore)

    do {
      _ = try await store.importSharedRecordsIntoSwiftData(
        importer: ParticipantProvenanceFailingRevisionHydrator()
      )
      XCTFail("Expected collaboration revision hydration to fail before journal creation.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportFailed(let message) = error else {
        XCTFail("Expected bridge import failure from revision hydration, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("revision hydration"))
    }

    let reloadedRegistry = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    XCTAssertEqual(reloadedRegistry.ownership(for: herd.publicID), .participant)
    let unfinished = await HerdSharingBridgeJournal(fileURL: journalURL)
      .unfinishedOperations(for: herd.publicID)
    XCTAssertTrue(unfinished.isEmpty)
  }

  func testAcceptedSharedImportPersistsParticipantProvenanceBeforeStartedFailure() async throws {
    let directory = participantProvenanceDirectory(named: "failure")
    let journalURL = directory.appendingPathComponent("journal.json")
    let suiteName = "HerdSharingParticipantProvenance.failure.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }

    let keyPrefix = "ParticipantProvenance"
    let registry = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let store = try await makeParticipantProvenanceStore(
      directory: directory,
      journalURL: journalURL,
      defaults: defaults,
      recorder: { herdPublicID in
        registry.recordParticipant(herdPublicID: herdPublicID)
      }
    )
    let sharedStore = try XCTUnwrap(store.sharedStore)
    let sourceContainer = try TestSupport.makeModelContainer()
    let sourceContext = sourceContainer.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Accepted Participant Failure",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    sourceContext.insert(herd)
    try sourceContext.save()
    let sourceActor = SwiftDataHerdSharingActor(modelContainer: sourceContainer)
    let export = try await sourceActor.makeExport(
      for: herd.toSummary(),
      storeDescription: "participant provenance failure seed"
    )
    _ = try await store.writeBridgeSnapshot(export.snapshot, to: sharedStore)

    do {
      _ = try await store.importSharedRecordsIntoSwiftData(
        importer: ParticipantProvenanceFailingImporter()
      )
      XCTFail("Expected accepted shared import to fail after the journal boundary.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportRequiresAccessVerification(let message) = error else {
        XCTFail("Expected access verification after started import failure, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("participant provenance regression"))
    }

    let reloadedRegistry = UserDefaultsHerdSharingOwnershipRegistry(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    XCTAssertEqual(reloadedRegistry.ownership(for: herd.publicID), .participant)
    let unfinished = await HerdSharingBridgeJournal(fileURL: journalURL)
      .unfinishedOperations(for: herd.publicID)
    XCTAssertEqual(unfinished.count, 1)
    XCTAssertEqual(unfinished.first?.state, .failed)
    XCTAssertEqual(unfinished.first?.direction, .importFromBridge)
    XCTAssertEqual(
      unfinished.first?.bridgeLocation,
      HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
  }

  func testAcceptedSharedImportWithoutHerdRecordDoesNotPersistParticipantProvenance() async throws {
    let directory = participantProvenanceDirectory(named: "missing-record")
    let journalURL = directory.appendingPathComponent("journal.json")
    var recordedHerdIDs: [UUID] = []
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try await makeParticipantProvenanceStore(
      directory: directory,
      journalURL: journalURL,
      recorder: { herdPublicID in
        recordedHerdIDs.append(herdPublicID)
      }
    )
    let targetContainer = try TestSupport.makeModelContainer()
    let targetActor = SwiftDataHerdSharingActor(modelContainer: targetContainer)

    do {
      _ = try await store.importSharedRecordsIntoSwiftData(importer: targetActor)
      XCTFail("Expected an empty accepted shared store to remain retryable.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportFailed(let message) = error else {
        XCTFail("Expected retryable missing-record import failure, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("No accepted shared herd records"))
    }

    XCTAssertTrue(recordedHerdIDs.isEmpty)
  }

  func testOwnerPrivateImportDoesNotPersistParticipantProvenance() async throws {
    let directory = participantProvenanceDirectory(named: "owner-private")
    let journalURL = directory.appendingPathComponent("journal.json")
    var recordedHerdIDs: [UUID] = []
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try await makeParticipantProvenanceStore(
      directory: directory,
      journalURL: journalURL,
      recorder: { herdPublicID in
        recordedHerdIDs.append(herdPublicID)
      }
    )
    let privateStore = try XCTUnwrap(store.privateStore)
    let sourceContainer = try TestSupport.makeModelContainer()
    let sourceContext = sourceContainer.mainContext
    let herd = Herd(
      publicID: UUID(),
      name: "Owner Private Import",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    sourceContext.insert(herd)
    try sourceContext.save()
    let sourceActor = SwiftDataHerdSharingActor(modelContainer: sourceContainer)
    let export = try await sourceActor.makeExport(
      for: herd.toSummary(),
      storeDescription: "owner private provenance seed"
    )
    _ = try await store.writeBridgeSnapshot(export.snapshot, to: privateStore)

    let targetContainer = try TestSupport.makeModelContainer()
    let targetActor = SwiftDataHerdSharingActor(modelContainer: targetContainer)
    _ = try await store.importBridgeRecordsIntoSwiftData(
      for: herd.toSummary(),
      access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true),
      importer: targetActor
    )

    XCTAssertTrue(recordedHerdIDs.isEmpty)
  }
}

@MainActor
private final class ParticipantProvenanceRemoteVerifier:
  HerdSharingRemoteAcceptedParticipantVerifying
{
  let statusToReturn: HerdSharingRemoteAcceptedParticipantStatus
  private(set) var references: [HerdSharingAcceptedParticipantReference] = []

  init(status: HerdSharingRemoteAcceptedParticipantStatus) {
    statusToReturn = status
  }

  func status(
    for reference: HerdSharingAcceptedParticipantReference
  ) async throws -> HerdSharingRemoteAcceptedParticipantStatus {
    references.append(reference)
    return statusToReturn
  }
}

private final class ParticipantProvenanceAccountOwnershipRegistry:
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

private struct ParticipantProvenanceFailingImporter: HerdSharingImportApplying {
  func applyImport(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector
  ) async throws -> HerdSharingSwiftDataImportApplication {
    throw HerdSharingActionError.bridgeImportFailed(
      "participant provenance regression failure after import start"
    )
  }
}

private struct ParticipantProvenanceFailingRevisionHydrator:
  HerdSharingImportApplying,
  CollaborationRevisionHydrating
{
  func hydrateCollaborationRevisions(for herdPublicID: UUID) async throws {
    throw HerdSharingActionError.bridgeImportFailed(
      "participant provenance regression revision hydration failure"
    )
  }

  func applyImport(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector
  ) async throws -> HerdSharingSwiftDataImportApplication {
    throw HerdSharingActionError.bridgeImportFailed(
      "unexpected import application after revision hydration failure"
    )
  }
}

@MainActor
private func makeParticipantProvenanceStore(
  directory: URL,
  journalURL: URL,
  defaults: UserDefaults = .standard,
  recorder: @escaping @MainActor (UUID) -> Void
) async throws -> HerdSharingCoreDataStore {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let scopeStore = HerdSharingAcceptedShareImportScopeStore(
    defaults: defaults,
    storageKey: "ParticipantProvenance.pending-scopes",
    currentAccountRecordNameProvider: { "participant-provenance-test-account" }
  )
  let store = HerdSharingCoreDataStore(
    storeDirectoryURL: directory,
    journalFileURL: journalURL,
    acceptedParticipantProvenanceRecorder: recorder,
    acceptedShareImportScopeStore: scopeStore,
    acceptedShareRecordIDProvider: { objectID in
      CKRecord.ID(
        recordName: objectID.uriRepresentation().absoluteString,
        zoneID: CKRecordZone.ID(
          zoneName: "participant-provenance-test-zone",
          ownerName: "participant-provenance-test-owner"
        )
      )
    }
  )
  store.persistentContainer.persistentStoreDescriptions = [
    participantProvenancePlainStoreDescription(
      at: directory.appendingPathComponent(HerdSharingCoreDataStore.privateStoreFileName)
    ),
    participantProvenancePlainStoreDescription(
      at: directory.appendingPathComponent(HerdSharingCoreDataStore.sharedStoreFileName)
    ),
  ]
  try await store.loadIfNeeded()
  return store
}

private func participantProvenancePlainStoreDescription(at url: URL) -> NSPersistentStoreDescription {
  let description = NSPersistentStoreDescription(url: url)
  description.type = NSSQLiteStoreType
  description.shouldMigrateStoreAutomatically = true
  description.shouldInferMappingModelAutomatically = true
  return description
}

private func participantProvenanceDirectory(named name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("GatedHerdSharingRepositoryTests.ParticipantProvenance", isDirectory: true)
    .appendingPathComponent(name, isDirectory: true)
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
}


@MainActor
extension GatedHerdSharingRepositoryTests {
  func testSavedOwnerShareObserverRecordsURLAfterSystemShareSave() async throws {
    let defaults = savedOwnerReferenceDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let base = SavedOwnerReferenceSharingRepository(
      startResult: savedOwnerReferenceActionResult(shareIdentifier: "new-owner-share")
    )
    var installedRequest: HerdSharePresentationRequest?
    var savedRecorder: HerdSharingSavedOwnerShareReferenceRecorder?
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(),
      savedOwnerShareObserverInstaller: { request, recorder in
        installedRequest = request
        savedRecorder = recorder
        return true
      }
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)

    XCTAssertEqual(installedRequest?.shareIdentifier, "new-owner-share")
    XCTAssertNil(installedRequest?.shareURL)
    XCTAssertEqual(
      referenceStore.reference(for: herd.publicID),
      savedOwnerProvisionalReference(shareIdentifier: "new-owner-share")
    )

    let savedURL = URL(string: "https://www.icloud.com/share/new-owner-share")!
    guard let savedRecorder else {
      XCTFail("Expected the saved-share observer recorder to be installed before presentation.")
      return
    }
    savedRecorder.record(
      shareURL: savedURL,
      shareIdentifier: "new-owner-share"
    )

    XCTAssertEqual(
      referenceStore.reference(for: herd.publicID),
      HerdSharingRemoteOwnerShareReference(
        shareURL: savedURL,
        shareIdentifier: "new-owner-share",
        shareRecordZoneName: savedOwnerReferenceZoneName,
        shareRecordOwnerName: savedOwnerReferenceZoneOwnerName,
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      )
    )
  }

  func testCancelledFirstShareRetainsProvisionalRecordIdentityForRecovery() async throws {
    let defaults = savedOwnerReferenceDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .absent)
    let base = SavedOwnerReferenceSharingRepository(
      startResult: savedOwnerReferenceActionResult(shareIdentifier: "cancelled-owner-share")
    )
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier,
      savedOwnerShareObserverInstaller: { _, _ in true }
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)

    let provisionalReference = savedOwnerProvisionalReference(
      shareIdentifier: "cancelled-owner-share"
    )
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), provisionalReference)

    // Simulate dismissal/cancellation by deliberately omitting the saved-share callback. If the
    // local owner bridge is later lost, the exact provisional record identity remains sufficient
    // for the existing stale-owner reset path to perform authoritative remote verification.
    let resetResult = try await repository.resetStaleOwnerSharingState(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(resetResult.title, "Reset")
    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(verifier.lastReference, provisionalReference)
    XCTAssertEqual(base.resetCallCount, 1)
  }

  func testReplacementShareReplacesAbsentPriorReferenceWithExactProvisionalIdentity() async throws {
    let defaults = savedOwnerReferenceDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let sharedRecordName = "zone-wide-share"
    let priorReference = HerdSharingRemoteOwnerShareReference(
      shareURL: URL(string: "https://www.icloud.com/share/prior-owner-share")!,
      shareIdentifier: sharedRecordName,
      shareRecordZoneName: "prior-owner-zone",
      shareRecordOwnerName: savedOwnerReferenceZoneOwnerName,
      shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
    )
    referenceStore.record(priorReference, for: herd.publicID)
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .absent)
    let base = SavedOwnerReferenceSharingRepository(
      startResult: savedOwnerReferenceActionResult(shareIdentifier: sharedRecordName)
    )
    var savedRecorder: HerdSharingSavedOwnerShareReferenceRecorder?
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier,
      savedOwnerShareObserverInstaller: { _, recorder in
        savedRecorder = recorder
        return true
      }
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)

    XCTAssertEqual(verifier.callCount, 1)
    XCTAssertEqual(verifier.lastReference, priorReference)
    XCTAssertEqual(
      referenceStore.reference(for: herd.publicID),
      savedOwnerProvisionalReference(shareIdentifier: sharedRecordName)
    )

    let replacementURL = URL(string: "https://www.icloud.com/share/replacement-owner-share")!
    guard let savedRecorder else {
      XCTFail("Expected replacement-share save observation to be installed.")
      return
    }
    savedRecorder.record(
      shareURL: replacementURL,
      shareIdentifier: sharedRecordName
    )

    XCTAssertEqual(
      referenceStore.reference(for: herd.publicID),
      HerdSharingRemoteOwnerShareReference(
        shareURL: replacementURL,
        shareIdentifier: sharedRecordName,
        shareRecordZoneName: savedOwnerReferenceZoneName,
        shareRecordOwnerName: savedOwnerReferenceZoneOwnerName,
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      )
    )
  }

  func testMismatchedSavedCallbackDoesNotReplaceProvisionalReference() async throws {
    let defaults = savedOwnerReferenceDefaults()
    let gate = HerdDataMutationGate(defaults: defaults)
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let base = SavedOwnerReferenceSharingRepository(
      startResult: savedOwnerReferenceActionResult(shareIdentifier: "expected-owner-share")
    )
    var savedRecorder: HerdSharingSavedOwnerShareReferenceRecorder?
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: gate,
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(),
      savedOwnerShareObserverInstaller: { _, recorder in
        savedRecorder = recorder
        return true
      }
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
    let provisionalReference = savedOwnerProvisionalReference(
      shareIdentifier: "expected-owner-share"
    )
    XCTAssertEqual(referenceStore.reference(for: herd.publicID), provisionalReference)

    guard let savedRecorder else {
      XCTFail("Expected saved-share observation to be installed.")
      return
    }
    savedRecorder.record(
      shareURL: URL(string: "https://www.icloud.com/share/unrelated-share")!,
      shareIdentifier: "different-share"
    )

    XCTAssertEqual(referenceStore.reference(for: herd.publicID), provisionalReference)
  }

  func testDeferredResumePreflightBlocksInnerStartWhenRecordedRemoteShareStillExists() async throws {
    let herd = savedOwnerReferenceHerd()
    let base = SavedOwnerReferenceSharingRepository(
      startResult: savedOwnerReferenceActionResult(shareIdentifier: "blocked-resume-share"),
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )
    let creationGuard = SavedOwnerReferenceCreationGuard(
      evaluatedCreationState: .unresolvedBridgeRecord
    )
    var preflightCallCount = 0
    var preparationCallCount = 0
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: creationGuard,
      unresolvedOwnerShareResumePreflight: { herdPublicID in
        preflightCallCount += 1
        XCTAssertEqual(herdPublicID, herd.publicID)
        throw HerdSharingActionError.ownerBridgeVerificationRequired
      },
      ownerSharePreparation: { _, _ in
        preparationCallCount += 1
      }
    )

    do {
      _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
      XCTFail("Expected remote owner-share verification to block the inner resume start.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertEqual(preflightCallCount, 1)
    XCTAssertEqual(base.startCallCount, 0)
    XCTAssertEqual(preparationCallCount, 0)
    XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 0)
  }

  func testDeferredResumePersistsProvenanceAndDefersOwnerMarkerToAccountVerification()
    async throws
  {
    let herd = savedOwnerReferenceHerd()
    let base = SavedOwnerReferenceSharingRepository(
      startResult: savedOwnerReferenceActionResult(shareIdentifier: "resumed-owner-share"),
      access: .ownerPrivateStore(
        participantCount: nil,
        hasActiveSystemShare: false
      )
    )
    let creationGuard = SavedOwnerReferenceCreationGuard(
      evaluatedCreationState: .unresolvedBridgeRecord
    )
    var preflightCallCount = 0
    var preparationCallCount = 0
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: creationGuard,
      unresolvedOwnerShareResumePreflight: { herdPublicID in
        preflightCallCount += 1
        XCTAssertEqual(herdPublicID, herd.publicID)
        XCTAssertEqual(base.startCallCount, 0)
      },
      ownerSharePreparation: { result, herdPublicID in
        preparationCallCount += 1
        XCTAssertEqual(herdPublicID, herd.publicID)
        XCTAssertEqual(result.sharePresentation?.shareIdentifier, "resumed-owner-share")
        XCTAssertEqual(base.startCallCount, 1)
        XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 0)
      }
    )

    let result = try await repository.manageExistingShare(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(result.sharePresentation?.shareIdentifier, "resumed-owner-share")
    XCTAssertEqual(preflightCallCount, 1)
    XCTAssertEqual(base.startCallCount, 1)
    XCTAssertEqual(preparationCallCount, 1)
    XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 0)
  }

  func testDeferredFirstSharePreparationFailureDoesNotCommitOwnerEstablishedMarker() async throws {
    let herd = savedOwnerReferenceHerd()
    let base = SavedOwnerReferenceSharingRepository(
      startResult: savedOwnerReferenceActionResult(shareIdentifier: "unprepared-owner-share")
    )
    let creationGuard = SavedOwnerReferenceCreationGuard(
      evaluatedCreationState: .ready
    )
    var preparationCallCount = 0
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: creationGuard,
      ownerSharePreparation: { _, herdPublicID in
        preparationCallCount += 1
        XCTAssertEqual(herdPublicID, herd.publicID)
        XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 0)
        throw SavedOwnerReferenceTestError.preparationFailed
      }
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected owner-share provenance preparation to fail before the marker commits.")
    } catch SavedOwnerReferenceTestError.preparationFailed {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.startCallCount, 1)
    XCTAssertEqual(preparationCallCount, 1)
    XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 0)
  }

  func testExistingOwnerManagementDoesNotRunResumePreflight() async throws {
    let herd = savedOwnerReferenceHerd()
    let base = SavedOwnerReferenceSharingRepository(
      access: .ownerPrivateStore(
        participantCount: 2,
        hasActiveSystemShare: true
      )
    )
    let creationGuard = SavedOwnerReferenceCreationGuard(
      evaluatedCreationState: .existingOwnerShare
    )
    var preflightCallCount = 0
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: creationGuard,
      unresolvedOwnerShareResumePreflight: { _ in
        preflightCallCount += 1
        throw SavedOwnerReferenceTestError.unused
      }
    )

    let result = try await repository.manageExistingShare(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Managed")
    XCTAssertEqual(preflightCallCount, 0)
    XCTAssertEqual(base.manageCallCount, 1)
    XCTAssertEqual(base.startCallCount, 0)
  }

  func testResumeVerificationFailsClosedWhenOwnerProvenanceIsMissing() async {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .absent)

    do {
      try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
        for: herd.publicID,
        referenceStore: referenceStore,
        remoteVerifier: verifier
      )
      XCTFail("Expected owner-bridge resume to require durable provenance.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(verifier.callCount, 0)
  }

  func testProvisionalOwnerReferenceCodableRoundTripPreservesRecordLocator() throws {
    let reference = savedOwnerProvisionalReference(shareIdentifier: "round-trip-share")

    let encoded = try JSONEncoder().encode(reference)
    let decoded = try JSONDecoder().decode(
      HerdSharingRemoteOwnerShareReference.self,
      from: encoded
    )

    XCTAssertEqual(decoded, reference)
    XCTAssertNil(decoded.shareURL)
    XCTAssertEqual(decoded.shareOwnerAccountRecordName, savedOwnerReferenceAccountRecordName)
    XCTAssertTrue(decoded.hasVerifiableLocator)
  }

  func testProvisionalOwnerReferenceWithoutAccountIdentityFailsClosed() {
    let reference = HerdSharingRemoteOwnerShareReference(
      shareURL: nil,
      shareIdentifier: "unscoped-owner-share",
      shareRecordZoneName: savedOwnerReferenceZoneName,
      shareRecordOwnerName: savedOwnerReferenceZoneOwnerName
    )

    XCTAssertFalse(reference.hasVerifiableLocator)
  }

  func testDifferentCurrentICloudAccountCannotVerifyProvisionalOwnerShareAbsence() {
    XCTAssertThrowsError(
      try HerdSharingOwnerShareProvenance.validateAccountCompatibility(
        expectedOwnerAccountRecordName: savedOwnerReferenceAccountRecordName,
        currentAccountRecordName: "different-owner-account"
      )
    ) { error in
      XCTAssertEqual(error as? HerdSharingActionError, .ownerBridgeVerificationRequired)
    }
  }

  func testMatchingCurrentICloudAccountAllowsProvisionalVerificationToContinue() {
    XCTAssertNoThrow(
      try HerdSharingOwnerShareProvenance.validateAccountCompatibility(
        expectedOwnerAccountRecordName: savedOwnerReferenceAccountRecordName,
        currentAccountRecordName: savedOwnerReferenceAccountRecordName
      )
    )
  }

  func testOwnerRoleAllowsURLBasedOwnerVerificationToContinue() {
    XCTAssertNoThrow(
      try HerdSharingOwnerShareProvenance.validateParticipantRole(.owner)
    )
  }

  func testParticipantRoleCannotVerifyURLBasedOwnerAccess() {
    XCTAssertThrowsError(
      try HerdSharingOwnerShareProvenance.validateParticipantRole(.privateUser)
    ) { error in
      XCTAssertEqual(error as? HerdSharingActionError, .ownerBridgeVerificationRequired)
    }
  }

  func testLegacyURLOnlyOwnerReferenceStillDecodes() throws {
    let legacyJSON = """
      {
        "shareURL": "https://www.icloud.com/share/legacy-owner-share",
        "shareIdentifier": "legacy-owner-share"
      }
      """
    let data = try XCTUnwrap(legacyJSON.data(using: .utf8))

    let decoded = try JSONDecoder().decode(
      HerdSharingRemoteOwnerShareReference.self,
      from: data
    )

    XCTAssertEqual(
      decoded,
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/legacy-owner-share")!,
        shareIdentifier: "legacy-owner-share"
      )
    )
    XCTAssertTrue(decoded.hasVerifiableLocator)
  }

  func testRestoredOwnerShareDoesNotCommitAccountHistoryWhenAccountVerificationFails()
    async throws
  {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/account-a-owner-share"),
        shareIdentifier: "account-a-owner-share",
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      ),
      for: herd.publicID
    )
    let creationGuard = SavedOwnerReferenceCreationGuard(
      evaluatedCreationState: .existingOwnerShare
    )
    let deferred = DeferredCoreDataHerdSharingRepository(
      repository: SavedOwnerReferenceSharingRepository(
        access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
      ),
      creationGuard: creationGuard
    )
    let repository = GatedHerdSharingRepository(
      base: deferred,
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(
        error: HerdSharingActionError.ownerBridgeVerificationRequired
      )
    )

    do {
      _ = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
      XCTFail("A different iCloud account must not inherit established-owner history.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
    XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 0)
  }

  func testRestoredOwnerShareCommitsAccountHistoryOnlyAfterRemoteVerification() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/verified-account-owner-share"),
        shareIdentifier: "verified-account-owner-share",
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      ),
      for: herd.publicID
    )
    let creationGuard = SavedOwnerReferenceCreationGuard(
      evaluatedCreationState: .existingOwnerShare
    )
    let deferred = DeferredCoreDataHerdSharingRepository(
      repository: SavedOwnerReferenceSharingRepository(
        access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
      ),
      creationGuard: creationGuard
    )
    let repository = GatedHerdSharingRepository(
      base: deferred,
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(status: .present)
    )

    _ = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)

    XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 1)
  }

  func testRemoteOwnerStopPreflightBlocksManagementBeforeBaseRepository() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/stopped-owner-share"),
        shareIdentifier: "stopped-owner-share",
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      ),
      for: herd.publicID
    )
    let base = SavedOwnerReferenceSharingRepository(
      access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
    )
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(status: .absent)
    )

    do {
      _ = try await repository.manageExistingShare(herd: herd, storageMode: .iCloud)
      XCTFail("A remotely stopped owner share must not reopen management.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        return XCTFail("Unexpected sharing error: \(error)")
      }
    }

    XCTAssertEqual(base.manageCallCount, 0)
  }

  func testRetainedOwnerStopCleanupCapabilityBypassesNormalRemoteManagementPreflight()
    async throws
  {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/stopped-cleanup-share"),
        shareIdentifier: "stopped-cleanup-share",
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      ),
      for: herd.publicID
    )
    let inner = SavedOwnerReferenceSharingRepository(
      access: .ownerPrivateStore(participantCount: 1, hasActiveSystemShare: true)
    )
    let deferred = DeferredCoreDataHerdSharingRepository(
      repository: inner,
      creationGuard: SavedOwnerReferenceCreationGuard(
        evaluatedCreationState: .ownerStopCleanupPending
      )
    )
    let repository = GatedHerdSharingRepository(
      base: deferred,
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(status: .absent)
    )

    let result = try await repository.manageRetainedOwnerShareForStopCleanup(
      herd: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(result.title, "Managed")
    XCTAssertEqual(inner.manageCallCount, 1)
  }

  func testNewOwnerShareDoesNotCommitAccountHistoryWhenPostCreationVerificationFails()
    async throws
  {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let creationGuard = SavedOwnerReferenceCreationGuard(evaluatedCreationState: .ready)
    let shareIdentifier = "switched-account-new-owner-share"
    let deferred = DeferredCoreDataHerdSharingRepository(
      repository: SavedOwnerReferenceSharingRepository(
        startResult: savedOwnerReferenceActionResult(shareIdentifier: shareIdentifier)
      ),
      creationGuard: creationGuard,
      ownerSharePreparation: { _, herdPublicID in
        referenceStore.record(
          savedOwnerProvisionalReference(shareIdentifier: shareIdentifier),
          for: herdPublicID
        )
      }
    )
    let repository = GatedHerdSharingRepository(
      base: deferred,
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(
        error: HerdSharingActionError.ownerBridgeVerificationRequired
      )
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Owner history must wait for post-creation account verification.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
    XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 0)
  }

  func testNewOwnerShareCommitsAccountHistoryAfterProvisionalAccountVerification()
    async throws
  {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let creationGuard = SavedOwnerReferenceCreationGuard(evaluatedCreationState: .ready)
    let shareIdentifier = "verified-new-owner-share"
    let deferred = DeferredCoreDataHerdSharingRepository(
      repository: SavedOwnerReferenceSharingRepository(
        startResult: savedOwnerReferenceActionResult(shareIdentifier: shareIdentifier)
      ),
      creationGuard: creationGuard,
      ownerSharePreparation: { _, herdPublicID in
        referenceStore.record(
          savedOwnerProvisionalReference(shareIdentifier: shareIdentifier),
          for: herdPublicID
        )
      }
    )
    let repository = GatedHerdSharingRepository(
      base: deferred,
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: SavedOwnerReferenceRemoteVerifier(status: .absent)
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)

    XCTAssertEqual(creationGuard.recordOwnerShareEstablishedCallCount, 1)
  }

  func testRestoredLocalOwnerShareRequiresRemotePresenceBeforeWritableAccess() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/restored-owner-share"),
        shareIdentifier: "restored-owner-share",
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      ),
      for: herd.publicID
    )
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .absent)
    let base = SavedOwnerReferenceSharingRepository(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: true
      ).applyingCreationState(.existingOwnerShare)
    )
    let repository = GatedHerdSharingRepository(
      base: base,
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    let access = try await repository.fetchSharingAccess(
      for: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(access.creationState, .ownerStopCleanupPending)
    XCTAssertFalse(access.allowsLocalMutations)
    XCTAssertEqual(verifier.callCount, 1)
  }

  func testRestoredOwnerShareRemotePresenceIsReverifiedOnEveryAccessRefresh() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/verified-owner-share"),
        shareIdentifier: "verified-owner-share",
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      ),
      for: herd.publicID
    )
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .present)
    let expectedAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let repository = GatedHerdSharingRepository(
      base: SavedOwnerReferenceSharingRepository(access: expectedAccess),
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    let first = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
    let second = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)

    XCTAssertEqual(first, expectedAccess)
    XCTAssertEqual(second, expectedAccess)
    XCTAssertEqual(verifier.callCount, 2)
  }

  func testPreviouslyVerifiedOwnerShareBecomesWriteBlockedAfterRemoteRemoval() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    referenceStore.record(
      HerdSharingRemoteOwnerShareReference(
        shareURL: URL(string: "https://www.icloud.com/share/remotely-stopped-owner-share"),
        shareIdentifier: "remotely-stopped-owner-share",
        shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
      ),
      for: herd.publicID
    )
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .present)
    let expectedAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let repository = GatedHerdSharingRepository(
      base: SavedOwnerReferenceSharingRepository(access: expectedAccess),
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier
    )

    let first = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
    verifier.setStatus(.absent)
    let second = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)

    XCTAssertEqual(first, expectedAccess)
    XCTAssertEqual(second.creationState, .ownerStopCleanupPending)
    XCTAssertFalse(second.allowsLocalMutations)
    XCTAssertEqual(verifier.callCount, 2)
  }

  func testNewProvisionalOwnerShareFailsClosedWhenAccountRevalidationFails() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .absent)
    let expectedAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let repository = GatedHerdSharingRepository(
      base: SavedOwnerReferenceSharingRepository(
        startResult: savedOwnerReferenceActionResult(
          shareIdentifier: "account-scoped-provisional-share"
        ),
        access: expectedAccess
      ),
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier,
      savedOwnerShareObserverInstaller: { _, _ in true }
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
    verifier.setError(HerdSharingActionError.ownerBridgeVerificationRequired)

    do {
      _ = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
      XCTFail("The provisional-share exception must not bypass iCloud account verification.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
    XCTAssertEqual(verifier.callCount, 1)
  }

  func testNewProvisionalOwnerShareIsTrustedOnlyUntilItsSavedReferenceChanges() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .absent)
    let expectedAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    var savedRecorder: HerdSharingSavedOwnerShareReferenceRecorder?
    let repository = GatedHerdSharingRepository(
      base: SavedOwnerReferenceSharingRepository(
        startResult: savedOwnerReferenceActionResult(
          shareIdentifier: "provisional-then-saved-share"
        ),
        access: expectedAccess
      ),
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier,
      savedOwnerShareObserverInstaller: { _, recorder in
        savedRecorder = recorder
        return true
      }
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
    let provisionalAccess = try await repository.fetchSharingAccess(
      for: herd,
      storageMode: .iCloud
    )
    XCTAssertEqual(provisionalAccess, expectedAccess)

    let recorder = try XCTUnwrap(savedRecorder)
    recorder.record(
      shareURL: URL(string: "https://www.icloud.com/share/provisional-then-saved-share")!,
      shareIdentifier: "provisional-then-saved-share"
    )
    let savedAccess = try await repository.fetchSharingAccess(
      for: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(savedAccess.creationState, .ownerStopCleanupPending)
    XCTAssertFalse(savedAccess.allowsLocalMutations)
    XCTAssertEqual(verifier.callCount, 2)
  }

  func testProvisionalOwnerReferenceChangeDuringRemoteCheckFailsClosed() async throws {
    let herd = savedOwnerReferenceHerd()
    let referenceStore = SavedOwnerReferenceRecordingStore()
    let verifier = SavedOwnerReferenceRemoteVerifier(status: .absent)
    let expectedAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    var savedRecorder: HerdSharingSavedOwnerShareReferenceRecorder?
    let repository = GatedHerdSharingRepository(
      base: SavedOwnerReferenceSharingRepository(
        startResult: savedOwnerReferenceActionResult(
          shareIdentifier: "reference-changed-during-check"
        ),
        access: expectedAccess
      ),
      mutationGate: HerdDataMutationGate(defaults: savedOwnerReferenceDefaults()),
      ownerShareReferenceStore: referenceStore,
      remoteOwnerShareVerifier: verifier,
      savedOwnerShareObserverInstaller: { _, recorder in
        savedRecorder = recorder
        return true
      }
    )

    _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
    let recorder = try XCTUnwrap(savedRecorder)
    verifier.setStatusObserver {
      recorder.record(
        shareURL: URL(string: "https://www.icloud.com/share/reference-changed-during-check")!,
        shareIdentifier: "reference-changed-during-check"
      )
    }

    do {
      _ = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
      XCTFail("A changed owner-share reference must be reverified before publishing access.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
    XCTAssertEqual(verifier.callCount, 1)
  }
}

@MainActor
private final class SavedOwnerReferenceRecordingStore: HerdSharingOwnerShareReferenceRecording {
  private var references: [UUID: HerdSharingRemoteOwnerShareReference] = [:]

  func reference(for herdPublicID: UUID) -> HerdSharingRemoteOwnerShareReference? {
    references[herdPublicID]
  }

  func record(
    _ reference: HerdSharingRemoteOwnerShareReference,
    for herdPublicID: UUID
  ) {
    references[herdPublicID] = reference
  }

  func clearReference(for herdPublicID: UUID) {
    references.removeValue(forKey: herdPublicID)
  }
}

@MainActor
private final class SavedOwnerReferenceRemoteVerifier: HerdSharingRemoteOwnerShareVerifying {
  private var resolvedStatus: HerdSharingRemoteOwnerShareStatus
  private var error: Error?
  private var statusObserver: (@MainActor () -> Void)?
  private(set) var callCount = 0
  private(set) var lastReference: HerdSharingRemoteOwnerShareReference?

  init(
    status: HerdSharingRemoteOwnerShareStatus = .absent,
    error: Error? = nil
  ) {
    resolvedStatus = status
    self.error = error
  }

  func setStatus(_ status: HerdSharingRemoteOwnerShareStatus) {
    resolvedStatus = status
    error = nil
  }

  func setError(_ error: Error) {
    self.error = error
  }

  func setStatusObserver(_ observer: @escaping @MainActor () -> Void) {
    statusObserver = observer
  }

  func status(
    for reference: HerdSharingRemoteOwnerShareReference
  ) async throws -> HerdSharingRemoteOwnerShareStatus {
    callCount += 1
    lastReference = reference
    statusObserver?()
    if let error { throw error }
    return resolvedStatus
  }
}

@MainActor
private final class SavedOwnerReferenceSharingRepository: HerdSharingRepository,
  HerdSharingRetainedOwnerShareCleanupManaging
{
  private let startResult: HerdSharingActionResult
  private let access: HerdSharingAccess
  private(set) var startCallCount = 0
  private(set) var manageCallCount = 0
  private(set) var resetCallCount = 0

  init(
    startResult: HerdSharingActionResult = HerdSharingActionResult(
      title: "Unused",
      message: "Unused"
    ),
    access: HerdSharingAccess = .localOwnerBridgePending
  ) {
    self.startResult = startResult
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
    startCallCount += 1
    return startResult
  }

  func manageExistingShare(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    manageCallCount += 1
    return HerdSharingActionResult(title: "Managed", message: "Managed")
  }

  func manageRetainedOwnerShareForStopCleanup(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    manageCallCount += 1
    return HerdSharingActionResult(title: "Managed", message: "Managed")
  }

  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    resetCallCount += 1
    return HerdSharingActionResult(title: "Reset", message: "Reset")
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw SavedOwnerReferenceTestError.unused
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw SavedOwnerReferenceTestError.unused
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw SavedOwnerReferenceTestError.unused
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw SavedOwnerReferenceTestError.unused
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw SavedOwnerReferenceTestError.unused
  }
}

@MainActor
private final class SavedOwnerReferenceCreationGuard: HerdSharingCreationStateGuarding {
  private let evaluatedCreationState: HerdSharingAccess.CreationState
  private(set) var recordOwnerShareEstablishedCallCount = 0

  init(evaluatedCreationState: HerdSharingAccess.CreationState) {
    self.evaluatedCreationState = evaluatedCreationState
  }

  func evaluate(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    access.applyingCreationState(evaluatedCreationState)
  }

  func validateNewShare(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    access.applyingCreationState(.ready)
  }

  func synchronizationDisposition(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingSynchronizationDisposition {
    .fullSync
  }

  func confirmLocalOwnership(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    access
  }

  func resetStaleOwnerSharingState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    access
  }

  func detachStaleParticipantState(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    access
  }

  func recordOwnerShareEstablished(herdPublicID: UUID) {
    recordOwnerShareEstablishedCallCount += 1
  }

  func prepareBridgeConflictResolution(
    herd: HerdSummary,
    resolution: HerdSharingBridgeConflictResolution,
    access: HerdSharingAccess
  ) async throws {}

  func finalizeBridgeConflictResolution(
    herd: HerdSummary,
    resolution: HerdSharingBridgeConflictResolution,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    access
  }
}

private enum SavedOwnerReferenceTestError: Error {
  case unused
  case preparationFailed
}

private let savedOwnerReferenceZoneName = "com.apple.coredata.cloudkit.zone"
private let savedOwnerReferenceZoneOwnerName = "__defaultOwner__"
private let savedOwnerReferenceAccountRecordName = "owner-account-record"

@MainActor
private func savedOwnerReferenceHerd() -> HerdSummary {
  HerdSummary(
    publicID: UUID(),
    name: "Saved Owner Reference Herd",
    createdAt: Date(timeIntervalSince1970: 1),
    updatedAt: Date(timeIntervalSince1970: 2),
    schemaVersion: 1
  )
}

@MainActor
private func savedOwnerReferenceActionResult(
  shareIdentifier: String
) -> HerdSharingActionResult {
  HerdSharingActionResult(
    title: "Share sheet ready",
    message: "Ready",
    sharePresentation: HerdSharePresentationRequest(
      token: HerdShareToken(),
      title: "Saved Owner Reference Herd",
      shareIdentifier: shareIdentifier,
      shareURL: nil,
      shareRecordZoneName: savedOwnerReferenceZoneName,
      shareRecordOwnerName: savedOwnerReferenceZoneOwnerName,
      shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
    )
  )
}

private func savedOwnerProvisionalReference(
  shareIdentifier: String
) -> HerdSharingRemoteOwnerShareReference {
  HerdSharingRemoteOwnerShareReference(
    shareURL: nil,
    shareIdentifier: shareIdentifier,
    shareRecordZoneName: savedOwnerReferenceZoneName,
    shareRecordOwnerName: savedOwnerReferenceZoneOwnerName,
    shareOwnerAccountRecordName: savedOwnerReferenceAccountRecordName
  )
}

@MainActor
private func savedOwnerReferenceDefaults() -> UserDefaults {
  let suiteName = "SavedOwnerShareReferenceRegressionTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  return defaults
}
