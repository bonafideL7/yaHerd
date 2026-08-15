import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairBridgeRestartRegressionTests: XCTestCase {
    func testRepairFingerprintIsStableAcrossRepeatedExportsOfUnchangedLiveGraph() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdModel = Herd(
            name: "Fingerprint herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(herdModel)
        try context.save()

        let herd = herdModel.toSummary()
        let reader = SwiftDataHerdSharingActor(modelContainer: container)
        let first = try await reader.makeExport(
            for: herd,
            storeDescription: "fingerprint-first"
        )
        try await ContinuousClock().sleep(for: .milliseconds(10))
        let second = try await reader.makeExport(
            for: herd,
            storeDescription: "fingerprint-second"
        )

        XCTAssertEqual(
            first.snapshot.publicIDRepairFingerprint,
            second.snapshot.publicIDRepairFingerprint,
            "Transport-only lastMirroredAt changes must not make repair recovery look like a collaborator edit"
        )
    }

    func testExporterRetryAcceptsExactRepairedSnapshotAfterPostWriteCrashWithoutRewriting() async throws {
        let herd = restartTestHerd()
        let baselineFingerprint = "restart-baseline"
        let export = restartTestExport(for: herd)
        let desiredFingerprint = export.snapshot.publicIDRepairFingerprint
        let bridgeStore = RestartableRepairBridgeStore(
            currentLocation: .ownerPrivateStore,
            currentFingerprint: baselineFingerprint,
            failAfterFirstWrite: true
        )
        let exporter = SwiftDataPublicIDRepairBridgeExporter(
            modelContainer: try TestSupport.makeModelContainer(),
            exportReader: RestartExportReader(export),
            bridgeStore: bridgeStore
        )
        let target = PublicIDRepairBridgeTargetIdentity(
            herdPublicID: herd.publicID,
            location: PublicIDRepairBridgeLocationIdentity.ownerPrivateStore,
            bridgeFingerprint: baselineFingerprint
        )

        do {
            _ = try await exporter.exportRepairedGraph(for: herd, target: target)
            XCTFail("Expected the simulated crash after the bridge write")
        } catch BridgeRestartTestError.injectedPostWriteCrash {
            XCTAssertEqual(bridgeStore.currentFingerprint, desiredFingerprint)
            XCTAssertEqual(bridgeStore.successfulWriteCount, 1)
        }

        let reconciliation = try await exporter.exportRepairedGraph(
            for: herd,
            target: target
        )

        XCTAssertFalse(reconciliation.hasUnresolvedDifferences)
        XCTAssertEqual(bridgeStore.syncCallCount, 2)
        XCTAssertEqual(
            bridgeStore.successfulWriteCount,
            1,
            "Retry must recognize the exact repaired bridge instead of rewriting it"
        )
    }

    func testMissingPreparedBridgeCanResumeAfterPriorConvergenceCreatedOwnerPrivateRecord() async throws {
        let herd = restartTestHerd()
        let inventory = RestartHerdInventory(herds: [herd])
        let repository = RestartSharingRepository(access: .localOwnerBridgePending)
        let exporter = RestartBoundaryExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        XCTAssertEqual(preparation.targets.first?.location, .bridgeRecordMissing)
        XCTAssertEqual(preparation.targets.first?.bridgeFingerprint, exporter.baselineFingerprint)

        repository.access = .ownerPrivateStore(participantCount: 1)

        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: restartRepairReport()
        )

        XCTAssertEqual(exporter.importedHerdIDs, [herd.publicID])
        XCTAssertEqual(exporter.exportedHerdIDs, [herd.publicID])
        XCTAssertEqual(exporter.receivedTargets.first?.location, .bridgeRecordMissing)
    }

    func testMissingPreparedHerdRestoreAndIntentionalDeletionAreSeparateExplicitActions() async throws {
        let herd = restartTestHerd()
        let inventory = RestartHerdInventory(herds: [herd])
        let repository = RestartSharingRepository(access: .ownerPrivateStore(participantCount: 1))
        let exporter = RestartBoundaryExporter(onImport: { restored in
            await inventory.setHerds([restored])
        })
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let preparation = try await coordinator.prepareForRepair()
        await inventory.setHerds([])

        let issue: PublicIDRepairUnresolvedReference
        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: restartRepairReport()
            )
            XCTFail("Expected diagnostics to require explicit restore versus deletion intent")
            return
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            issue = try XCTUnwrap(error.issues.first)
        }

        XCTAssertEqual(issue.kind, .preparedHerdRecovery)
        XCTAssertEqual(issue.referencedPublicID, herd.publicID)
        XCTAssertEqual(issue.candidates.count, 2)
        XCTAssertTrue(issue.candidates.contains {
            $0.stableRecordIdentifier.hasPrefix("restore-prepared-herd|")
        })
        XCTAssertTrue(issue.candidates.contains {
            $0.stableRecordIdentifier.hasPrefix("retire-prepared-herd|")
        })

        let restoreAction = PublicIDRepairBridgeRecoveryAction(
            kind: .restoreMissingPreparedHerd,
            herdPublicID: herd.publicID
        )
        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: restartRepairReport(recoveryActions: [restoreAction])
        )

        let restoredHerds = try await inventory.fetchHerds()
        XCTAssertEqual(restoredHerds.map(\.publicID), [herd.publicID])
        XCTAssertTrue(exporter.importedHerdIDs.contains(herd.publicID))
        XCTAssertEqual(exporter.exportedHerdIDs, [herd.publicID])
        XCTAssertEqual(exporter.retiredHerdIDs, [])
    }

    func testMissingPreparedHerdIntentionalDeletionRetiresExactBridgeWithoutRestoring() async throws {
        let herd = restartTestHerd()
        let inventory = RestartHerdInventory(herds: [herd])
        let repository = RestartSharingRepository(access: .ownerPrivateStore(participantCount: 1))
        let exporter = RestartBoundaryExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let preparation = try await coordinator.prepareForRepair()
        await inventory.setHerds([])

        let retirementAction = PublicIDRepairBridgeRecoveryAction(
            kind: .retireIntentionallyDeletedPreparedHerd,
            herdPublicID: herd.publicID
        )
        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: restartRepairReport(recoveryActions: [retirementAction])
        )

        XCTAssertEqual(exporter.retiredHerdIDs, [herd.publicID])
        XCTAssertEqual(exporter.retiredTargets.first, preparation.targets.first)
        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
        let remainingHerds = try await inventory.fetchHerds()
        XCTAssertEqual(remainingHerds, [])
    }
}

