import SwiftData
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

    func testAcceptedSharedBridgeImportIntroducingDuplicateHerdBlocksPreparation() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdID = UUID(uuidString: "E5E5E5E5-E5E5-45E5-85E5-E5E5E5E5E5E5")!
        let original = HerdSummary(
            publicID: herdID,
            name: "Accepted shared herd",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let duplicate = HerdSummary(
            publicID: herdID,
            name: "Duplicate from bridge import",
            createdAt: timestamp.addingTimeInterval(1),
            updatedAt: timestamp.addingTimeInterval(1),
            schemaVersion: 1
        )
        let inventory = BridgeBoundaryHerdInventory(herds: [original])
        let repository = BridgeBoundarySharingRepository(
            access: .acceptedSharedStore(
                permission: .readWrite,
                participantCount: 2
            ),
            onImport: {
                await inventory.setHerds([original, duplicate])
            }
        )
        let exporter = BridgeBoundaryExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        do {
            _ = try await coordinator.prepareForRepair()
            XCTFail("Expected duplicate Herd introduced by bridge import to block repair")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .duplicateHerdBridgeTargetAmbiguous(
                    herdPublicID: herdID,
                    recordCount: 2
                )
            )
        }

        XCTAssertEqual(repository.fetchAccessCallCount, 1)
        XCTAssertEqual(repository.importCallCount, 1)
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    func testBridgeMutationAfterPreparationBlocksConvergenceBeforeExport() async throws {
        let herd = makeBridgeBoundaryHerd()
        let inventory = BridgeBoundaryHerdInventory(herds: [herd])
        let repository = BridgeBoundarySharingRepository()
        let exporter = BridgeBoundaryExporter(currentFingerprint: "baseline-a")
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        XCTAssertEqual(preparation.targets.first?.bridgeFingerprint, "baseline-a")
        exporter.currentFingerprint = "baseline-b"

        do {
            try await coordinator.convergeAfterRepair(preparation: preparation)
            XCTFail("Expected intervening bridge mutation to block convergence")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(error, .bridgeContentChanged(herdPublicID: herd.publicID))
        }
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    func testBridgeTargetChangeDuringExportSnapshotBuildCannotFallThroughToAnotherStore() async throws {
        let herd = makeBridgeBoundaryHerd()
        let baseline = "accepted-shared-baseline"
        let bridgeStore = TargetChangingRepairBridgeStore(
            currentLocation: .acceptedSharedStore,
            currentFingerprint: baseline
        )
        let export = HerdSharingSwiftDataExport(
            herd: herd,
            snapshot: HerdSharingBridgeStoreSnapshot(
                herdPublicID: herd.publicID,
                storeDescription: "target-binding-test",
                recordsByStep: [:]
            ),
            localPublicIDs: [:]
        )
        let exportReader = TargetChangingExportReader(export: export) {
            bridgeStore.currentLocation = .ownerPrivateStore
        }
        let exporter = SwiftDataPublicIDRepairBridgeExporter(
            modelContainer: try TestSupport.makeModelContainer(),
            exportReader: exportReader,
            bridgeStore: bridgeStore
        )
        let target = PublicIDRepairBridgeTargetIdentity(
            herdPublicID: herd.publicID,
            location: .acceptedSharedStore,
            bridgeFingerprint: baseline
        )

        do {
            _ = try await exporter.exportRepairedGraph(
                for: herd,
                target: target
            )
            XCTFail("Expected the changed bridge target to block the repair export")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .bridgeTargetChangedDuringExport(
                    herdPublicID: herd.publicID,
                    expected: .acceptedSharedStore,
                    actual: "owner private store"
                )
            )
        }

        XCTAssertEqual(bridgeStore.syncCallCount, 1)
        XCTAssertEqual(bridgeStore.successfulWriteCount, 0)
    }

    func testLegacyReplacementHerdCannotFallBackFromAcceptedShareToPrivateStore() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let originalID = UUID(uuidString: "C3C3C3C3-C3C3-43C3-83C3-C3C3C3C3C3C3")!
        let replacementID = UUID(uuidString: "D4D4D4D4-D4D4-44D4-84D4-D4D4D4D4D4D4")!
        let original = HerdSummary(
            publicID: originalID,
            name: "Accepted shared herd",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let replacement = HerdSummary(
            publicID: replacementID,
            name: "Legacy repaired duplicate",
            createdAt: timestamp.addingTimeInterval(1),
            updatedAt: timestamp.addingTimeInterval(1),
            schemaVersion: 1
        )
        let inventory = BridgeBoundaryHerdInventory(herds: [original])
        let repository = BridgeBoundarySharingRepository(
            access: .acceptedSharedStore(
                permission: .readWrite,
                participantCount: 2
            )
        )
        let exporter = BridgeBoundaryExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        XCTAssertEqual(preparation.targets.count, 1)
        XCTAssertEqual(preparation.targets.first?.herdPublicID, originalID)
        XCTAssertEqual(preparation.targets.first?.location, .acceptedSharedStore)
        XCTAssertNotNil(preparation.targets.first?.bridgeFingerprint)
        let accessCallsAfterPreparation = repository.fetchAccessCallCount

        // Models a pending repair produced by an earlier build that reassigned a duplicate Herd
        // before the current preflight prohibition existed. The new ID has no prepared target.
        await inventory.setHerds([original, replacement])

        do {
            try await coordinator.convergeAfterRepair(preparation: preparation)
            XCTFail("Expected unprepared replacement Herd to keep convergence blocked")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .unpreparedHerdBridgeTarget(herdPublicID: replacementID)
            )
        }

        XCTAssertEqual(
            repository.fetchAccessCallCount,
            accessCallsAfterPreparation,
            "Convergence must not query the replacement ID and infer local-owner access"
        )
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }
}

