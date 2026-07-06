//
//  HerdSharingRepositoryTests.swift
//  yaHerdTests
//

import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingRepositoryTests: XCTestCase {
  func testReadinessRequiresShareRoot() throws {
    let repository = try makeRepository()

    let readiness = repository.fetchSharingReadiness(
      for: nil,
      storageMode: .iCloud
    )

    XCTAssertEqual(readiness.state, .shareRootMissing)
    XCTAssertFalse(readiness.shareActionEnabled)
  }

  func testReadinessRequiresICloudStorage() throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    let readiness = repository.fetchSharingReadiness(
      for: herd,
      storageMode: .localOnly
    )

    XCTAssertEqual(readiness.state, .iCloudSyncRequired)
    XCTAssertFalse(readiness.shareActionEnabled)
  }

  func testICloudReadinessEnablesSharingBridge() throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    let readiness = repository.fetchSharingReadiness(
      for: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(readiness.state, .sharingAdapterAvailable)
    XCTAssertTrue(readiness.shareActionEnabled)
  }

  func testStartSharingRequiresICloudStorageBeforeLoadingCoreData() async throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    do {
      _ = try await repository.startSharing(
        herd: herd,
        storageMode: .localOnly
      )
      XCTFail("Expected iCloud Sync requirement error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .iCloudSyncRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAcceptInvitationUseCaseRequiresPendingInvitation() async {
    let repository = MissingInvitationTestHerdSharingRepository()

    do {
      _ = try await AcceptHerdShareInvitationUseCase(repository: repository).execute(
        invitation: nil,
        storageMode: .iCloud
      )
      XCTFail("Expected missing share invitation error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareInvitationMissing)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSyncUseCaseRequiresHerd() async {
    let repository = MissingInvitationTestHerdSharingRepository()

    do {
      _ = try await SyncSharedHerdDataUseCase(repository: repository).execute(
        herd: nil,
        storageMode: .iCloud
      )
      XCTFail("Expected missing share root error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareRootMissing)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSyncRequiresICloudStorageBeforeLoadingCoreData() async throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd,
        storageMode: .localOnly
      )
      XCTFail("Expected iCloud Sync requirement error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .iCloudSyncRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeRepository() throws -> CoreDataHerdSharingRepository {
    let container = try TestSupport.makeModelContainer()
    return CoreDataHerdSharingRepository(context: container.mainContext)
  }

  private func makeHerdSummary() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Test Herd",
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 1),
      schemaVersion: 1
    )
  }
}

@MainActor
private final class MissingInvitationTestHerdSharingRepository: HerdSharingRepository {
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
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    XCTFail("Repository should not be called when the invitation is missing.")
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func importSharedBridgeData(storageMode: HerdStorageMode) async throws -> HerdSharingActionResult
  {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    XCTFail("Repository should not be called when the herd is missing.")
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }
}