private enum BridgeRestartTestError: Error, Sendable {
    case injectedPostWriteCrash
    case unexpectedImport
}

private let restartAffectedSourceID = UUID(uuidString: "68686868-6868-4868-8868-686868686868")!
private let restartAffectedFinalID = UUID(uuidString: "69696969-6969-4969-8969-696969696969")!

private func restartTestHerd() -> HerdSummary {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    return HerdSummary(
        publicID: UUID(uuidString: "67676767-6767-4767-8767-676767676767")!,
        name: "Restart herd",
        createdAt: timestamp,
        updatedAt: timestamp,
        schemaVersion: 1
    )
}

private func restartRepairReport(
    recoveryActions: [PublicIDRepairBridgeRecoveryAction]? = nil
) -> PublicIDRepairReport {
    let herdID = restartTestHerd().publicID
    return PublicIDRepairReport(
        completedAt: .now,
        assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
        replacements: [
            PublicIDRepairReplacement(
                entityType: .animal,
                recordDescription: "Restart affected animal",
                stableRecordIdentifier: "restart-affected-animal",
                retainedPublicID: restartAffectedSourceID,
                replacementPublicID: restartAffectedFinalID,
                owningHerdPublicID: herdID
            )
        ],
        referenceUpdates: [],
        backupFilename: "restart.json",
        backupPath: "/tmp/restart.json",
        validationIssueCount: 0,
        bridgeRecoveryActions: recoveryActions
    )
}

private func restartTestExport(for herd: HerdSummary) -> HerdSharingSwiftDataExport {
    HerdSharingSwiftDataExport(
        herd: herd,
        snapshot: HerdSharingBridgeStoreSnapshot(
            herdPublicID: herd.publicID,
            storeDescription: "restart-regression",
            recordsByStep: [:]
        ),
        localPublicIDs: [:]
    )
}

private func restartExportResult(for herd: HerdSummary) -> HerdSharingBridgeExportResult {
    HerdSharingBridgeExportResult(
        herdName: herd.name,
        writeTargetDescription: "restart-regression",
        didUpdateExistingCloudKitShare: false,
        exportedTagColorDefinitionCount: 0,
        exportedStatusReferenceCount: 0,
        exportedAnimalTagCount: 0,
        exportedPastureGroupCount: 0,
        exportedPastureCount: 0,
        exportedAnimalCount: 0,
        exportedMovementCount: 0,
        exportedStatusRecordCount: 0,
        exportedHealthRecordCount: 0,
        exportedPregnancyCheckCount: 0,
        exportedWorkingProtocolTemplateCount: 0,
        exportedWorkingSessionCount: 0,
        exportedWorkingQueueItemCount: 0,
        exportedWorkingTreatmentRecordCount: 0,
        exportedFieldCheckSessionCount: 0,
        exportedFieldCheckAnimalCheckCount: 0,
        exportedFieldCheckFindingCount: 0,
        exportedDeletedRecordCount: 0,
        reconciliationReport: .empty
    )
}

private actor RestartExportReader: HerdSharingExportSnapshotReading {
    private let export: HerdSharingSwiftDataExport

    init(_ export: HerdSharingSwiftDataExport) {
        self.export = export
    }

    func makeExport(
        for herd: HerdSummary,
        storeDescription: String
    ) async throws -> HerdSharingSwiftDataExport {
        export
    }
}

