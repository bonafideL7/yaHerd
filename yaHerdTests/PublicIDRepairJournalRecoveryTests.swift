import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairJournalRecoveryTests: XCTestCase {
    func testIndeterminatePartialCommitCompletesFromExistingManifestWithoutChangingAuthoritativeIDs() async throws {
        let fixture = try await makeIndeterminateRecoveryFixture()
        defer { removeBackups(fixture.report) }

        let replacement = try XCTUnwrap(
            fixture.report.replacements.first { $0.entityType == .pasture }
        )
        let mutationContext = ModelContext(fixture.container)
        let pastures = try mutationContext.fetch(FetchDescriptor<Pasture>())
        let reverted = try XCTUnwrap(
            pastures.first { $0.publicID == replacement.replacementPublicID }
        )
        reverted.publicID = replacement.retainedPublicID
        try mutationContext.save()

        let indeterminateCommitState = try await fixture.worker.commitState(for: fixture.report)
        XCTAssertEqual(indeterminateCommitState, .indeterminate)
        let assessment = try await fixture.worker.assessIndeterminateRecovery(
            for: fixture.report
        )
        XCTAssertTrue(assessment.canContinueManifestRepair)
        XCTAssertEqual(assessment.capability, .manifestForwardRecoveryAvailable)
        XCTAssertGreaterThanOrEqual(assessment.alreadyAppliedCount, 1)
        XCTAssertGreaterThanOrEqual(assessment.missingCount, 1)
        XCTAssertEqual(assessment.contradictoryOrAmbiguousCount, 0)

        var journaledRecoveryReport: PublicIDRepairReport?
        let recovered = try await fixture.worker.recoverIndeterminateRepair(
            report: fixture.report,
            action: .continueManifestRepair,
            willCommit: { planned in
                journaledRecoveryReport = planned
            }
        )
        defer { removeBackups(recovered) }

        let journaled = try XCTUnwrap(journaledRecoveryReport)
        XCTAssertNotEqual(journaled.backupPath, fixture.report.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journaled.backupPath))
        XCTAssertEqual(
            recovered.manifest.generations.count,
            fixture.report.manifest.generations.count + 1
        )
        XCTAssertEqual(
            authoritativeManifestIDs(recovered),
            authoritativeManifestIDs(fixture.report),
            "Recovery must replay the already-authoritative manifest rather than generate replacement IDs"
        )
        let recoveredCommitState = try await fixture.worker.commitState(for: recovered)
        XCTAssertEqual(recoveredCommitState, .committed)

        let verificationContext = ModelContext(fixture.container)
        let repairedPastures = try verificationContext.fetch(FetchDescriptor<Pasture>())
        XCTAssertEqual(Set(repairedPastures.map(\.publicID)).count, 3)
        for mapping in fixture.report.replacements where mapping.entityType == .pasture {
            XCTAssertTrue(repairedPastures.contains {
                $0.publicID == mapping.replacementPublicID
            })
        }
    }

    func testIndeterminateContradictoryRepairUsesVerifiedBackupThenReplaysSameManifest() async throws {
        let fixture = try await makeIndeterminateRecoveryFixture()
        defer { removeBackups(fixture.report) }

        let replacement = try XCTUnwrap(
            fixture.report.replacements.first { $0.entityType == .pasture }
        )
        let damagedID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let mutationContext = ModelContext(fixture.container)
        let pastures = try mutationContext.fetch(FetchDescriptor<Pasture>())
        let damaged = try XCTUnwrap(
            pastures.first { $0.publicID == replacement.replacementPublicID }
        )
        damaged.publicID = damagedID
        try mutationContext.save()

        let indeterminateCommitState = try await fixture.worker.commitState(for: fixture.report)
        XCTAssertEqual(indeterminateCommitState, .indeterminate)
        let assessment = try await fixture.worker.assessIndeterminateRecovery(
            for: fixture.report
        )
        XCTAssertTrue(assessment.requiresBackupRestore)
        XCTAssertEqual(assessment.capability, .verifiedBackupRestoreAvailable)
        XCTAssertFalse(assessment.requiresManualResolution)
        XCTAssertGreaterThanOrEqual(assessment.contradictoryOrAmbiguousCount, 1)

        var journaledGenerations: [PublicIDRepairReport] = []
        let recovered = try await fixture.worker.recoverIndeterminateRepair(
            report: fixture.report,
            action: .restorePreRepairBackup,
            willCommit: { planned in
                journaledGenerations.append(planned)
            }
        )
        defer { removeBackups(recovered) }

        XCTAssertEqual(
            journaledGenerations.count,
            2,
            "Backup restoration and the restarted forward repair must each be journaled before their corresponding local save"
        )
        XCTAssertNotEqual(journaledGenerations[0].backupPath, fixture.report.backupPath)
        XCTAssertNotEqual(journaledGenerations[1].backupPath, journaledGenerations[0].backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journaledGenerations[0].backupPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journaledGenerations[1].backupPath))
        XCTAssertEqual(
            recovered.manifest.generations.count,
            fixture.report.manifest.generations.count + 2
        )
        XCTAssertEqual(
            authoritativeManifestIDs(recovered),
            authoritativeManifestIDs(fixture.report)
        )
        let recoveredCommitState = try await fixture.worker.commitState(for: recovered)
        XCTAssertEqual(recoveredCommitState, .committed)

        let verificationContext = ModelContext(fixture.container)
        let repairedPastures = try verificationContext.fetch(FetchDescriptor<Pasture>())
        XCTAssertFalse(repairedPastures.contains { $0.publicID == damagedID })
        XCTAssertEqual(Set(repairedPastures.map(\.publicID)).count, 3)
    }

    func testNonRestorableIndeterminateRepairRequiresExplicitManifestBindingThenReplaysSameIDs() async throws {
        let fixture = try await makeIndeterminateRecoveryFixture()
        defer { removeBackups(fixture.report) }

        let replacement = try XCTUnwrap(
            fixture.report.replacements.first { $0.entityType == .pasture }
        )
        let damagedID = UUID(uuidString: "97979797-9797-4797-8797-979797979797")!
        let mutationContext = ModelContext(fixture.container)
        let pastures = try mutationContext.fetch(FetchDescriptor<Pasture>())
        let damaged = try XCTUnwrap(
            pastures.first { $0.publicID == replacement.replacementPublicID }
        )
        damaged.publicID = damagedID
        damaged.name += " synchronized rename"
        try mutationContext.save()

        let damagedCommitState = try await fixture.worker.commitState(for: fixture.report)
        XCTAssertEqual(damagedCommitState, .indeterminate)
        let assessment = try await fixture.worker.assessIndeterminateRecovery(
            for: fixture.report
        )
        XCTAssertEqual(assessment.capability, .manualRecoveryResolutionRequired)
        XCTAssertTrue(assessment.requiresManualResolution)
        XCTAssertFalse(
            assessment.requiresBackupRestore,
            "Diagnostics must not advertise a backup restore the planner already knows cannot identify the record"
        )
        XCTAssertTrue(assessment.evidence.contains {
            $0.kind == .recordNoLongerUniquelyMatchesBackup
        })

        let issue = try XCTUnwrap(assessment.manualResolutionIssues.first)
        let candidate = try XCTUnwrap(issue.candidates.first)
        XCTAssertEqual(issue.candidates.count, 1)
        XCTAssertEqual(candidate.resultingPublicID, damagedID)

        var journaledGenerations: [PublicIDRepairReport] = []
        let recovered = try await fixture.worker.resolveIndeterminateRecovery(
            report: fixture.report,
            resolutions: [
                PublicIDRepairReferenceResolution(
                    unresolvedReferenceID: issue.id,
                    selectedCandidateStableRecordIdentifier: candidate.stableRecordIdentifier
                )
            ],
            willCommit: { planned in
                journaledGenerations.append(planned)
            }
        )
        defer { removeBackups(recovered) }

        XCTAssertGreaterThanOrEqual(journaledGenerations.count, 2)
        let decisionGeneration = try XCTUnwrap(journaledGenerations.first?.manifest.generations.last)
        XCTAssertNil(decisionGeneration.backup)
        XCTAssertTrue(decisionGeneration.selectedResolutionIDs.contains {
            $0.hasPrefix("local-recovery-binding-v1|")
        })
        let forwardGeneration = try XCTUnwrap(journaledGenerations.last)
        XCTAssertNotEqual(forwardGeneration.backupPath, fixture.report.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: forwardGeneration.backupPath))
        XCTAssertEqual(
            authoritativeManifestIDs(recovered),
            authoritativeManifestIDs(fixture.report),
            "A manual identity binding must never regenerate or replace manifest public IDs"
        )
        let recoveredCommitState = try await fixture.worker.commitState(for: recovered)
        XCTAssertEqual(recoveredCommitState, .committed)

        let verificationContext = ModelContext(fixture.container)
        let repairedPastures = try verificationContext.fetch(FetchDescriptor<Pasture>())
        let rebound = try XCTUnwrap(
            repairedPastures.first { $0.publicID == replacement.replacementPublicID }
        )
        XCTAssertTrue(rebound.name.hasSuffix("synchronized rename"))
        XCTAssertFalse(repairedPastures.contains { $0.publicID == damagedID })
    }

    func testDurableBackupFailureDoesNotJournalOrCommitRepairMutation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairDurableBackupFailureTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }

        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let duplicateID = UUID(uuidString: "96969696-9696-4696-8696-969696969696")!
        let herd = Herd(name: "Durability herd")
        let north = Pasture(publicID: duplicateID, name: "North", sortOrder: 1)
        let south = Pasture(publicID: duplicateID, name: "South", sortOrder: 2)
        north.herd = herd
        south.herd = herd
        context.insert(herd)
        context.insert(north)
        context.insert(south)
        try context.save()

        let worker = SwiftDataPublicIDRepairService(modelContainer: container)
        await worker.setBackupDirectoryOverrideForTesting(directory)

        var willCommitCallCount = 0
        do {
            _ = try await worker.repair(
                resolutions: [],
                willCommit: { _ in willCommitCallCount += 1 }
            )
            XCTFail("Expected durable backup persistence to fail before journaling")
        } catch {
            // The locally verifiable invariant is ordering, not simulated hardware durability.
        }
        await worker.setBackupDirectoryOverrideForTesting(nil)

        XCTAssertEqual(willCommitCallCount, 0)
        let verificationContext = ModelContext(container)
        let persistedPastures = try verificationContext.fetch(FetchDescriptor<Pasture>())
        XCTAssertEqual(persistedPastures.count, 2)
        XCTAssertEqual(Set(persistedPastures.map(\.publicID)), Set([duplicateID]))
    }

    func testVerifiedRecoveryTransactionRestoresWhenBothActiveCopiesAreMalformedOrMissing() throws {
        for mode in [ActiveJournalFailureMode.malformed, .missing] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PublicIDRepairJournalRecoveryTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let journalURL = directory.appendingPathComponent("PendingState.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let defaults = isolatedDefaults()
            let report = makeReport()
            let firstGate = makePendingGate(
                defaults: defaults,
                journalURL: journalURL,
                report: report
            )
            try firstGate.markLocalCommitSucceeded()
            XCTAssertTrue(firstGate.requiresBridgeConvergence)

            let activeRecoveryURL = journalURL.appendingPathExtension("recovery")
            let verifiedRecoveryURL = journalURL.appendingPathExtension("verified-recovery")
            XCTAssertTrue(FileManager.default.fileExists(atPath: verifiedRecoveryURL.path))

            switch mode {
            case .malformed:
                try Data("{}".utf8).write(to: journalURL)
                try Data("not-json".utf8).write(to: activeRecoveryURL)
            case .missing:
                try FileManager.default.removeItem(at: journalURL)
                try FileManager.default.removeItem(at: activeRecoveryURL)
            }

            let recoveredGate = HerdDataMutationGate(
                defaults: isolatedDefaults(),
                journalFileURL: journalURL
            )

            XCTAssertTrue(recoveredGate.requiresBridgeConvergence)
            XCTAssertEqual(recoveredGate.pendingBridgeConvergenceReport, report)
            XCTAssertThrowsError(try recoveredGate.beginSynchronization()) { error in
                guard case .repairJournalUnavailable = error as? HerdDataMutationGate.GateError else {
                    return XCTFail("Expected journal recovery gate for \(mode), got \(error)")
                }
            }

            let repairToken = try recoveredGate.beginPublicIDRepair()
            recoveredGate.endPublicIDRepair(repairToken)
            XCTAssertEqual(recoveredGate.pendingBridgeConvergenceReport, report)
            XCTAssertThrowsError(try recoveredGate.beginSynchronization()) { error in
                guard case .bridgeConvergenceRequired = error as? HerdDataMutationGate.GateError else {
                    return XCTFail("Expected recovered bridge convergence requirement, got \(error)")
                }
            }

            try recoveredGate.completeBridgeConvergence()
            XCTAssertFalse(recoveredGate.requiresBridgeConvergence)
            let completedGate = HerdDataMutationGate(
                defaults: isolatedDefaults(),
                journalFileURL: journalURL
            )
            XCTAssertFalse(completedGate.requiresBridgeConvergence)
        }
    }

    func testRecoveryCopyKeepsPreCommitStateDurableWhenPrimaryWriteFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairJournalPrimaryWriteFailureTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let journalURL = directory.appendingPathComponent("PendingState.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let report = makeReport()
        let gate = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )

        try FileManager.default.createDirectory(
            at: journalURL,
            withIntermediateDirectories: true
        )

        XCTAssertNoThrow(
            try gate.requireLocalCommitCompletion(
                preparation: PublicIDRepairBridgePreparation(
                    identity: .iCloud,
                    herdPublicIDs: [UUID(uuidString: "83838383-8383-4383-8383-838383838383")!]
                ),
                report: report,
                resolutions: []
            )
        )
        XCTAssertTrue(gate.requiresBridgeConvergence)
        XCTAssertEqual(gate.pendingBridgeConvergenceReport, report)

        let recoveryURL = journalURL.appendingPathExtension("recovery")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        var primaryIsDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: journalURL.path,
                isDirectory: &primaryIsDirectory
            )
        )
        XCTAssertTrue(primaryIsDirectory.boolValue)

        let relaunchedGate = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )

        XCTAssertTrue(relaunchedGate.requiresBridgeConvergence)
        XCTAssertEqual(relaunchedGate.pendingBridgeConvergenceReport, report)
        var relaunchedPrimaryIsDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: journalURL.path,
                isDirectory: &relaunchedPrimaryIsDirectory
            )
        )
        XCTAssertTrue(relaunchedPrimaryIsDirectory.boolValue)
        XCTAssertThrowsError(try relaunchedGate.beginSynchronization()) { error in
            guard case .bridgeConvergenceRequired = error as? HerdDataMutationGate.GateError else {
                return XCTFail("Expected recovered bridge convergence requirement, got \(error)")
            }
        }

        XCTAssertNoThrow(try relaunchedGate.markLocalCommitSucceeded())
        var primaryStillObstructed: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: journalURL.path,
                isDirectory: &primaryStillObstructed
            )
        )
        XCTAssertTrue(primaryStillObstructed.boolValue)

        XCTAssertNoThrow(try relaunchedGate.completeBridgeConvergence())
        XCTAssertFalse(relaunchedGate.requiresBridgeConvergence)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))

        let completedGate = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )
        XCTAssertFalse(completedGate.requiresBridgeConvergence)
        let synchronizationToken = try completedGate.beginSynchronization()
        completedGate.endSynchronization(synchronizationToken)
    }

    func testSchemaInvalidButSyntacticallyValidPrimaryDoesNotOverwriteRecoveryState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairJournalSchemaRecoveryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let journalURL = directory.appendingPathComponent("PendingState.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaults = isolatedDefaults()
        let report = makeReport()
        _ = makePendingGate(
            defaults: defaults,
            journalURL: journalURL,
            report: report
        )
        try Data("{}".utf8).write(to: journalURL)

        let recoveredGate = HerdDataMutationGate(
            defaults: defaults,
            journalFileURL: journalURL
        )

        XCTAssertEqual(recoveredGate.pendingBridgeConvergenceReport, report)
        XCTAssertTrue(recoveredGate.requiresBridgeConvergence)
        XCTAssertNotEqual(try Data(contentsOf: journalURL), Data("{}".utf8))
    }

    func testSchemaInvalidRecoveryDoesNotOverwriteValidPrimaryState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairJournalInvalidRecoveryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let journalURL = directory.appendingPathComponent("PendingState.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaults = isolatedDefaults()
        let report = makeReport()
        _ = makePendingGate(
            defaults: defaults,
            journalURL: journalURL,
            report: report
        )

        let validPrimaryData = try Data(contentsOf: journalURL)
        let recoveryURL = journalURL.appendingPathExtension("recovery")
        try Data("{}".utf8).write(to: recoveryURL)

        let recoveredGate = HerdDataMutationGate(
            defaults: defaults,
            journalFileURL: journalURL
        )

        XCTAssertTrue(recoveredGate.requiresBridgeConvergence)
        XCTAssertEqual(recoveredGate.pendingBridgeConvergenceReport, report)
        XCTAssertEqual(try Data(contentsOf: journalURL), validPrimaryData)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), validPrimaryData)

        let secondRelaunch = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )
        XCTAssertEqual(secondRelaunch.pendingBridgeConvergenceReport, report)
    }

    func testRemovingCompletedJournalRemovesPrimaryAndRecoveryCopies() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairJournalRemovalTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let journalURL = directory.appendingPathComponent("PendingState.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let gate = makePendingGate(
            defaults: isolatedDefaults(),
            journalURL: journalURL,
            report: makeReport()
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: journalURL.appendingPathExtension("recovery").path
            )
        )

        try gate.markLocalCommitSucceeded()
        try gate.completeBridgeConvergence()

        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: journalURL.appendingPathExtension("recovery").path
            )
        )
    }

    private func makeIndeterminateRecoveryFixture() async throws -> IndeterminateRecoveryFixture {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let duplicateID = UUID(uuidString: "91919191-9191-4191-8191-919191919191")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herd = Herd(
            name: "Recovery herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let north = Pasture(publicID: duplicateID, name: "North", sortOrder: 1)
        let south = Pasture(publicID: duplicateID, name: "South", sortOrder: 2)
        let west = Pasture(publicID: duplicateID, name: "West", sortOrder: 3)
        north.herd = herd
        south.herd = herd
        west.herd = herd
        context.insert(herd)
        context.insert(north)
        context.insert(south)
        context.insert(west)
        try context.save()

        let worker = SwiftDataPublicIDRepairService(modelContainer: container)
        let report = try await worker.repair(
            resolutions: [],
            willCommit: { _ in }
        )
        XCTAssertEqual(
            report.replacements.filter { $0.entityType == .pasture }.count,
            2
        )
        return IndeterminateRecoveryFixture(
            container: container,
            worker: worker,
            report: report
        )
    }

    private func authoritativeManifestIDs(
        _ report: PublicIDRepairReport
    ) -> Set<String> {
        Set(report.manifest.recordMappings.map {
            "\($0.id)|\($0.finalPublicID.uuidString.lowercased())"
        })
    }

    private func removeBackups(_ report: PublicIDRepairReport) {
        for backup in report.backupReferences {
            try? FileManager.default.removeItem(atPath: backup.path)
        }
    }

    private func makePendingGate(
        defaults: UserDefaults,
        journalURL: URL,
        report: PublicIDRepairReport
    ) -> HerdDataMutationGate {
        let gate = HerdDataMutationGate(
            defaults: defaults,
            journalFileURL: journalURL
        )
        do {
            try gate.requireLocalCommitCompletion(
                preparation: PublicIDRepairBridgePreparation(
                    identity: .iCloud,
                    herdPublicIDs: [UUID(uuidString: "82828282-8282-4282-8282-828282828282")!]
                ),
                report: report,
                resolutions: []
            )
        } catch {
            XCTFail("Expected pending repair journal to persist: \(error)")
        }
        return gate
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PublicIDRepairJournalRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeReport() -> PublicIDRepairReport {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        return PublicIDRepairReport(
            completedAt: timestamp,
            assessment: PublicIDRepairAssessment(scannedAt: timestamp, entities: []),
            replacements: [],
            referenceUpdates: [],
            backupFilename: "journal-recovery.json",
            backupPath: "/tmp/journal-recovery.json",
            validationIssueCount: 0
        )
    }
}

private struct IndeterminateRecoveryFixture {
    let container: ModelContainer
    let worker: SwiftDataPublicIDRepairService
    let report: PublicIDRepairReport
}

private enum ActiveJournalFailureMode: String {
    case malformed
    case missing
}
