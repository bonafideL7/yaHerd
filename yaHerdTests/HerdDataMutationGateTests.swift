import XCTest

@testable import yaHerd

@MainActor
final class HerdDataMutationGateTests: XCTestCase {
    func testRepairBlocksRepositoryWritesAndSynchronization() throws {
        let defaults = isolatedDefaults()
        let gate = HerdDataMutationGate(defaults: defaults)
        let writePolicy = HerdCollaborationWritePolicy(mutationGate: gate)
        let repairToken = try gate.beginPublicIDRepair()

        XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .animal))
        XCTAssertThrowsError(try gate.beginSynchronization())

        gate.endPublicIDRepair(repairToken)
        XCTAssertNoThrow(try writePolicy.validateCanWrite(reason: .animal))
        let syncToken = try gate.beginSynchronization()
        gate.endSynchronization(syncToken)
    }

    func testActiveSynchronizationBlocksRepair() throws {
        let gate = HerdDataMutationGate(defaults: isolatedDefaults())
        let syncToken = try gate.beginSynchronization()

        XCTAssertThrowsError(try gate.beginPublicIDRepair())

        gate.endSynchronization(syncToken)
        let repairToken = try gate.beginPublicIDRepair()
        gate.endPublicIDRepair(repairToken)
    }

    func testActiveSyncDataResetBlocksWritesSynchronizationAndRepair() throws {
        let gate = HerdDataMutationGate(defaults: isolatedDefaults())
        let writePolicy = HerdCollaborationWritePolicy(mutationGate: gate)
        let resetToken = try gate.beginSyncDataReset()

        XCTAssertTrue(gate.isSyncDataResetInProgress)
        XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .animal))
        XCTAssertThrowsError(try gate.beginSynchronization())
        XCTAssertThrowsError(try gate.beginPublicIDRepair())
        XCTAssertThrowsError(try gate.beginSyncDataReset())

        gate.endSyncDataReset(resetToken)
        XCTAssertFalse(gate.isSyncDataResetInProgress)
        XCTAssertNoThrow(try writePolicy.validateCanWrite(reason: .animal))
    }

    func testDirectSharedImportIsBlockedWhileRepairWorkerIsSuspended() async throws {
        let gate = HerdDataMutationGate(defaults: isolatedDefaults())
        let worker = SuspendedPublicIDRepairService()
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: gate
        )
        let baseRepository = RecordingHerdSharingRepository()
        let gatedRepository = GatedHerdSharingRepository(
            base: baseRepository,
            mutationGate: gate
        )

        let repairTask = Task { @MainActor in
            try await service.repair()
        }
        await worker.waitUntilRepairStarts()

        do {
            _ = try await gatedRepository.importSharedBridgeData(
                herd: nil,
                storageMode: .iCloud
            )
            XCTFail("Expected direct bridge import to be blocked")
        } catch {
            XCTAssertEqual(baseRepository.importCallCount, 0)
        }

        await worker.finishRepair()
        _ = try await repairTask.value
        XCTAssertFalse(gate.isPublicIDRepairInProgress)
    }

    func testCoordinatedRepairJournalsBeforeCommitThenExportsWithoutNormalSync() async throws {
        let events = RepairEventRecorder()
        let gate = HerdDataMutationGate(defaults: isolatedDefaults())
        let worker = RecordingPublicIDRepairService(events: events)
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: events)
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: gate,
            bridgeCoordinator: bridge
        )

        _ = try await service.repair()

        XCTAssertEqual(
            events.events,
            ["prepare-import", "repair-will-commit", "repair-save", "export-only-converge"]
        )
        let repairCallCount = await worker.repairCallCountValue()
        XCTAssertEqual(repairCallCount, 1)
        XCTAssertEqual(bridge.prepareCallCount, 1)
        XCTAssertEqual(bridge.convergeCallCount, 1)
        XCTAssertFalse(gate.requiresBridgeConvergence)
    }

    func testFailedBridgeConvergencePersistsGateAndRetrySkipsSecondRepair() async throws {
        let defaults = isolatedDefaults()
        let events = RepairEventRecorder()
        let gate = HerdDataMutationGate(defaults: defaults)
        let worker = RecordingPublicIDRepairService(events: events)
        let bridge = RecordingPublicIDRepairBridgeCoordinator(
            events: events,
            convergenceFailuresRemaining: 1
        )
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: gate,
            bridgeCoordinator: bridge
        )
        let writePolicy = HerdCollaborationWritePolicy(mutationGate: gate)

        do {
            _ = try await service.repair()
            XCTFail("Expected first bridge convergence to fail")
        } catch {
            XCTAssertTrue(gate.requiresBridgeConvergence)
            XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .animal))
            XCTAssertThrowsError(try gate.beginSynchronization())
        }

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        XCTAssertTrue(relaunchedGate.requiresBridgeConvergence)

        let retryService = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )
        _ = try await retryService.repair()

        let repairCallCount = await worker.repairCallCountValue()
        XCTAssertEqual(repairCallCount, 1)
        XCTAssertEqual(bridge.prepareCallCount, 1)
        XCTAssertEqual(bridge.convergeCallCount, 2)
        XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
        XCTAssertNoThrow(try HerdCollaborationWritePolicy(
            mutationGate: relaunchedGate
        ).validateCanWrite(reason: .animal))
    }

    func testRelaunchBetweenLocalSaveAndBridgePhaseConvergesWithoutRepeatingRepair() async throws {
        let defaults = isolatedDefaults()
        let preparation = testICloudPreparation()
        let report = makeTestRepairReport()
        let firstGate = HerdDataMutationGate(defaults: defaults)

        // This is the process-death window: the pre-commit journal exists, the SwiftData
        // save has completed, but the coordinator never advanced the journal phase.
        try firstGate.requireLocalCommitCompletion(
            preparation: preparation,
            report: report,
            resolutions: []
        )

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let events = RepairEventRecorder()
        let worker = RecordingPublicIDRepairService(
            events: events,
            commitState: .committed
        )
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: events)
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )

        let resumedReport = try await service.repair()

        XCTAssertEqual(resumedReport, report)
        let repairCallCount = await worker.repairCallCountValue()
        XCTAssertEqual(repairCallCount, 0)
        XCTAssertEqual(bridge.convergeCallCount, 1)
        XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
    }

    func testPostSaveCrashWithNewDuplicateDoesNotRetryOrClearCommittedRepair() async throws {
        let defaults = isolatedDefaults()
        let preparation = testICloudPreparation()
        let report = makeTestRepairReport()
        let firstGate = HerdDataMutationGate(defaults: defaults)
        try firstGate.requireLocalCommitCompletion(
            preparation: preparation,
            report: report,
            resolutions: []
        )

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let events = RepairEventRecorder()
        let worker = RecordingPublicIDRepairService(
            events: events,
            scanHasDuplicates: true,
            commitState: .committed,
            repairShouldFail: true
        )
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: events)
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )

        _ = try await service.repair()

        XCTAssertEqual(await worker.scanCallCountValue(), 0)
        XCTAssertEqual(await worker.repairCallCountValue(), 0)
        XCTAssertEqual(bridge.convergeCallCount, 1)
        XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
    }

    func testRelaunchBeforeLocalSaveRetriesRepairUsingPersistedJournal() async throws {
        let defaults = isolatedDefaults()
        let preparation = testICloudPreparation()
        let report = makeTestRepairReport()
        let firstGate = HerdDataMutationGate(defaults: defaults)
        try firstGate.requireLocalCommitCompletion(
            preparation: preparation,
            report: report,
            resolutions: []
        )

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let events = RepairEventRecorder()
        let worker = RecordingPublicIDRepairService(
            events: events,
            commitState: .notCommitted
        )
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: events)
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )

        _ = try await service.repair()

        let repairCallCount = await worker.repairCallCountValue()
        XCTAssertEqual(repairCallCount, 1)
        XCTAssertEqual(bridge.convergeCallCount, 1)
        XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
    }

    func testFailedRetryClearsPreCommitJournalOnlyWhenNotCommittedIsProven() async throws {
        let defaults = isolatedDefaults()
        let firstGate = HerdDataMutationGate(defaults: defaults)
        try firstGate.requireLocalCommitCompletion(
            preparation: testICloudPreparation(),
            report: makeTestRepairReport(),
            resolutions: []
        )

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let worker = RecordingPublicIDRepairService(
            events: RepairEventRecorder(),
            commitState: .notCommitted,
            repairShouldFail: true
        )
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: RepairEventRecorder())
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )

        do {
            _ = try await service.repair()
            XCTFail("Expected the retry to fail")
        } catch GateTestError.injectedRepairFailure {
            XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
            XCTAssertEqual(bridge.convergeCallCount, 0)
        }
    }

    func testIndeterminateCommitStateFailsClosedAndKeepsJournal() async throws {
        let defaults = isolatedDefaults()
        let firstGate = HerdDataMutationGate(defaults: defaults)
        try firstGate.requireLocalCommitCompletion(
            preparation: testICloudPreparation(),
            report: makeTestRepairReport(),
            resolutions: []
        )

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let worker = RecordingPublicIDRepairService(
            events: RepairEventRecorder(),
            commitState: .indeterminate
        )
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: RepairEventRecorder())
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )

        do {
            _ = try await service.repair()
            XCTFail("Expected recovery to fail closed")
        } catch let error as CoordinatedPublicIDRepairError {
            XCTAssertEqual(error, .localCommitStateIndeterminate)
            XCTAssertTrue(relaunchedGate.requiresBridgeConvergence)
            XCTAssertEqual(bridge.convergeCallCount, 0)
        }
    }

    func testPendingBridgeConvergenceBlocksDestructiveSyncResetBeforeCloudKitMutation() async throws {
        let defaults = isolatedDefaults()
        let gate = HerdDataMutationGate(defaults: defaults)
        try gate.requireLocalCommitCompletion(
            preparation: testICloudPreparation(),
            report: makeTestRepairReport(),
            resolutions: []
        )
        try gate.markLocalCommitSucceeded()

        let settings = ApplicationSettings(
            store: InMemoryApplicationSettingsStore(values: [
                ApplicationSettingKey.syncMode.rawValue: SyncMode.iCloud.rawValue
            ])
        )
        let synchronizer = RecordingSettingsSynchronizer()
        let resetService = SyncDataResetService(
            applicationSettings: settings,
            settingsSynchronizer: synchronizer,
            mutationGate: gate,
            cloudKitContainerIdentifier: "iCloud.com.example.gate-test"
        )

        do {
            _ = try await resetService.deleteICloudSyncData()
            XCTFail("Expected reset to be blocked before CloudKit deletion")
        } catch let error as HerdDataMutationGate.GateError {
            XCTAssertEqual(error, .bridgeConvergenceRequired(reason: nil))
            XCTAssertEqual(settings.syncMode, .iCloud)
            XCTAssertEqual(synchronizer.deleteCloudSettingsCallCount, 0)
            XCTAssertTrue(gate.requiresBridgeConvergence)
        }
    }

    func testPendingICloudConvergenceCannotBeClearedByLocalOnlyRelaunch() async throws {
        let defaults = isolatedDefaults()
        let preparation = testICloudPreparation()
        let report = makeTestRepairReport()
        let firstGate = HerdDataMutationGate(defaults: defaults)
        try firstGate.requireLocalCommitCompletion(
            preparation: preparation,
            report: report,
            resolutions: []
        )
        try firstGate.markLocalCommitSucceeded()

        let localGate = HerdDataMutationGate(defaults: defaults)
        let worker = RecordingPublicIDRepairService(events: RepairEventRecorder())
        let localService = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: localGate,
            bridgeCoordinator: LocalOnlyPublicIDRepairBridgeCoordinator()
        )

        do {
            _ = try await localService.repair()
            XCTFail("Expected Local Only launch to preserve the pending iCloud requirement")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .bridgeIdentityMismatch(expected: .iCloud, actual: .localOnly)
            )
        }
        XCTAssertTrue(localGate.requiresBridgeConvergence)

        let iCloudGate = HerdDataMutationGate(defaults: defaults)
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: RepairEventRecorder())
        let iCloudService = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: iCloudGate,
            bridgeCoordinator: bridge
        )
        _ = try await iCloudService.repair()

        XCTAssertEqual(bridge.convergeCallCount, 1)
        XCTAssertFalse(iCloudGate.requiresBridgeConvergence)
    }

    func testDefaultBridgeCoordinatorPreparesAndConvergesEveryPreparedHerd() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = HerdSummary(
            publicID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            name: "First",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let second = HerdSummary(
            publicID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            name: "Second",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let inventory = RecordingHerdInventory(herds: [first, second])
        let repository = RecordingHerdSharingRepository()
        let exporter = RecordingPublicIDRepairBridgeExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        XCTAssertEqual(Set(preparation.herdPublicIDs), Set([first.publicID, second.publicID]))
        XCTAssertEqual(Set(repository.importedHerdIDs), Set([first.publicID, second.publicID]))
        XCTAssertTrue(preparation.targets.allSatisfy { $0.bridgeFingerprint != nil })

        try await coordinator.convergeAfterRepair(preparation: preparation)

        XCTAssertEqual(
            Set(exporter.exportedHerdIDs),
            Set([first.publicID, second.publicID])
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "HerdDataMutationGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func testICloudPreparation() -> PublicIDRepairBridgePreparation {
        PublicIDRepairBridgePreparation(
            identity: .iCloud,
            herdPublicIDs: [UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!]
        )
    }
}

private enum GateTestError: Error {
    case injectedRepairFailure
}

private actor SuspendedPublicIDRepairService: PublicIDRepairTransactionalService {
    private var hasStartedRepair = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func scan() async throws -> PublicIDRepairAssessment {
        duplicateAssessment()
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        hasStartedRepair = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
        let report = makeTestRepairReport()
        try await willCommit(report)
        return report
    }

    func waitUntilRepairStarts() async {
        guard !hasStartedRepair else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishRepair() {
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class RepairEventRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private actor RecordingPublicIDRepairService: PublicIDRepairTransactionalService {
    private let events: RepairEventRecorder
    private var scanHasDuplicates: Bool
    private var commitStateValue: PublicIDRepairCommitState
    private let repairShouldFail: Bool
    private var repairCallCount = 0
    private var scanCallCount = 0

    init(
        events: RepairEventRecorder,
        scanHasDuplicates: Bool = true,
        commitState: PublicIDRepairCommitState = .notCommitted,
        repairShouldFail: Bool = false
    ) {
        self.events = events
        self.scanHasDuplicates = scanHasDuplicates
        self.commitStateValue = commitState
        self.repairShouldFail = repairShouldFail
    }

    func scan() async throws -> PublicIDRepairAssessment {
        scanCallCount += 1
        return scanHasDuplicates ? duplicateAssessment() : emptyAssessment()
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        repairCallCount += 1
        await events.record("repair-will-commit")
        let report = makeTestRepairReport()
        try await willCommit(report)
        if repairShouldFail {
            throw GateTestError.injectedRepairFailure
        }
        await events.record("repair-save")
        scanHasDuplicates = false
        commitStateValue = .committed
        return report
    }

    func commitState(for report: PublicIDRepairReport) async throws -> PublicIDRepairCommitState {
        commitStateValue
    }

    func repairCallCountValue() -> Int {
        repairCallCount
    }

    func scanCallCountValue() -> Int {
        scanCallCount
    }
}

@MainActor
private final class RecordingPublicIDRepairBridgeCoordinator: PublicIDRepairBridgeCoordinating {
    let bridgeIdentity: PublicIDRepairBridgeIdentity = .iCloud

    private let events: RepairEventRecorder
    private var convergenceFailuresRemaining: Int
    private(set) var prepareCallCount = 0
    private(set) var convergeCallCount = 0

    init(
        events: RepairEventRecorder,
        convergenceFailuresRemaining: Int = 0
    ) {
        self.events = events
        self.convergenceFailuresRemaining = convergenceFailuresRemaining
    }

    func prepareForRepair() async throws -> PublicIDRepairBridgePreparation {
        prepareCallCount += 1
        events.record("prepare-import")
        return PublicIDRepairBridgePreparation(
            identity: .iCloud,
            herdPublicIDs: [UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!]
        )
    }

    func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation
    ) async throws {
        convergeCallCount += 1
        events.record("export-only-converge")
        if convergenceFailuresRemaining > 0 {
            convergenceFailuresRemaining -= 1
            throw PublicIDRepairBridgeError.reconciliationFailed(
                herdPublicID: preparation.herdPublicIDs[0],
                summary: "Injected failure"
            )
        }
    }
}

private actor RecordingHerdInventory: PublicIDRepairHerdInventoryReading {
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
private final class RecordingPublicIDRepairBridgeExporter: PublicIDRepairBridgeExporting {
    private(set) var exportedHerdIDs: [UUID] = []

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        "fingerprint|\(herd.publicID.uuidString)|\(access.locationDescription)"
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        guard target.bridgeFingerprint != nil else {
            throw PublicIDRepairBridgeError.bridgeBaselineUnavailable(
                herdPublicID: herd.publicID
            )
        }
        exportedHerdIDs.append(herd.publicID)
        return .empty
    }
}

@MainActor
private final class RecordingHerdSharingRepository: HerdSharingRepository {
    private(set) var importCallCount = 0
    private(set) var importedHerdIDs: [UUID] = []

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
        .ownerPrivateStore(participantCount: 1)
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
        if let herd { importedHerdIDs.append(herd.publicID) }
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

    private func result(_ title: String) -> HerdSharingActionResult {
        HerdSharingActionResult(title: title, message: title)
    }
}

@MainActor
private final class RecordingSettingsSynchronizer: AppSettingsSyncing {
    private(set) var deleteCloudSettingsCallCount = 0

    func startIfNeeded(syncMode: SyncMode) {}
    func stop() {}
    func refreshFromICloudIfStarted() {}

    func deleteCloudSettings() -> Int {
        deleteCloudSettingsCallCount += 1
        return 0
    }
}

private func emptyAssessment() -> PublicIDRepairAssessment {
    PublicIDRepairAssessment(scannedAt: .now, entities: [])
}

private func duplicateAssessment() -> PublicIDRepairAssessment {
    PublicIDRepairAssessment(
        scannedAt: .now,
        entities: [
            PublicIDRepairEntityAssessment(
                entityType: .animal,
                scannedRecordCount: 2,
                duplicateGroupCount: 1,
                duplicateRecordCount: 1
            )
        ]
    )
}

private func makeTestRepairReport() -> PublicIDRepairReport {
    PublicIDRepairReport(
        completedAt: .now,
        assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
        replacements: [],
        referenceUpdates: [],
        backupFilename: "test-backup.json",
        backupPath: "/tmp/test-backup.json",
        validationIssueCount: 0
    )
}
