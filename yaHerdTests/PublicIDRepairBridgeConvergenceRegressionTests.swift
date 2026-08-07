import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairBridgeConvergenceRegressionTests: XCTestCase {
    func testDuplicateHerdAppearingBeforeConvergenceBlocksBeforeAccessOrExport() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdID = UUID(uuidString: "B2B2B2B2-B2B2-42B2-82B2-B2B2B2B2B2B2")!
        let original = HerdSummary(
            publicID: herdID,
            name: "Original",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let duplicate = HerdSummary(
            publicID: herdID,
            name: "Late duplicate",
            createdAt: timestamp.addingTimeInterval(1),
            updatedAt: timestamp.addingTimeInterval(1),
            schemaVersion: 1
        )
        let inventory = BridgeBoundaryHerdInventory(herds: [original])
        let repository = BridgeBoundarySharingRepository()
        let exporter = BridgeBoundaryExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        let accessCallsAfterPreparation = repository.fetchAccessCallCount
        await inventory.setHerds([original, duplicate])

        do {
            try await coordinator.convergeAfterRepair(preparation: preparation)
            XCTFail("Expected late duplicate Herd to block convergence")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .duplicateHerdBridgeTargetAmbiguous(
                    herdPublicID: herdID,
                    recordCount: 2
                )
            )
        }

        XCTAssertEqual(repository.fetchAccessCallCount, accessCallsAfterPreparation)
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }
}

private actor BridgeBoundaryHerdInventory: PublicIDRepairHerdInventoryReading {
    private var herds: [HerdSummary]

    init(herds: [HerdSummary]) {
        self.herds = herds
    }

    func fetchHerds() async throws -> [HerdSummary] {
        herds
    }

    func setHerds(_ herds: [HerdSummary]) {
        self.herds = herds
    }
}

@MainActor
private final class BridgeBoundaryExporter: PublicIDRepairBridgeExporting {
    private(set) var exportedHerdIDs: [UUID] = []

    func exportRepairedGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> HerdSharingBridgeReconciliationReport {
        exportedHerdIDs.append(herd.publicID)
        return .empty
    }
}

@MainActor
private final class BridgeBoundarySharingRepository: HerdSharingRepository {
    private(set) var fetchAccessCallCount = 0

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
        fetchAccessCallCount += 1
        return .ownerPrivateStore(participantCount: 1)
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("start")
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("accept")
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("import")
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("delete")
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("restore")
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("sync")
    }

    private func result(_ value: String) -> HerdSharingActionResult {
        HerdSharingActionResult(title: value, message: value)
    }
}