@MainActor
private final class RestartableRepairBridgeStore: PublicIDRepairBridgeStore {
    let currentLocation: HerdSharingAccess.BridgeLocation
    var currentFingerprint: String
    private var failAfterFirstWrite: Bool
    private(set) var syncCallCount = 0
    private(set) var successfulWriteCount = 0

    init(
        currentLocation: HerdSharingAccess.BridgeLocation,
        currentFingerprint: String,
        failAfterFirstWrite: Bool
    ) {
        self.currentLocation = currentLocation
        self.currentFingerprint = currentFingerprint
        self.failAfterFirstWrite = failAfterFirstWrite
    }

    func publicIDRepairFingerprint(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> String {
        guard currentLocation == expectedLocation else {
            throw HerdSharingPublicIDRepairBridgeError.targetChanged(
                expected: restartBridgeDescription(expectedLocation),
                actual: restartBridgeDescription(currentLocation)
            )
        }
        return currentFingerprint
    }

    func importPublicIDRepairBridgeRecordsIntoSwiftData(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String,
        importer: any HerdSharingImportApplying,
        report: PublicIDRepairReport
    ) async throws -> HerdSharingBridgeImportResult {
        throw BridgeRestartTestError.unexpectedImport
    }

    func syncPublicIDRepairBridgeRecordsFromSnapshot(
        _ export: HerdSharingSwiftDataExport,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws -> HerdSharingBridgeExportResult {
        syncCallCount += 1
        guard currentLocation == expectedLocation else {
            throw HerdSharingPublicIDRepairBridgeError.targetChanged(
                expected: restartBridgeDescription(expectedLocation),
                actual: restartBridgeDescription(currentLocation)
            )
        }

        let desiredFingerprint = export.snapshot.publicIDRepairFingerprint
        if currentFingerprint == desiredFingerprint {
            return restartExportResult(for: export.herd)
        }
        guard currentFingerprint == expectedFingerprint else {
            throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: export.herd.publicID
            )
        }

        currentFingerprint = desiredFingerprint
        successfulWriteCount += 1
        if failAfterFirstWrite {
            failAfterFirstWrite = false
            throw BridgeRestartTestError.injectedPostWriteCrash
        }
        return restartExportResult(for: export.herd)
    }
}

private actor RestartHerdInventory: PublicIDRepairHerdInventoryReading {
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
private final class RestartBoundaryExporter: PublicIDRepairBridgeExporting {
    let baselineFingerprint = "missing-bridge-baseline"
    private let onImport: (@MainActor (HerdSummary) async -> Void)?
    private(set) var importedHerdIDs: [UUID] = []
    private(set) var exportedHerdIDs: [UUID] = []
    private(set) var receivedTargets: [PublicIDRepairBridgeTargetIdentity] = []
    private(set) var retiredHerdIDs: [UUID] = []
    private(set) var retiredTargets: [PublicIDRepairBridgeTargetIdentity] = []

    init(onImport: (@MainActor (HerdSummary) async -> Void)? = nil) {
        self.onImport = onImport
    }

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        baselineFingerprint
    }

    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight {
        let identities: Set<PublicIDRepairBridgeRecordIdentity>
        if access.bridgeLocation == .bridgeRecordMissing {
            identities = []
        } else {
            identities = [
                PublicIDRepairBridgeRecordIdentity(
                    step: .animals,
                    publicID: restartAffectedSourceID
                )
            ]
        }
        return PublicIDRepairBridgePreflight(
            fingerprint: baselineFingerprint,
            recordIdentities: identities
        )
    }

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        guard expectedFingerprint == baselineFingerprint else {
            throw PublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }
        importedHerdIDs.append(herd.publicID)
        if let onImport {
            await onImport(herd)
        }
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        guard target.bridgeFingerprint == baselineFingerprint else {
            throw PublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }
        exportedHerdIDs.append(herd.publicID)
        receivedTargets.append(target)
        return .empty
    }

    func retirePreparedBridge(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws {
        guard target.herdPublicID == herd.publicID,
              target.bridgeFingerprint == baselineFingerprint else {
            throw PublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }
        retiredHerdIDs.append(herd.publicID)
        retiredTargets.append(target)
    }
}

@MainActor
private final class RestartSharingRepository: HerdSharingRepository {
    var access: HerdSharingAccess

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
        restartActionResult("start")
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        restartActionResult("accept")
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        restartActionResult("import")
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        restartActionResult("delete")
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        restartActionResult("restore")
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        restartActionResult("sync")
    }

    private func restartActionResult(_ value: String) -> HerdSharingActionResult {
        HerdSharingActionResult(title: value, message: value)
    }
}

private func restartBridgeDescription(
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
