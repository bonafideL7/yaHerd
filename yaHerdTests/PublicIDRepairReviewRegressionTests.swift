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

    func testDurableJournalIsReadFromDiskByFreshGateBeforeSwiftDataSave() throws {
        let journalURL = temporaryJournalURL()
        defer {
            try? FileManager.default.removeItem(
                at: journalURL.deletingLastPathComponent()
            )
        }
        let preparation = PublicIDRepairBridgePreparation(
            identity: .iCloud,
            herdPublicIDs: [UUID(uuidString: "91919191-9191-4191-8191-919191919191")!]
        )
        let report = makeReport()

        do {
            let firstDefaults = isolatedDefaults()
            let firstGate = HerdDataMutationGate(
                defaults: firstDefaults,
                journalFileURL: journalURL
            )
            try firstGate.requireLocalCommitCompletion(
                preparation: preparation,
                report: report,
                resolutions: []
            )

            let persistedBytes = try Data(contentsOf: journalURL)
            XCTAssertFalse(persistedBytes.isEmpty)
            XCTAssertNil(
                firstDefaults.data(forKey: "PublicIDRepair.PendingState.v2"),
                "The crash boundary must not depend on UserDefaults persistence"
            )
        }

        let relaunchedDefaults = isolatedDefaults()
        let relaunchedGate = HerdDataMutationGate(
            defaults: relaunchedDefaults,
            journalFileURL: journalURL
        )

        XCTAssertTrue(relaunchedGate.requiresBridgeConvergence)
        XCTAssertThrowsError(try relaunchedGate.beginSynchronization())
        XCTAssertThrowsError(
            try relaunchedGate.validateLocalMutationAllowed(reason: .animal)
        )
    }

    func testCorruptDurableJournalFailsClosed() throws {
        let journalURL = temporaryJournalURL()
        defer {
            try? FileManager.default.removeItem(
                at: journalURL.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: journalURL)

        let gate = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )

        XCTAssertTrue(gate.requiresBridgeConvergence)
        XCTAssertThrowsError(try gate.beginSynchronization()) { error in
            guard case .repairJournalUnavailable = error as? HerdDataMutationGate.GateError else {
                return XCTFail("Expected repairJournalUnavailable, got \(error)")
            }
        }
        XCTAssertThrowsError(try gate.beginPublicIDRepair()) { error in
            guard case .repairJournalUnavailable = error as? HerdDataMutationGate.GateError else {
                return XCTFail("Expected repairJournalUnavailable, got \(error)")
            }
        }
        XCTAssertThrowsError(try gate.beginSyncDataReset()) { error in
            guard case .repairJournalUnavailable = error as? HerdDataMutationGate.GateError else {
                return XCTFail("Expected repairJournalUnavailable, got \(error)")
            }
        }
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
        XCTAssertEqual(preparation.targets.count, 1)
        XCTAssertEqual(preparation.targets.first?.herdPublicID, herd.publicID)
        XCTAssertEqual(preparation.targets.first?.location, .ownerPrivateStore)
        XCTAssertEqual(preparation.targets.first?.bridgeFingerprint, "review-baseline")

        repository.access = .localOwnerBridgePending

        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: makeReport()
            )
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

    func testRelaunchImportsInterveningBridgeChangeButBlocksAChangeAfterImportBaseline() async throws {
        let defaults = isolatedDefaults()
        let herd = makeHerdSummary()
        let inventory = ReviewHerdInventory(herds: [herd])
        let repository = ReviewHerdSharingRepository(
            access: .ownerPrivateStore(participantCount: 1)
        )
        let exporter = ReviewBridgeExporter(
            currentFingerprint: "bridge-before-crash",
            fingerprintAfterImport: "bridge-after-second-edit"
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let preparation = try await coordinator.prepareForRepair()
        let report = makeAffectedReport(for: herd)
        let firstGate = HerdDataMutationGate(defaults: defaults)

        try firstGate.requireLocalCommitCompletion(
            preparation: preparation,
            report: report,
            resolutions: []
        )
        exporter.currentFingerprint = "bridge-after-collaborator-edit"

        let relaunchedGate = HerdDataMutationGate(defaults: defaults)
        let service = CoordinatedPublicIDRepairService(
            worker: ReviewCommittedRepairWorker(),
            mutationGate: relaunchedGate,
            bridgeCoordinator: coordinator
        )

        do {
            _ = try await service.repair()
            XCTFail("Expected a bridge change after import baseline capture to block export")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(error, .bridgeContentChanged(herdPublicID: herd.publicID))
        }

        XCTAssertTrue(relaunchedGate.requiresBridgeConvergence)
        XCTAssertEqual(exporter.importedHerdIDs, [herd.publicID])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
        XCTAssertThrowsError(try relaunchedGate.beginSynchronization())
    }

    func testPendingPreparationPreservesPreparedHerdWhenNewHerdAppears() async throws {
        let original = makeHerdSummary()
        let replacement = HerdSummary(
            publicID: UUID(uuidString: "82828282-8282-4282-8282-828282828282")!,
            name: "New mirrored herd",
            createdAt: original.createdAt.addingTimeInterval(60),
            updatedAt: original.updatedAt.addingTimeInterval(60),
            schemaVersion: original.schemaVersion
        )
        let inventory = ReviewHerdInventory(herds: [original])
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
        let originalTarget = try XCTUnwrap(preparation.targets.first)
        await inventory.setHerds([replacement])

        let rebased = try await coordinator.rebasePendingRepair(
            preparation: preparation
        )

        XCTAssertEqual(rebased.targets.count, 2)
        XCTAssertTrue(rebased.targets.contains(originalTarget))
        let replacementTarget = try XCTUnwrap(
            rebased.targets.first { $0.herdPublicID == replacement.publicID }
        )
        XCTAssertEqual(replacementTarget.location, .ownerPrivateStore)
        XCTAssertEqual(replacementTarget.bridgeFingerprint, "review-baseline")

        do {
            try await coordinator.convergeAfterRepair(
                preparation: rebased,
                report: makeReport()
            )
            XCTFail("Expected the preserved prepared Herd target to require explicit recovery intent")
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            XCTAssertEqual(error.issues.count, 1)
            let issue = try XCTUnwrap(error.issues.first)
            XCTAssertEqual(issue.kind, .preparedHerdRecovery)
            XCTAssertEqual(issue.entityType, .herd)
            XCTAssertEqual(issue.fieldName, "preparedBridgeTarget")
            XCTAssertEqual(issue.referencedPublicID, original.publicID)
            XCTAssertEqual(issue.candidates.count, 2)
            XCTAssertTrue(issue.candidates.contains {
                $0.stableRecordIdentifier.hasPrefix("restore-prepared-herd|")
                    && $0.resultingPublicID == original.publicID
            })
            XCTAssertTrue(issue.candidates.contains {
                $0.stableRecordIdentifier.hasPrefix("retire-prepared-herd|")
                    && $0.resultingPublicID == original.publicID
            })
        }
        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    func testDuplicateHerdOnReadWriteParticipantCanPrepareWithoutNormalBridgeImport() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicatedPublicID = UUID(uuidString: "A1A1A1A1-A1A1-41A1-81A1-A1A1A1A1A1A1")!
        let first = HerdSummary(
            publicID: duplicatedPublicID,
            name: "Participant herd",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let second = HerdSummary(
            publicID: duplicatedPublicID,
            name: "Participant herd duplicate",
            createdAt: timestamp.addingTimeInterval(1),
            updatedAt: timestamp.addingTimeInterval(1),
            schemaVersion: 1
        )
        let inventory = ReviewHerdInventory(herds: [first, second])
        let repository = ReviewHerdSharingRepository(
            access: .acceptedSharedStore(
                permission: .readWrite,
                participantCount: 2
            )
        )
        let exporter = ReviewBridgeExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()

        XCTAssertEqual(preparation.targets.count, 1)
        XCTAssertEqual(preparation.targets.first?.herdPublicID, duplicatedPublicID)
        XCTAssertEqual(preparation.targets.first?.location, .acceptedSharedStore)
        XCTAssertGreaterThan(repository.fetchAccessCallCount, 0)
        XCTAssertEqual(repository.importedHerdIDs, [])
        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PublicIDRepairReviewRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryJournalURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PublicIDRepairReviewRegressionTests-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("PendingState.json")
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

    private func makeAffectedReport(for herd: HerdSummary) -> PublicIDRepairReport {
        PublicIDRepairReport(
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            assessment: PublicIDRepairAssessment(
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
                entities: []
            ),
            replacements: [
                PublicIDRepairReplacement(
                    entityType: .animal,
                    recordDescription: "Review bridge animal",
                    stableRecordIdentifier: "review-affected-animal",
                    retainedPublicID: reviewBridgeSourceID,
                    replacementPublicID: reviewBridgeFinalID,
                    owningHerdPublicID: herd.publicID
                )
            ],
            referenceUpdates: [],
            backupFilename: "review-affected.json",
            backupPath: "/tmp/review-affected.json",
            validationIssueCount: 0
        )
    }
}

private let reviewBridgeSourceID = UUID(uuidString: "83838383-8383-4383-8383-838383838383")!
private let reviewBridgeFinalID = UUID(uuidString: "84848484-8484-4484-8484-848484848484")!

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

private actor ReviewCommittedRepairWorker: PublicIDRepairTransactionalService {
    func scan() async throws -> PublicIDRepairAssessment {
        PublicIDRepairAssessment(scannedAt: .now, entities: [])
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        XCTFail("A committed journaled repair must not be repeated")
        throw ReviewRepairError.unexpectedRepair
    }

    func commitState(for report: PublicIDRepairReport) async throws -> PublicIDRepairCommitState {
        .committed
    }
}

private enum ReviewRepairError: Error {
    case unexpectedRepair
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
    var currentFingerprint: String
    var fingerprintAfterImport: String?
    private(set) var importedHerdIDs: [UUID] = []
    private(set) var exportedHerdIDs: [UUID] = []

    init(
        currentFingerprint: String = "review-baseline",
        fingerprintAfterImport: String? = nil
    ) {
        self.currentFingerprint = currentFingerprint
        self.fingerprintAfterImport = fingerprintAfterImport
    }

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        currentFingerprint
    }

    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight {
        PublicIDRepairBridgePreflight(
            fingerprint: currentFingerprint,
            recordIdentities: [
                PublicIDRepairBridgeRecordIdentity(
                    step: .animals,
                    publicID: reviewBridgeSourceID
                )
            ]
        )
    }

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        guard expectedFingerprint == currentFingerprint else {
            throw PublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }
        importedHerdIDs.append(herd.publicID)
        if let fingerprintAfterImport {
            currentFingerprint = fingerprintAfterImport
        }
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

@MainActor
private final class ReviewHerdSharingRepository: HerdSharingRepository {
    var access: HerdSharingAccess
    private(set) var fetchAccessCallCount = 0
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
        fetchAccessCallCount += 1
        return access
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
