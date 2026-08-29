import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingConflictReviewWritePolicyTests: XCTestCase {
  func testConflictReviewMutationsRespectBlockedWritePolicyStates() async throws {
    let review = makeReview()
    let blockedAccesses: [(HerdSharingAccess, HerdCollaborationWritePolicyError)] = [
      (
        HerdSharingAccess.ownerPrivateStore(
          participantCount: 2,
          hasActiveSystemShare: true
        ).applyingCreationState(.pendingBridgeOperation),
        .sharingRecoveryPending(reason: .herd)
      ),
      (
        HerdSharingAccess.conflictingStores(
          ownerHasActiveSystemShare: true,
          participantCount: 2
        ).applyingCreationState(.conflictingBridgeRecords),
        .bridgeConflictRequiresResolution(reason: .herd)
      ),
      (
        HerdSharingAccess.localOwnerBridgePending
          .applyingCreationState(.ownerBridgeVerificationRequired),
        .ownerSharingStateUnverified(reason: .herd)
      ),
    ]

    for (access, expectedError) in blockedAccesses {
      let base = ConflictReviewWritePolicyRecordingRepository()
      let writePolicy = HerdCollaborationWritePolicy()
      writePolicy.update(access: access)
      let repository = MutationPublishingHerdSharingRepository(
        base: base,
        mutationCenter: ApplicationMutationCenter(),
        writePolicy: writePolicy
      )

      do {
        _ = try await repository.acceptPreventedSharedDeletes(
          in: review,
          storageMode: .iCloud
        )
        XCTFail("Expected prevented-delete acceptance to be blocked for \(access.creationState).")
      } catch {
        XCTAssertEqual(error as? HerdCollaborationWritePolicyError, expectedError)
      }
      XCTAssertEqual(base.acceptPreventedSharedDeletesCallCount, 0)

      do {
        _ = try await repository.restoreLocalFields(
          [],
          in: review,
          storageMode: .iCloud
        )
        XCTFail("Expected local-field restore to be blocked for \(access.creationState).")
      } catch {
        XCTAssertEqual(error as? HerdCollaborationWritePolicyError, expectedError)
      }
      XCTAssertEqual(base.restoreLocalFieldsCallCount, 0)
    }
  }

  func testConflictReviewMutationsDelegateWhenWritePolicyAllowsEdits() async throws {
    let base = ConflictReviewWritePolicyRecordingRepository()
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: HerdSharingAccess.acceptedSharedStore(
        permission: .readWrite,
        participantCount: 2
      ).applyingCreationState(.acceptedParticipantShare)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy
    )
    let review = makeReview()

    _ = try await repository.acceptPreventedSharedDeletes(
      in: review,
      storageMode: .iCloud
    )
    _ = try await repository.restoreLocalFields(
      [],
      in: review,
      storageMode: .iCloud
    )

    XCTAssertEqual(base.acceptPreventedSharedDeletesCallCount, 1)
    XCTAssertEqual(base.restoreLocalFieldsCallCount, 1)
  }

  func testReadOnlyParticipantCanAcceptAuthoritativeSharedDeletesButCannotRestoreLocalFields() async throws {
    let base = ConflictReviewWritePolicyRecordingRepository()
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: HerdSharingAccess.acceptedSharedStore(
        permission: .readOnly,
        participantCount: 2
      ).applyingCreationState(.acceptedParticipantShare)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy
    )
    let review = makeReview()

    _ = try await repository.acceptPreventedSharedDeletes(
      in: review,
      storageMode: .iCloud
    )

    XCTAssertEqual(base.acceptPreventedSharedDeletesCallCount, 1)

    do {
      _ = try await repository.restoreLocalFields(
        [],
        in: review,
        storageMode: .iCloud
      )
      XCTFail("Expected a read-only participant to remain blocked from restoring local fields.")
    } catch {
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .readOnlySharedHerd(reason: .herd, permission: .readOnly)
      )
    }
    XCTAssertEqual(base.restoreLocalFieldsCallCount, 0)
  }

  func testReadOnlyParticipantCannotAcceptSharedDeletesWhileRecoveryIsPending() async throws {
    let base = ConflictReviewWritePolicyRecordingRepository()
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: HerdSharingAccess.acceptedSharedStore(
        permission: .readOnly,
        participantCount: 2
      ).applyingCreationState(.pendingBridgeOperation)
    )
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy
    )

    do {
      _ = try await repository.acceptPreventedSharedDeletes(
        in: makeReview(),
        storageMode: .iCloud
      )
      XCTFail("Expected pending shared-data recovery to remain fail-closed.")
    } catch {
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingRecoveryPending(reason: .herd)
      )
    }
    XCTAssertEqual(base.acceptPreventedSharedDeletesCallCount, 0)
  }

  func testSuccessfulShareStartDoesNotRunFailureRecovery() async throws {
    let herd = makeHerd()
    let base = ConflictReviewWritePolicyRecordingRepository()
    let writePolicy = HerdCollaborationWritePolicy()
    let originalAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: false
    ).applyingCreationState(.ready)
    writePolicy.update(access: originalAccess)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy
    )

    let result = try await repository.startSharing(herd: herd, storageMode: .iCloud)

    XCTAssertEqual(result, HerdSharingActionResult(title: "Unused", message: "Unused"))
    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(base.fetchSharingAccessCallCount, 0)
    XCTAssertEqual(writePolicy.snapshot.access, originalAccess)
  }

  func testFailedShareStartPublishesAuthoritativeBlockingAccessBeforeReturningError() async {
    let herd = makeHerd()
    let blockingAccess = HerdSharingAccess.localOwnerBridgePending
      .applyingCreationState(.ownerBridgeVerificationRequired)
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    var wasBlockedBeforeAccessRefresh = false
    let base = ConflictReviewWritePolicyRecordingRepository(
      sharingAccess: blockingAccess,
      startSharingError: .startSharingFailed,
      fetchSharingAccessObserver: {
        wasBlockedBeforeAccessRefresh = writePolicy.snapshot.requiresVerifiedAccessBeforeWrite
          && !writePolicy.snapshot.allowsLocalMutations
      }
    )
    let herdRepository = ConflictReviewWritePolicyHerdRepository(herd: herd)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy,
      herdRepository: herdRepository
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected share creation to fail after the sharing state changed.")
    } catch let error as ConflictReviewWritePolicyTestError {
      XCTAssertEqual(error, .startSharingFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(base.fetchSharingAccessCallCount, 1)
    XCTAssertEqual(herdRepository.fetchCallCount, 2)
    XCTAssertTrue(wasBlockedBeforeAccessRefresh)
    XCTAssertEqual(writePolicy.snapshot.access?.creationState, .ownerBridgeVerificationRequired)
    XCTAssertFalse(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .ownerSharingStateUnverified(reason: .animal)
      )
    }
  }

  func testFailedShareStartRestoresWritablePolicyOnlyAfterAuthoritativeReadyAccess() async {
    let herd = makeHerd()
    let readyAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: false
    ).applyingCreationState(.ready)
    let base = ConflictReviewWritePolicyRecordingRepository(
      sharingAccess: readyAccess,
      startSharingError: .startSharingFailed
    )
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(access: readyAccess)
    let herdRepository = ConflictReviewWritePolicyHerdRepository(herd: herd)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy,
      herdRepository: herdRepository
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected the test repository to fail share creation.")
    } catch let error as ConflictReviewWritePolicyTestError {
      XCTAssertEqual(error, .startSharingFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(base.fetchSharingAccessCallCount, 1)
    XCTAssertEqual(herdRepository.fetchCallCount, 2)
    XCTAssertEqual(writePolicy.snapshot.access, readyAccess)
    XCTAssertFalse(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertTrue(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertNoThrow(try writePolicy.validateCanWrite(reason: .herd))
  }

  func testFailedShareStartKeepsWritesBlockedWhenAccessCannotBeRevalidated() async {
    let herd = makeHerd()
    let base = ConflictReviewWritePolicyRecordingRepository(
      startSharingError: .startSharingFailed,
      fetchSharingAccessError: .accessRefreshFailed
    )
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(
      access: HerdSharingAccess.ownerPrivateStore(
        participantCount: 1,
        hasActiveSystemShare: false
      ).applyingCreationState(.ready)
    )
    let herdRepository = ConflictReviewWritePolicyHerdRepository(herd: herd)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy,
      herdRepository: herdRepository
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected share creation to fail.")
    } catch let error as ConflictReviewWritePolicyTestError {
      XCTAssertEqual(error, .startSharingFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(base.fetchSharingAccessCallCount, 1)
    XCTAssertEqual(herdRepository.fetchCallCount, 1)
    XCTAssertNil(writePolicy.snapshot.access)
    XCTAssertTrue(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertFalse(writePolicy.snapshot.allowsLocalMutations)
    XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .pasture)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .pasture)
      )
    }
  }

  func testFailedLocalOnlyShareStartDoesNotInvalidateWritePolicy() async {
    let herd = makeHerd()
    let base = ConflictReviewWritePolicyRecordingRepository(
      startSharingError: .startSharingFailed,
      fetchSharingAccessError: .accessRefreshFailed
    )
    let writePolicy = HerdCollaborationWritePolicy()
    let originalAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: false
    ).applyingCreationState(.ready)
    writePolicy.update(access: originalAccess)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy
    )

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .localOnly)
      XCTFail("Expected the test repository to fail share creation.")
    } catch let error as ConflictReviewWritePolicyTestError {
      XCTAssertEqual(error, .startSharingFailed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(base.startSharingCallCount, 1)
    XCTAssertEqual(base.fetchSharingAccessCallCount, 0)
    XCTAssertEqual(writePolicy.snapshot.access, originalAccess)
    XCTAssertTrue(writePolicy.snapshot.allowsLocalMutations)
  }

  private func makeReview() -> HerdSharingConflictReview {
    HerdSharingConflictReview(
      title: "Persisted conflict review",
      sourceDescription: "write policy regression",
      detectedAt: Date(timeIntervalSince1970: 3),
      existingLocalRecordUpdateCount: 1,
      preventedDeleteConflicts: []
    )
  }

  private func makeHerd() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Write Policy Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }
}

