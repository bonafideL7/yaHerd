//
//  SwiftDataHerdSharingRepositoryTests.swift
//  yaHerdTests
//

import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataHerdSharingRepositoryTests: XCTestCase {
    func testReadinessRequiresShareRoot() {
        let repository = SwiftDataHerdSharingRepository()

        let readiness = repository.fetchSharingReadiness(
            for: nil,
            storageMode: .iCloud
        )

        XCTAssertEqual(readiness.state, .shareRootMissing)
        XCTAssertFalse(readiness.shareActionEnabled)
    }

    func testReadinessRequiresICloudStorage() {
        let repository = SwiftDataHerdSharingRepository()
        let herd = makeHerdSummary()

        let readiness = repository.fetchSharingReadiness(
            for: herd,
            storageMode: .localOnly
        )

        XCTAssertEqual(readiness.state, .iCloudSyncRequired)
        XCTAssertFalse(readiness.shareActionEnabled)
    }

    func testICloudReadinessStillBlocksUntilSharingAdapterExists() {
        let repository = SwiftDataHerdSharingRepository()
        let herd = makeHerdSummary()

        let readiness = repository.fetchSharingReadiness(
            for: herd,
            storageMode: .iCloud
        )

        XCTAssertEqual(readiness.state, .sharingAdapterPending)
        XCTAssertFalse(readiness.shareActionEnabled)
    }

    func testStartSharingRequiresICloudStorage() async {
        let repository = SwiftDataHerdSharingRepository()
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

    func testStartSharingBlocksUntilSharingAdapterExists() async {
        let repository = SwiftDataHerdSharingRepository()
        let herd = makeHerdSummary()

        do {
            _ = try await repository.startSharing(
                herd: herd,
                storageMode: .iCloud
            )
            XCTFail("Expected sharing adapter pending error.")
        } catch let error as HerdSharingActionError {
            XCTAssertEqual(error, .sharingAdapterPending)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAcceptInvitationRequiresICloudStorage() async {
        let repository = SwiftDataHerdSharingRepository()

        do {
            _ = try await repository.acceptPendingShareInvitation(storageMode: .localOnly)
            XCTFail("Expected iCloud Sync requirement error.")
        } catch let error as HerdSharingActionError {
            XCTAssertEqual(error, .iCloudSyncRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAcceptInvitationBlocksUntilSharingAdapterExists() async {
        let repository = SwiftDataHerdSharingRepository()

        do {
            _ = try await repository.acceptPendingShareInvitation(storageMode: .iCloud)
            XCTFail("Expected sharing adapter pending error.")
        } catch let error as HerdSharingActionError {
            XCTAssertEqual(error, .sharingAdapterPending)
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
