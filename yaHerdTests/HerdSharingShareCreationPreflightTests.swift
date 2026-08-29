import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingShareCreationPreflightTests: XCTestCase {
  func testPositiveCommitPreflightKeepsSubsequentReadyAccessBlocked() async {
    let base = ShareCreationPreflightRepository()
    var lookupResults = [true, true]
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: {
        guard !lookupResults.isEmpty else {
          throw HerdSharingActionError.cloudKitSharingFailed("unexpected extra lookup")
        }
        return lookupResults.removeFirst()
      }
    )
    let herd = makeHerd()

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected account-wide owner-share presence to block the commit boundary.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(base.startSharingCallCount, 0)

    let access = try? await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
    XCTAssertEqual(access?.creationState, .ownerBridgeVerificationRequired)
    XCTAssertFalse(access?.allowsLocalMutations ?? true)
    XCTAssertTrue(lookupResults.isEmpty)
  }

  func testPositiveCommitPreflightBlockSurvivesRepositoryRecreation() async throws {
    let suiteName = "HerdSharingShareCreationPreflightTests.revalidation.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let keyPrefix = "owner-share-revalidation.\(UUID().uuidString)"
    let herd = makeHerd()
    let firstStore = HerdSharingRemoteOwnerShareRevalidationStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let firstRepository = DeferredCoreDataHerdSharingRepository(
      repository: ShareCreationPreflightRepository(),
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: { true },
      remoteOwnerShareRevalidationStore: firstStore
    )

    do {
      _ = try await firstRepository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected the remote owner share to block the first share attempt.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }
    XCTAssertTrue(firstStore.contains(herd.publicID))

    // Recreate both repository and marker store to model process termination before the Core Data
    // owner bridge or per-Herd provenance has converged locally.
    let restartedStore = HerdSharingRemoteOwnerShareRevalidationStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let restartedRepository = DeferredCoreDataHerdSharingRepository(
      repository: ShareCreationPreflightRepository(),
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: { true },
      remoteOwnerShareRevalidationStore: restartedStore
    )

    let access = try await restartedRepository.fetchSharingAccess(
      for: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(access.creationState, .ownerBridgeVerificationRequired)
    XCTAssertFalse(access.allowsLocalMutations)
    XCTAssertTrue(restartedStore.contains(herd.publicID))
  }

  func testDurableBlockingObservationClearsAfterRestartedRevalidationConfirmsAbsence() async throws {
    let suiteName = "HerdSharingShareCreationPreflightTests.revalidation-clear.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let keyPrefix = "owner-share-revalidation-clear.\(UUID().uuidString)"
    let herd = makeHerd()
    let firstStore = HerdSharingRemoteOwnerShareRevalidationStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let firstRepository = DeferredCoreDataHerdSharingRepository(
      repository: ShareCreationPreflightRepository(),
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: { true },
      remoteOwnerShareRevalidationStore: firstStore
    )

    do {
      _ = try await firstRepository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected the first share attempt to persist a revalidation requirement.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    let restartedStore = HerdSharingRemoteOwnerShareRevalidationStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let restartedRepository = DeferredCoreDataHerdSharingRepository(
      repository: ShareCreationPreflightRepository(),
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: { false },
      remoteOwnerShareRevalidationStore: restartedStore
    )

    let recoveredAccess = try await restartedRepository.fetchSharingAccess(
      for: herd,
      storageMode: .iCloud
    )
    XCTAssertEqual(recoveredAccess.creationState, .ready)
    XCTAssertTrue(recoveredAccess.allowsLocalMutations)
    XCTAssertFalse(restartedStore.contains(herd.publicID))

    var unnecessaryLookupCount = 0
    let secondRestartStore = HerdSharingRemoteOwnerShareRevalidationStore(
      defaults: defaults,
      keyPrefix: keyPrefix
    )
    let secondRestartRepository = DeferredCoreDataHerdSharingRepository(
      repository: ShareCreationPreflightRepository(),
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: {
        unnecessaryLookupCount += 1
        return true
      },
      remoteOwnerShareRevalidationStore: secondRestartStore
    )

    let steadyAccess = try await secondRestartRepository.fetchSharingAccess(
      for: herd,
      storageMode: .iCloud
    )
    XCTAssertEqual(steadyAccess.creationState, .ready)
    XCTAssertEqual(unnecessaryLookupCount, 0)
  }

  func testBlockingObservationClearsOnlyAfterAccountWideRevalidationConfirmsAbsence() async throws {
    let base = ShareCreationPreflightRepository()
    var lookupResults = [true, false]
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: {
        guard !lookupResults.isEmpty else {
          throw HerdSharingActionError.cloudKitSharingFailed("unexpected extra lookup")
        }
        return lookupResults.removeFirst()
      }
    )
    let herd = makeHerd()

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected the first positive lookup to block share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    let recoveredAccess = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
    XCTAssertEqual(recoveredAccess.creationState, .ready)
    XCTAssertTrue(recoveredAccess.allowsLocalMutations)
    XCTAssertTrue(lookupResults.isEmpty)
  }

  func testBlockingObservationRemainsFailClosedWhenRevalidationFails() async {
    let base = ShareCreationPreflightRepository()
    var lookupCallCount = 0
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: {
        lookupCallCount += 1
        if lookupCallCount == 1 { return true }
        throw HerdSharingActionError.cloudKitSharingFailed("revalidation failed")
      }
    )
    let herd = makeHerd()

    do {
      _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
      XCTFail("Expected the initial positive lookup to block share creation.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    } catch {
      XCTFail("Unexpected initial error: \(error)")
    }

    do {
      _ = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
      XCTFail("Expected failed account-wide revalidation to stay fail-closed.")
    } catch let error as HerdSharingActionError {
      guard case .cloudKitSharingFailed = error else {
        return XCTFail("Expected CloudKit revalidation failure, got \(error)")
      }
    } catch {
      XCTFail("Unexpected revalidation error: \(error)")
    }
    XCTAssertEqual(lookupCallCount, 2)
  }

  func testDeferredRepositoryStartsShareOnlyAfterAccountWideLookupConfirmsAbsence() async throws {
    let base = ShareCreationPreflightRepository()
    var lookupCallCount = 0
    let repository = DeferredCoreDataHerdSharingRepository(
      repository: base,
      creationGuard: ShareCreationPreflightGuard(),
      newOwnerShareRemoteOwnerShareLookup: {
        lookupCallCount += 1
        return false
      }
    )

    _ = try await repository.startSharing(herd: makeHerd(), storageMode: .iCloud)

    XCTAssertEqual(lookupCallCount, 1)
    XCTAssertEqual(base.startSharingCallCount, 1)
  }

  func testFailedOperationRefreshDoesNotRepublishAccessAfterSharingGenerationChanges() async {
    let herd = makeHerd()
    let staleWritableAccess = HerdSharingAccess.ownerPrivateStore(
      participantCount: 1,
      hasActiveSystemShare: true
    ).applyingCreationState(.existingOwnerShare)
    let base = SuspendedFailedOperationRepository(access: staleWritableAccess)
    let writePolicy = HerdCollaborationWritePolicy()
    writePolicy.update(access: staleWritableAccess)
    let repository = MutationPublishingHerdSharingRepository(
      base: base,
      mutationCenter: ApplicationMutationCenter(),
      writePolicy: writePolicy,
      herdRepository: StaticShareCreationHerdRepository(herd: herd)
    )

    let failedStart = Task { @MainActor in
      do {
        _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
        XCTFail("Expected the underlying start operation to fail.")
      } catch SuspendedFailedOperationError.expected {
        // Expected. The decorator performs its access recovery read before rethrowing.
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }

    while !base.accessLookupStarted {
      await Task.yield()
    }

    // Models a same-Herd invitation/recovery transition committing while the failed-operation
    // access read is suspended. The older recovery result must not overwrite this newer generation.
    writePolicy.clearAccessAfterFailedSynchronization()
    let newerGeneration = writePolicy.sharingStateGeneration
    base.resumeAccessLookup()
    await failedStart.value

    XCTAssertEqual(writePolicy.sharingStateGeneration, newerGeneration)
    XCTAssertNil(writePolicy.snapshot.access)
    XCTAssertTrue(writePolicy.snapshot.requiresVerifiedAccessBeforeWrite)
    XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .herd)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .sharingAccessVerificationRequired(reason: .herd)
      )
    }
  }

  private func makeHerd() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Share Creation Preflight Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
  }
}