private enum ConflictReviewWritePolicyTestError: Error, Equatable {
  case startSharingFailed
  case accessRefreshFailed
}

@MainActor
private final class ConflictReviewWritePolicyHerdRepository: HerdRepository {
  private var herd: HerdSummary
  private(set) var fetchCallCount = 0

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    fetchCallCount += 1
    return herd
  }

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

@MainActor
private final class ConflictReviewWritePolicyRecordingRepository: HerdSharingRepository {
  private let sharingAccess: HerdSharingAccess
  private let startSharingError: ConflictReviewWritePolicyTestError?
  private let fetchSharingAccessError: ConflictReviewWritePolicyTestError?
  private let fetchSharingAccessObserver: @MainActor () -> Void
  private(set) var startSharingCallCount = 0
  private(set) var fetchSharingAccessCallCount = 0
  private(set) var acceptPreventedSharedDeletesCallCount = 0
  private(set) var restoreLocalFieldsCallCount = 0

  init(
    sharingAccess: HerdSharingAccess = .localOwnerBridgePending,
    startSharingError: ConflictReviewWritePolicyTestError? = nil,
    fetchSharingAccessError: ConflictReviewWritePolicyTestError? = nil,
    fetchSharingAccessObserver: @escaping @MainActor () -> Void = {}
  ) {
    self.sharingAccess = sharingAccess
    self.startSharingError = startSharingError
    self.fetchSharingAccessError = fetchSharingAccessError
    self.fetchSharingAccessObserver = fetchSharingAccessObserver
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
    fetchSharingAccessObserver()
    fetchSharingAccessCallCount += 1
    if let fetchSharingAccessError {
      throw fetchSharingAccessError
    }
    return sharingAccess
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    startSharingCallCount += 1
    if let startSharingError {
      throw startSharingError
    }
    return HerdSharingActionResult(title: "Unused", message: "Unused")
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
    acceptPreventedSharedDeletesCallCount += 1
    return HerdSharingActionResult(title: "Accepted", message: "Accepted")
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    restoreLocalFieldsCallCount += 1
    return HerdSharingActionResult(title: "Restored", message: "Restored")
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }
}
