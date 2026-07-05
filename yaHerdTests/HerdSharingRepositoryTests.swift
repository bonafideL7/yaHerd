//
//  HerdSharingRepositoryTests.swift
//  yaHerdTests
//

import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class HerdSharingRepositoryTests: XCTestCase {
    func testReadinessRequiresShareRoot() {
        let repository = CoreDataHerdSharingRepository()

        let readiness = repository.fetchSharingReadiness(
            for: nil,
            storageMode: .iCloud
        )

        XCTAssertEqual(readiness.state, .shareRootMissing)
        XCTAssertFalse(readiness.shareActionEnabled)
    }

    func testReadinessRequiresICloudStorage() {
        let repository = CoreDataHerdSharingRepository()
        let herd = makeHerdSummary()

        let readiness = repository.fetchSharingReadiness(
            for: herd,
            storageMode: .localOnly
        )

        XCTAssertEqual(readiness.state, .iCloudSyncRequired)
        XCTAssertFalse(readiness.shareActionEnabled)
    }

    func testICloudReadinessEnablesSharingBridge() {
        let repository = CoreDataHerdSharingRepository()
        let herd = makeHerdSummary()

        let readiness = repository.fetchSharingReadiness(
            for: herd,
            storageMode: .iCloud
        )

        XCTAssertEqual(readiness.state, .sharingAdapterAvailable)
        XCTAssertTrue(readiness.shareActionEnabled)
    }

    func testStartSharingRequiresICloudStorageBeforeLoadingCoreData() async {
        let repository = CoreDataHerdSharingRepository()
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
}