private func makeBridgeBoundaryHerd() -> HerdSummary {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    return HerdSummary(
        publicID: UUID(uuidString: "F6F6F6F6-F6F6-46F6-86F6-F6F6F6F6F6F6")!,
        name: "Boundary herd",
        createdAt: timestamp,
        updatedAt: timestamp,
        schemaVersion: 1
    )
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
    var currentFingerprint: String
    private(set) var exportedHerdIDs: [UUID] = []

    init(currentFingerprint: String = "bridge-boundary-baseline") {
        self.currentFingerprint = currentFingerprint
    }

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        currentFingerprint
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        guard target.bridgeFingerprint == currentFingerprint else {
            throw PublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }
        exportedHerdIDs.append(herd.publicID)
        return .empty
    }
}

private actor TargetChangingExportReader: HerdSharingExportSnapshotReading {
    private let export: HerdSharingSwiftDataExport
    private let onMakeExport: @MainActor @Sendable () -> Void

    init(
        export: HerdSharingSwiftDataExport,
        onMakeExport: @escaping @MainActor @Sendable () -> Void
    ) {
        self.export = export
        self.onMakeExport = onMakeExport
    }

    func makeExport(
        for herd: HerdSummary,
        storeDescription: String
    ) async throws -> HerdSharingSwiftDataExport {
        await onMakeExport()
        return export
    }
}

@MainActor
private final class TargetChangingRepairBridgeStore: PublicIDRepairBridgeStore {
    var currentLocation: HerdSharingAccess.BridgeLocation
    var currentFingerprint: String
    private(set) var syncCallCount = 0
    private(set) var successfulWriteCount = 0

    init(
        currentLocation: HerdSharingAccess.BridgeLocation,
        currentFingerprint: String
    ) {
        self.currentLocation = currentLocation
        self.currentFingerprint = currentFingerprint
    }

    func publicIDRepairFingerprint(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> String {
        try validateLocation(expectedLocation)
        return currentFingerprint
    }

    func syncPublicIDRepairBridgeRecordsFromSnapshot(
        _ export: HerdSharingSwiftDataExport,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws -> HerdSharingBridgeExportResult {
        syncCallCount += 1
        try validateLocation(expectedLocation)
        guard currentFingerprint == expectedFingerprint else {
            throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: export.herd.publicID
            )
        }
        successfulWriteCount += 1
        throw BridgeBoundaryTestError.unexpectedWrite
    }

    private func validateLocation(
        _ expectedLocation: HerdSharingAccess.BridgeLocation
    ) throws {
        guard currentLocation == expectedLocation else {
            throw HerdSharingPublicIDRepairBridgeError.targetChanged(
                expected: bridgeDescription(expectedLocation),
                actual: bridgeDescription(currentLocation)
            )
        }
    }

    private func bridgeDescription(
        _ location: HerdSharingAccess.BridgeLocation
    ) -> String {
        switch location {
        case .bridgeRecordMissing:
            "no bridge record yet"
        case .ownerPrivateStore:
            "owner private store"
        case .acceptedSharedStore:
            "accepted shared store"
        }
    }
}

private enum BridgeBoundaryTestError: Error, Sendable {
    case unexpectedWrite
}

@MainActor
private final class BridgeBoundarySharingRepository: HerdSharingRepository {
    private(set) var fetchAccessCallCount = 0
    private(set) var importCallCount = 0
    var access: HerdSharingAccess
    private let onImport: (@MainActor () async -> Void)?

    init(
        access: HerdSharingAccess = .ownerPrivateStore(participantCount: 1),
        onImport: (@MainActor () async -> Void)? = nil
    ) {
        self.access = access
        self.onImport = onImport
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
        fetchAccessCallCount += 1
        return access
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
        importCallCount += 1
        await onImport?()
        return result("import")
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