@MainActor
private final class ShareCreationPreflightGuard: HerdSharingCreationStateGuarding {
  func evaluate(
    herd: HerdSummary,
    access: HerdSharingAccess
  ) async throws -> HerdSharingAccess {
    access.applyingCreationState(.ready)
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
    access.applyingCreationState(.ready)
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

@MainActor
private final class ShareCreationPreflightRepository: HerdSharingRepository {
  private(set) var startSharingCallCount = 0

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
    return HerdSharingActionResult(title: "Ready", message: "Ready")
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
private final class StaticShareCreationHerdRepository: HerdRepository {
  private var herd: HerdSummary

  init(herd: HerdSummary) {
    self.herd = herd
  }

  func fetchCurrentHerd() throws -> HerdSummary {
    herd
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

private enum SuspendedFailedOperationError: Error {
  case expected
}

@MainActor
private final class SuspendedFailedOperationRepository: HerdSharingRepository {
  private let access: HerdSharingAccess
  private var shouldSuspendAccessLookup = true
  private(set) var accessLookupStarted = false

  init(access: HerdSharingAccess) {
    self.access = access
  }

  func resumeAccessLookup() {
    shouldSuspendAccessLookup = false
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
    accessLookupStarted = true
    while shouldSuspendAccessLookup {
      await Task.yield()
    }
    return access
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    throw SuspendedFailedOperationError.expected
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
