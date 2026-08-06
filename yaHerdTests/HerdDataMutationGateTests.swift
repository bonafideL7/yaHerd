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

    func testCoordinatedRepairImportsThenRepairsThenExportsWithoutNormalSync() async throws {
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

        XCTAssertEqual(events.events, ["prepare-import", "repair", "export-only-converge"])
        XCTAssertEqual(worker.repairCallCount, 1)
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

        XCTAssertEqual(worker.repairCallCount, 1)
        XCTAssertEqual(bridge.prepareCallCount, 1)
        XCTAssertEqual(bridge.convergeCallCount, 2)
        XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
        XCTAssertNoThrow(try HerdCollaborationWritePolicy(
            mutationGate: relaunchedGate
        ).validateCanWrite(reason: .animal))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "HerdDataMutationGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor SuspendedPublicIDRepairService: PublicIDRepairService {
    private var hasStartedRepair = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func scan() async throws -> PublicIDRepairAssessment {
        PublicIDRepairAssessment(scannedAt: .now, entities: [])
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport {
        hasStartedRepair = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
        return makeTestRepairReport()
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
    var events: [String] = []
}

@MainActor
private final class RecordingPublicIDRepairService: PublicIDRepairService {
    private let events: RepairEventRecorder
    private(set) var repairCallCount = 0

    init(events: RepairEventRecorder) {
        self.events = events
    }

    func scan() async throws -> PublicIDRepairAssessment {
        PublicIDRepairAssessment(scannedAt: .now, entities: [])
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport {
        repairCallCount += 1
        events.events.append("repair")
        return makeTestRepairReport()
    }
}

@MainActor
private final class RecordingPublicIDRepairBridgeCoordinator: PublicIDRepairBridgeCoordinating {
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

    func prepareForRepair() async throws -> Bool {
        prepareCallCount += 1
        events.events.append("prepare-import")
        return true
    }

    func convergeAfterRepair() async throws {
        convergeCallCount += 1
        events.events.append("export-only-converge")
        if convergenceFailuresRemaining > 0 {
            convergenceFailuresRemaining -= 1
            throw PublicIDRepairBridgeError.reconciliationFailed("Injected failure")
        }
    }
}

@MainActor
private final class RecordingHerdSharingRepository: HerdSharingRepository {
    private(set) var importCallCount = 0

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
