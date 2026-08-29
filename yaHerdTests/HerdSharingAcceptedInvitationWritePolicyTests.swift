import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingAcceptedInvitationWritePolicyTests: XCTestCase {
  func testICloudAcceptanceBlocksWritesBeforeBaseAcceptanceSuspends() async throws {
    let base = SuspendingInvitationRepository()
    let policy = writablePolicy()
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: FixedInvitationHerdRepository(herd: makeHerd())
    )
    let invitation = makeInvitation()

    let task = Task {
      try await repository.acceptShareInvitation(invitation, storageMode: .iCloud)
    }
    try await waitForAcceptanceToStart(base)

    XCTAssertNil(policy.snapshot.access)
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try policy.validateCanWrite(reason: .herd))

    base.resumeAcceptance()
    _ = try await task.value

    XCTAssertNil(policy.snapshot.access)
    XCTAssertTrue(policy.snapshot.requiresVerifiedAccessBeforeWrite)
  }

  func testFailedICloudAcceptanceCanRestoreOnlyAuthoritativelyRefetchedWritableAccess() async throws {
    let herd = makeHerd()
    let base = SuspendingInvitationRepository(
      acceptanceError: .cloudKitSharingFailed("pre-accept failure"),
      accessToReturn: writableAccess()
    )
    let policy = writablePolicy()
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: FixedInvitationHerdRepository(herd: herd)
    )
    let invitation = makeInvitation()

    let task = Task {
      try await repository.acceptShareInvitation(invitation, storageMode: .iCloud)
    }
    try await waitForAcceptanceToStart(base)

    XCTAssertFalse(policy.snapshot.allowsLocalMutations)

    base.resumeAcceptance()
    do {
      _ = try await task.value
      XCTFail("Expected invitation acceptance to fail.")
    } catch let error as HerdSharingActionError {
      guard case .cloudKitSharingFailed = error else {
        return XCTFail("Expected CloudKit sharing failure, received \(error).")
      }
    }

    XCTAssertEqual(base.fetchSharingAccessCallCount, 1)
    XCTAssertEqual(policy.snapshot.access, writableAccess())
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
    XCTAssertFalse(policy.snapshot.requiresVerifiedAccessBeforeWrite)
  }

  func testFailedAcceptancePreservesNewerSharingStatePublishedWhileAwaiting() async throws {
    let base = SuspendingInvitationRepository(
      acceptanceError: .cloudKitSharingFailed("pre-accept failure"),
      accessToReturn: writableAccess()
    )
    let policy = writablePolicy()
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: FixedInvitationHerdRepository(herd: makeHerd())
    )
    let invitation = makeInvitation()

    let task = Task {
      try await repository.acceptShareInvitation(invitation, storageMode: .iCloud)
    }
    try await waitForAcceptanceToStart(base)

    let newerAccess = HerdSharingAccess.acceptedSharedStore(
      permission: .readOnly,
      participantCount: 1
    ).applyingCreationState(.acceptedParticipantShare)
    policy.update(access: newerAccess)

    base.resumeAcceptance()
    do {
      _ = try await task.value
      XCTFail("Expected invitation acceptance to fail.")
    } catch let error as HerdSharingActionError {
      guard case .cloudKitSharingFailed = error else {
        return XCTFail("Expected CloudKit sharing failure, received \(error).")
      }
    }

    XCTAssertEqual(base.fetchSharingAccessCallCount, 0)
    XCTAssertEqual(policy.snapshot.access, newerAccess)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertFalse(policy.snapshot.requiresVerifiedAccessBeforeWrite)
  }

  func testLocalOnlyAcceptanceDoesNotInvalidateLocalWriteAuthority() async throws {
    let base = SuspendingInvitationRepository()
    let policy = writablePolicy()
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: policy,
      herdRepository: FixedInvitationHerdRepository(herd: makeHerd())
    )
    let invitation = makeInvitation()

    let task = Task {
      try await repository.acceptShareInvitation(invitation, storageMode: .localOnly)
    }
    try await waitForAcceptanceToStart(base)

    XCTAssertEqual(policy.snapshot.access, writableAccess())
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)

    base.resumeAcceptance()
    _ = try await task.value

    XCTAssertEqual(policy.snapshot.access, writableAccess())
    XCTAssertTrue(policy.snapshot.allowsLocalMutations)
  }

  private func waitForAcceptanceToStart(_ base: SuspendingInvitationRepository) async throws {
    for _ in 0..<100 {
      if base.acceptanceDidStart { return }
      await Task.yield()
    }
    throw InvitationWritePolicyTestError.acceptanceDidNotStart
  }

  private func writablePolicy() -> HerdCollaborationWritePolicy {
    let policy = HerdCollaborationWritePolicy()
    policy.update(access: Self.writableAccess())
    return policy
  }

  private static func writableAccess() -> HerdSharingAccess {
    HerdSharingAccess.ownerPrivateStore(participantCount: 1)
      .applyingCreationState(.ready)
  }

  private func writableAccess() -> HerdSharingAccess { Self.writableAccess() }

  private func makeHerd() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Invitation Transition Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }

  private func makeInvitation() -> HerdShareInvitation {
    HerdShareInvitation(
      token: HerdShareToken(),
      containerIdentifier: "iCloud.test",
      shareIdentifier: "invitation-transition-share",
      rootIdentifier: "invitation-transition-root",
      ownerIdentifier: "owner",
      ownerDisplayName: "Owner",
      participantRole: .privateUser,
      permission: .readOnly,
      status: .pending,
      shareURL: nil
    )
  }
}

private enum InvitationWritePolicyTestError: Error {
  case acceptanceDidNotStart
}

@MainActor
private final class SuspendingInvitationRepository: HerdSharingRepository {
  private let acceptanceError: HerdSharingActionError?
  private let accessToReturn: HerdSharingAccess
  private var acceptanceContinuation: CheckedContinuation<Void, Never>?
  private(set) var acceptanceDidStart = false
  private(set) var fetchSharingAccessCallCount = 0

  init(
    acceptanceError: HerdSharingActionError? = nil,
    accessToReturn: HerdSharingAccess = HerdSharingAccess.ownerPrivateStore(participantCount: 1)
      .applyingCreationState(.ready)
  ) {
    self.acceptanceError = acceptanceError
    self.accessToReturn = accessToReturn
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
    fetchSharingAccessCallCount += 1
    return accessToReturn
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.shareManagementUnavailable
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    acceptanceDidStart = true
    await withCheckedContinuation { continuation in
      acceptanceContinuation = continuation
    }
    if let acceptanceError { throw acceptanceError }
    return HerdSharingActionResult(title: "Accepted", message: "Accepted invitation")
  }

  func resumeAcceptance() {
    let continuation = acceptanceContinuation
    acceptanceContinuation = nil
    continuation?.resume()
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.shareManagementUnavailable
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.shareManagementUnavailable
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.shareManagementUnavailable
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw HerdSharingActionError.shareManagementUnavailable
  }
}

@MainActor
private final class FixedInvitationHerdRepository: HerdRepository {
  private var herd: HerdSummary

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary { herd }

  func renameCurrentHerd(to name: String) throws -> HerdSummary {
    herd = HerdSummary(
      publicID: herd.publicID,
      name: name,
      createdAt: herd.createdAt,
      updatedAt: herd.updatedAt,
      schemaVersion: herd.schemaVersion
    )
    return herd
  }
}
