import SwiftData
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

    func testCoordinatedRepairJournalsBeforeCommitThenConvergesBridge() async throws {
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
            ["prepare", "repair-will-commit", "repair-save", "converge"]
        )
        let repairCallCount = await worker.repairCallCountValue()
        XCTAssertEqual(repairCallCount, 1)
        XCTAssertEqual(bridge.prepareCallCount, 1)
        XCTAssertEqual(bridge.convergeCallCount, 1)
        XCTAssertFalse(gate.requiresBridgeConvergence)
    }

    func testBridgeResolutionPersistsAcrossRetryWithoutRepeatingLocalRepair() async throws {
        let defaults = isolatedDefaults()
        let events = RepairEventRecorder()
        let issue = makeBridgeChoiceIssue()
        let gate = HerdDataMutationGate(defaults: defaults)
        let worker = RecordingPublicIDRepairService(events: events)
        let bridge = RecordingPublicIDRepairBridgeCoordinator(
            events: events,
            requiredIssue: issue
        )
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: gate,
            bridgeCoordinator: bridge
        )
        let writePolicy = HerdCollaborationWritePolicy(mutationGate: gate)

        do {
            _ = try await service.repair()
            XCTFail("Expected first convergence to require a bridge repair choice")
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            XCTAssertEqual(error.issues, [issue])
            XCTAssertTrue(gate.requiresBridgeConvergence)
            XCTAssertThrowsError(try writePolicy.validateCanWrite(reason: .animal))
            XCTAssertThrowsError(try gate.beginSynchronization())
        }

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let retryService = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )
        let assessment = try await retryService.scan()
        XCTAssertEqual(assessment.unresolvedReferences, [issue])
        let selected = try XCTUnwrap(issue.candidates.last)
        let finalReport = try await retryService.repair(
            resolutions: [
                PublicIDRepairReferenceResolution(
                    unresolvedReferenceID: issue.id,
                    selectedCandidateStableRecordIdentifier: selected.stableRecordIdentifier
                )
            ]
        )

        XCTAssertTrue(
            finalReport.referenceUpdates.contains {
                $0.stableRecordIdentifier == issue.stableRecordIdentifier
                    && $0.fieldName == issue.fieldName
                    && $0.repairedPublicID == selected.resultingPublicID
            }
        )
        let repairCallCount = await worker.repairCallCountValue()
        XCTAssertEqual(repairCallCount, 1)
        XCTAssertEqual(bridge.prepareCallCount, 1)
        XCTAssertEqual(bridge.convergeCallCount, 2)
        XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
        XCTAssertNoThrow(try HerdCollaborationWritePolicy(
            mutationGate: relaunchedGate
        ).validateCanWrite(reason: .animal))
    }

    func testAuthoritativeBridgeOwnerIsPersistedAutomaticallyBeforeRetryingConvergence() async throws {
        let issue = makeAuthoritativeBridgeOwnerIssue()
        let events = RepairEventRecorder()
        let gate = HerdDataMutationGate(defaults: isolatedDefaults())
        let worker = RecordingPublicIDRepairService(events: events)
        let bridge = RecordingPublicIDRepairBridgeCoordinator(
            events: events,
            requiredIssue: issue
        )
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: gate,
            bridgeCoordinator: bridge
        )

        let finalReport = try await service.repair()

        let resolution = try XCTUnwrap(finalReport.bridgeCollisionResolutions?.first)
        let owner = try XCTUnwrap(issue.candidates.first)
        XCTAssertEqual(resolution.entityType, issue.entityType)
        XCTAssertEqual(resolution.retainedPublicID, issue.referencedPublicID)
        XCTAssertEqual(resolution.selectedHerdPublicID, owner.resultingPublicID)
        XCTAssertEqual(bridge.convergeCallCount, 2)
        XCTAssertFalse(gate.requiresBridgeConvergence)
    }

    func testPreparationGrowthDoesNotExpandBridgeCollisionOwnershipScope() throws {
        let retainedID = UUID(uuidString: "C1111111-1111-4111-8111-111111111111")!
        let herdA = UUID(uuidString: "C2222222-2222-4222-8222-222222222222")!
        let herdB = UUID(uuidString: "C3333333-3333-4333-8333-333333333333")!
        let herdC = UUID(uuidString: "C4444444-4444-4444-8444-444444444444")!
        let report = PublicIDRepairReport(
            completedAt: .now,
            assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
            replacements: [],
            referenceUpdates: [],
            backupFilename: "owner-scope.json",
            backupPath: "/tmp/owner-scope.json",
            validationIssueCount: 0,
            bridgeCollisionResolutions: [
                PublicIDRepairBridgeCollisionResolution(
                    entityType: .animal,
                    retainedPublicID: retainedID,
                    selectedHerdPublicID: herdA,
                    herdPublicIDs: [herdA, herdB]
                )
            ]
        )
        let gate = HerdDataMutationGate(defaults: isolatedDefaults())
        try gate.requireLocalCommitCompletion(
            preparation: PublicIDRepairBridgePreparation(
                identity: .iCloud,
                herdPublicIDs: [herdA, herdB]
            ),
            report: report,
            resolutions: []
        )
        try gate.markLocalCommitSucceeded()

        try gate.updatePendingPreparation(
            PublicIDRepairBridgePreparation(
                identity: .iCloud,
                herdPublicIDs: [herdA, herdB, herdC]
            )
        )

        let persisted = try XCTUnwrap(
            gate.pendingBridgeConvergenceReport?.bridgeCollisionResolutions?.first
        )
        XCTAssertEqual(persisted.selectedHerdPublicID, herdA)
        XCTAssertEqual(Set(persisted.herdPublicIDs), Set([herdA, herdB]))
    }

    func testRelaunchBetweenLocalSaveAndBridgePhaseConvergesWithoutRepeatingRepair() async throws {
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

    func testPostSaveCrashWithNewDuplicateFailedChainedRepairKeepsCommittedRepairGated() async throws {
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
        let worker = RecordingPublicIDRepairService(
            events: RepairEventRecorder(),
            scanHasDuplicates: true,
            commitState: .committed,
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
            XCTFail("Expected the newly required chained repair to fail")
        } catch GateTestError.injectedRepairFailure {
            let scanCallCount = await worker.scanCallCountValue()
            let repairCallCount = await worker.repairCallCountValue()
            XCTAssertEqual(scanCallCount, 1)
            XCTAssertEqual(repairCallCount, 1)
            XCTAssertEqual(bridge.convergeCallCount, 0)
            XCTAssertTrue(relaunchedGate.requiresBridgeConvergence)
            XCTAssertThrowsError(try relaunchedGate.beginSynchronization())
        }
    }

    func testDuplicateDetectedAfterConvergenceIsRepairedAndReconvergedBeforeGateClears() async throws {
        let events = RepairEventRecorder()
        let gate = HerdDataMutationGate(defaults: isolatedDefaults())
        let worker = RecordingPublicIDRepairService(
            events: events,
            scanDuplicateSequence: [false, true, false, false]
        )
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: events)
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: gate,
            bridgeCoordinator: bridge
        )

        _ = try await service.repair()

        let repairCallCount = await worker.repairCallCountValue()
        let scanCallCount = await worker.scanCallCountValue()
        XCTAssertEqual(bridge.convergeCallCount, 2)
        XCTAssertEqual(repairCallCount, 2)
        XCTAssertEqual(scanCallCount, 4)
        XCTAssertFalse(gate.requiresBridgeConvergence)
        XCTAssertEqual(
            events.events,
            [
                "prepare",
                "repair-will-commit", "repair-save",
                "converge",
                "repair-will-commit", "repair-save",
                "converge",
            ]
        )
    }

    func testConcretePendingRepairChainsNewLocalDuplicateBeforeConvergence() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let repairedDuplicateID = UUID(uuidString: "71717171-7171-4171-8171-717171717171")!
        let herd = Herd(name: "Commit witness", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        let north = Pasture(publicID: repairedDuplicateID, name: "North")
        north.herd = herd
        context.insert(north)
        let south = Pasture(publicID: repairedDuplicateID, name: "South")
        south.herd = herd
        context.insert(south)
        try context.save()

        let worker = SwiftDataPublicIDRepairService(modelContainer: container)
        let firstReport = try await worker.repair()
        defer { try? FileManager.default.removeItem(atPath: firstReport.backupPath) }
        let firstCommitState = try await worker.commitState(for: firstReport)
        XCTAssertEqual(firstCommitState, .committed)

        let defaults = isolatedDefaults()
        let firstGate = HerdDataMutationGate(defaults: defaults)
        try firstGate.requireLocalCommitCompletion(
            preparation: testICloudPreparation(),
            report: firstReport,
            resolutions: []
        )

        let lateContext = ModelContext(container)
        let persistedHerd = try XCTUnwrap(
            lateContext.fetch(FetchDescriptor<Herd>()).first
        )
        let unrelatedDuplicateID = UUID(uuidString: "72727272-7272-4272-8272-727272727272")!
        let east = Pasture(publicID: unrelatedDuplicateID, name: "East")
        east.herd = persistedHerd
        lateContext.insert(east)
        let west = Pasture(publicID: unrelatedDuplicateID, name: "West")
        west.herd = persistedHerd
        lateContext.insert(west)
        try lateContext.save()

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let bridge = RecordingPublicIDRepairBridgeCoordinator(events: RepairEventRecorder())
        let service = CoordinatedPublicIDRepairService(
            worker: worker,
            mutationGate: relaunchedGate,
            bridgeCoordinator: bridge
        )

        let finalReport = try await service.repair()
        defer {
            for backup in finalReport.backupReferences
            where backup.path != firstReport.backupPath {
                try? FileManager.default.removeItem(atPath: backup.path)
            }
        }

        let verificationContext = ModelContext(container)
        let pastures = try verificationContext.fetch(FetchDescriptor<Pasture>())
        XCTAssertEqual(Set(pastures.map(\.publicID)).count, pastures.count)
        XCTAssertEqual(finalReport.replacements.count, 2)
        XCTAssertEqual(finalReport.backupReferences.count, 2)
        XCTAssertNotEqual(finalReport.backupPath, firstReport.backupPath)
        XCTAssertEqual(finalReport.backupReferences.last?.path, finalReport.backupPath)
        XCTAssertTrue(
            finalReport.priorBackups?.contains {
                $0.path == firstReport.backupPath
                    && $0.filename == firstReport.backupFilename
            } == true
        )
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

    func testIndeterminateCommitStateWithNonRecoveringWorkerFailsClosedAndKeepsJournal() async throws {
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
            XCTFail("Expected unsupported fake recovery to remain gated")
        } catch let error as PublicIDRepairRecoveryError {
            XCTAssertEqual(error, .unsupported)
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

    func testDefaultBridgeCoordinatorObservesPreparedHerdsWithoutMutatingUnaffectedBridges() async throws {
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
        XCTAssertEqual(repository.importedHerdIDs, [])
        XCTAssertTrue(preparation.targets.allSatisfy { $0.bridgeFingerprint != nil })

        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: makeTestRepairReport()
        )

        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
        XCTAssertEqual(repository.importedHerdIDs, [])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "HerdDataMutationGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // The DEBUG journal path intentionally follows the UserDefaults object identity so a
        // second gate using the same defaults instance models a relaunch. XCTest can later reuse
        // that object address for a different isolated suite, so remove any prior test artifact
        // before returning this newly created defaults instance.
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yaHerd-PublicIDRepairTests", isDirectory: true)
            .appendingPathComponent(
                "\(ObjectIdentifier(defaults).hashValue)-PublicIDRepairPendingState.v3.json"
            )
        try? FileManager.default.removeItem(at: journalURL)
        try? FileManager.default.removeItem(
            at: journalURL.appendingPathExtension("verified-recovery")
        )
        return defaults
    }

    private func testICloudPreparation() -> PublicIDRepairBridgePreparation {
        PublicIDRepairBridgePreparation(
            identity: .iCloud,
            herdPublicIDs: [UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!]
        )
    }
}

