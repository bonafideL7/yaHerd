import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairReviewRegressionTests: XCTestCase {
    func testLegacyPendingBridgeMarkerMigratesToICloudIdentityAndSurvivesLocalOnlyRetry() async throws {
        let defaults = isolatedDefaults()
        let report = makeReport()
        defaults.set(
            try JSONEncoder().encode(report),
            forKey: "PublicIDRepair.PendingBridgeConvergenceReport.v1"
        )

        let gate = HerdDataMutationGate(defaults: defaults)
        XCTAssertTrue(gate.requiresBridgeConvergence)

        let service = CoordinatedPublicIDRepairService(
            worker: ReviewNoopRepairWorker(),
            mutationGate: gate,
            bridgeCoordinator: LocalOnlyPublicIDRepairBridgeCoordinator()
        )

        do {
            _ = try await service.repair()
            XCTFail("Expected migrated iCloud convergence to reject Local Only")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .bridgeIdentityMismatch(expected: .iCloud, actual: .localOnly)
            )
        }

        XCTAssertTrue(gate.requiresBridgeConvergence)
    }

    func testPreparedBridgeLocationChangeBlocksConvergence() async throws {
        let herd = makeHerdSummary()
        let inventory = ReviewHerdInventory(herds: [herd])
        let repository = ReviewHerdSharingRepository(
            access: .ownerPrivateStore(participantCount: 1)
        )
        let exporter = ReviewBridgeExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        XCTAssertEqual(
            preparation.targets,
            [
                PublicIDRepairBridgeTargetIdentity(
                    herdPublicID: herd.publicID,
                    location: .ownerPrivateStore
                )
            ]
        )

        repository.access = .localOwnerBridgePending

        do {
            try await coordinator.convergeAfterRepair(preparation: preparation)
            XCTFail("Expected bridge location change to block convergence")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .bridgeTargetMismatch(
                    herdPublicID: herd.publicID,
                    expected: .ownerPrivateStore,
                    actual: .bridgeRecordMissing
                )
            )
        }
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    func testPreparedHerdDisappearingKeepsConvergenceBlocked() async throws {
        let herd = makeHerdSummary()
        let inventory = ReviewHerdInventory(herds: [herd])
        let repository = ReviewHerdSharingRepository(
            access: .ownerPrivateStore(participantCount: 1)
        )
        let exporter = ReviewBridgeExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        await inventory.setHerds([])

        do {
            try await coordinator.convergeAfterRepair(preparation: preparation)
            XCTFail("Expected missing prepared herd to block convergence")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(error, .preparedHerdMissing(herdPublicID: herd.publicID))
        }
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PublicIDRepairReviewRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeHerdSummary() -> HerdSummary {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return HerdSummary(
            publicID: UUID(uuidString: "81818181-8181-4181-8181-818181818181")!,
            name: "Review herd",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
    }

    private func makeReport() -> PublicIDRepairReport {
        PublicIDRepairReport(
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            assessment: PublicIDRepairAssessment(
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
                entities: []
            ),
            replacements: [],
            referenceUpdates: [],
            backupFilename: "legacy.json",
            backupPath: "/tmp/legacy.json",
            validationIssueCount: 0
        )
    }
}

private actor ReviewNoopRepairWorker: PublicIDRepairTransactionalService {
    func scan() async throws -> PublicIDRepairAssessment {
        PublicIDRepairAssessment(scannedAt: .now, entities: [])
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        XCTFail("Pending bridge convergence must not invoke local repair")
        return PublicIDRepairReport(
            completedAt: .now,
            assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
            replacements: [],
            referenceUpdates: [],
            backupFilename: "unused.json",
            backupPath: "/tmp/unused.json",
            validationIssueCount: 0
        )
    }
}

private actor ReviewHerdInventory: PublicIDRepairHerdInventoryReading {
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
private final class ReviewBridgeExporter: PublicIDRepairBridgeExporting {
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
private final class ReviewHerdSharingRepository: HerdSharingRepository {
    var access: HerdSharingAccess
    private(set) var importedHerdIDs: [UUID] = []

    init(access: HerdSharingAccess) {
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
        actionResult("start")
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("accept")
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        if let herd { importedHerdIDs.append(herd.publicID) }
        return actionResult("import")
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("delete")
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("restore")
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("sync")
    }

    private func actionResult(_ value: String) -> HerdSharingActionResult {
        HerdSharingActionResult(title: value, message: value)
    }
}