private enum GateTestError: Error, Sendable {
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
    private var scanDuplicateSequence: [Bool]
    private var commitStateValue: PublicIDRepairCommitState
    private let repairShouldFail: Bool
    private var repairCallCount = 0
    private var scanCallCount = 0

    init(
        events: RepairEventRecorder,
        scanHasDuplicates: Bool = false,
        scanDuplicateSequence: [Bool] = [],
        commitState: PublicIDRepairCommitState = .notCommitted,
        repairShouldFail: Bool = false
    ) {
        self.events = events
        self.scanHasDuplicates = scanHasDuplicates
        self.scanDuplicateSequence = scanDuplicateSequence
        self.commitStateValue = commitState
        self.repairShouldFail = repairShouldFail
    }

    func scan() async throws -> PublicIDRepairAssessment {
        scanCallCount += 1
        let hasDuplicates = scanDuplicateSequence.isEmpty
            ? scanHasDuplicates
            : scanDuplicateSequence.removeFirst()
        return hasDuplicates ? duplicateAssessment() : emptyAssessment()
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
    private let requiredIssue: PublicIDRepairUnresolvedReference?
    private(set) var prepareCallCount = 0
    private(set) var convergeCallCount = 0

    init(
        events: RepairEventRecorder,
        convergenceFailuresRemaining: Int = 0,
        requiredIssue: PublicIDRepairUnresolvedReference? = nil
    ) {
        self.events = events
        self.convergenceFailuresRemaining = convergenceFailuresRemaining
        self.requiredIssue = requiredIssue
    }

    func prepareForRepair() async throws -> PublicIDRepairBridgePreparation {
        prepareCallCount += 1
        events.record("prepare")
        return PublicIDRepairBridgePreparation(
            identity: .iCloud,
            herdPublicIDs: [UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!]
        )
    }

    func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws {
        convergeCallCount += 1
        events.record("converge")

        if let requiredIssue {
            let selectedCandidate = requiredIssue.candidates.last
            let isResolved = selectedCandidate.map { selected in
                if requiredIssue.kind == .bridgeRecordOwner {
                    return report.bridgeCollisionResolutions?.contains {
                        $0.entityType == requiredIssue.entityType
                            && $0.retainedPublicID == requiredIssue.referencedPublicID
                            && $0.selectedHerdPublicID == selected.resultingPublicID
                    } == true
                }
                return report.referenceUpdates.contains {
                    $0.stableRecordIdentifier == requiredIssue.stableRecordIdentifier
                        && $0.fieldName == requiredIssue.fieldName
                        && $0.repairedPublicID == selected.resultingPublicID
                }
            } ?? false
            if !isResolved {
                throw PublicIDRepairBridgeResolutionRequired(issues: [requiredIssue])
            }
        }

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
    private(set) var importedHerdIDs: [UUID] = []
    private(set) var exportedHerdIDs: [UUID] = []

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        "fingerprint|\(herd.publicID.uuidString)|\(access.locationDescription)"
    }

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        XCTAssertFalse(expectedFingerprint.isEmpty)
        importedHerdIDs.append(herd.publicID)
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

private func makeBridgeChoiceIssue() -> PublicIDRepairUnresolvedReference {
    let retainedID = UUID(uuidString: "B1111111-1111-4111-8111-111111111111")!
    let replacementID = UUID(uuidString: "B2222222-2222-4222-8222-222222222222")!
    return PublicIDRepairUnresolvedReference(
        entityType: .movement,
        recordDescription: "Shared movement",
        stableRecordIdentifier: "bridge|SharedMovement|choice",
        fieldName: "animalPublicID",
        referencedPublicID: retainedID,
        reason: "Choose which repaired animal owns this bridge-only movement.",
        candidates: [
            PublicIDRepairResolutionCandidate(
                stableRecordIdentifier: "bridge-candidate|retained",
                recordDescription: "Cow",
                detail: "Tag 101",
                resultingPublicID: retainedID
            ),
            PublicIDRepairResolutionCandidate(
                stableRecordIdentifier: "bridge-candidate|replacement",
                recordDescription: "Cow",
                detail: "Tag 202",
                resultingPublicID: replacementID
            ),
        ]
    )
}

private func makeAuthoritativeBridgeOwnerIssue() -> PublicIDRepairUnresolvedReference {
    let retainedID = UUID(uuidString: "D1111111-1111-4111-8111-111111111111")!
    let ownerHerdID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    return PublicIDRepairUnresolvedReference(
        kind: .bridgeRecordOwner,
        entityType: .animal,
        recordDescription: "Shared animal collision",
        stableRecordIdentifier: "bridge-collision|animals|\(retainedID.uuidString.lowercased())",
        fieldName: "sharedBridgeOwner",
        referencedPublicID: retainedID,
        reason: "The repaired local graph uniquely identifies the owner.",
        candidates: [
            PublicIDRepairResolutionCandidate(
                stableRecordIdentifier: "bridge-owner|animals|owner",
                recordDescription: "Owner Herd — Cow 101",
                detail: "Keep the established local owner.",
                resultingPublicID: ownerHerdID
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