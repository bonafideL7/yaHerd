import CoreData
import XCTest
@testable import yaHerd

final class CoreDataAppHerdBootstrapperTests: XCTestCase {
    func testBootstrapCreatesOneLocalHerdAndReusesItsApplicationID() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        let createdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly,
            now: timestamp
        )
        let resolvedID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly,
            now: timestamp.addingTimeInterval(60)
        )

        XCTAssertEqual(resolvedID, createdID)

        let context = assembly.contextFactory.makeReadContext()
        let herds = try context.performAndWait {
            try context.fetch(
                NSFetchRequest<CDHerd>(
                    entityName: CDHerd.coreDataEntityName
                )
            )
        }

        XCTAssertEqual(herds.count, 1)
        XCTAssertEqual(herds.first?.id, createdID)
        XCTAssertEqual(herds.first?.name, CoreDataAppHerdBootstrapper.defaultHerdName)
        XCTAssertEqual(herds.first?.createdAt, timestamp)
        XCTAssertEqual(herds.first?.updatedAt, timestamp)
    }

    func testBootstrapRejectsAmbiguousMultipleHerdRootsAndReportsActualCount() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()

        try await assembly.transactionExecutor.performWrite { context in
            for index in 0..<3 {
                let herd = CDHerd(context: context)
                herd.id = UUID()
                herd.name = "Herd \(index)"
                herd.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
                herd.updatedAt = herd.createdAt
            }
        }

        do {
            _ = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
                assembly: assembly
            )
            XCTFail("Expected multiple-herd bootstrap failure")
        } catch let error as CoreDataAppHerdBootstrapError {
            XCTAssertEqual(error, .multipleLocalHerds(count: 3))
        }
    }

    @MainActor
    func testCoreDataAppGraphSharesHerdStoreMutationsAndReadProjections() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        let graph = CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID
        ).makeDependencies(dataAccessMode: .readWrite)

        XCTAssertEqual(try graph.herdRepository.fetchCurrentHerd().id, herdID)
        XCTAssertNotNil(graph.workingSessionFeatureDependencies.animalReferenceQueryReader)
        XCTAssertNotNil(graph.fieldCheckFeatureDependencies.animalReferenceQueryReader)
        XCTAssertNotNil(graph.animalFeatureDependencies.parentOptionQueryReader)
        XCTAssertNotNil(graph.animalFeatureDependencies.listSnapshotReader)

        let pasture = try graph.pastureFeatureDependencies.createRepository.create(
            input: PastureInput(
                name: "App Graph Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 2
            )
        )
        XCTAssertEqual(
            try graph.pastureFeatureDependencies.listRepository.fetchPastures().map(\.id),
            [pasture.id]
        )
        let dashboardAfterCreate = try await graph.homeFeatureDependencies
            .dashboardQueryReader.fetchDashboardPastureRecords()
        XCTAssertTrue(dashboardAfterCreate.contains { $0.id == pasture.id })
        XCTAssertEqual(graph.applicationMutationCenter.currentSequence, 1)

        try await graph.pastureFeatureDependencies.deletionCommand.deletePastures(
            ids: [pasture.id],
            archivedAt: Date(timeIntervalSinceReferenceDate: 800_000)
        )
        XCTAssertNil(
            try graph.pastureFeatureDependencies.detailRepository.fetchPastureDetail(
                id: pasture.id
            )
        )
        let dashboardAfterDelete = try await graph.homeFeatureDependencies
            .dashboardQueryReader.fetchDashboardPastureRecords()
        XCTAssertFalse(dashboardAfterDelete.contains { $0.id == pasture.id })
        XCTAssertEqual(graph.applicationMutationCenter.currentSequence, 2)
        XCTAssertEqual(graph.applicationMutationCenter.animalRevision, 2)
        XCTAssertEqual(graph.applicationMutationCenter.pastureRevision, 2)
        XCTAssertEqual(graph.applicationMutationCenter.fieldCheckRevision, 2)
    }

    @MainActor
    func testCoreDataAppGraphRecoveryBlocksMutationsWithoutUsingAnotherStore() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        let graph = CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID
        ).makeDependencies(dataAccessMode: .recoveryReadOnly)

        XCTAssertEqual(try graph.herdRepository.fetchCurrentHerd().id, herdID)
        XCTAssertThrowsError(
            try graph.pastureFeatureDependencies.createRepository.create(
                input: PastureInput(
                    name: "Blocked Pasture",
                    acreage: nil,
                    usableAcreage: nil,
                    targetAcresPerHead: nil
                )
            )
        ) { error in
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        do {
            try await graph.pastureFeatureDependencies.deletionCommand.deletePastures(
                ids: [UUID()],
                archivedAt: Date()
            )
            XCTFail("Expected the recovery policy to reject deletion.")
        } catch {
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        XCTAssertTrue(
            try graph.pastureFeatureDependencies.listRepository.fetchPastures().isEmpty
        )
        XCTAssertEqual(graph.applicationMutationCenter.currentSequence, 0)
    }

    @MainActor
    func testAppCutoverReopensDurableCoreDataHerdAndPastures() async throws {
        let harness = try CoreDataPersistenceHarness()
        let first = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL
        )
        let firstDependencies = first.makeDependencies(dataAccessMode: .readWrite)
        let originalHerdID = try firstDependencies.herdRepository.fetchCurrentHerd().id
        let pasture = try firstDependencies.pastureFeatureDependencies.createRepository.create(
            input: PastureInput(
                name: "Durable Cutover Pasture",
                acreage: 30,
                usableAcreage: 28,
                targetAcresPerHead: 2
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.storeURL.path))

        let reopened = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL
        )
        let reloadedDependencies = reopened.makeDependencies(dataAccessMode: .readWrite)
        XCTAssertEqual(
            try reloadedDependencies.herdRepository.fetchCurrentHerd().id,
            originalHerdID
        )
        XCTAssertEqual(
            try reloadedDependencies.pastureFeatureDependencies.listRepository
                .fetchPastures().map(\.id),
            [pasture.id]
        )
        let dashboard = try await reloadedDependencies.homeFeatureDependencies
            .dashboardQueryReader.fetchDashboardPastureRecords()
        XCTAssertTrue(dashboard.contains { $0.id == pasture.id })
        XCTAssertEqual(reloadedDependencies.applicationMutationCenter.currentSequence, 0)
    }

    @MainActor
    func testAppCutoverRecoveryUsesOnlyInMemoryCoreDataWithReadOnlyPolicy() async throws {
        let harness = try CoreDataPersistenceHarness()
        let recovery = try await CoreDataAppPersistenceAssembly.inMemoryRecovery()
        let dependencies = recovery.makeDependencies(dataAccessMode: .recoveryReadOnly)

        XCTAssertNotNil(try dependencies.herdRepository.fetchCurrentHerd().id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.storeURL.path))

        XCTAssertThrowsError(
            try dependencies.pastureFeatureDependencies.createRepository.create(
                input: PastureInput(
                    name: "Blocked Recovery Pasture",
                    acreage: nil,
                    usableAcreage: nil,
                    targetAcresPerHead: nil
                )
            )
        ) { error in
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        do {
            try await dependencies.pastureFeatureDependencies.deletionCommand
                .deletePastures(ids: [UUID()], archivedAt: .now)
            XCTFail("Expected in-memory recovery deletion to be rejected.")
        } catch {
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        XCTAssertTrue(
            try dependencies.pastureFeatureDependencies.listRepository
                .fetchPastures().isEmpty
        )
        XCTAssertEqual(dependencies.applicationMutationCenter.currentSequence, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.storeURL.path))
    }

    @MainActor
    func testFirstCoreDataLaunchIgnoresObsoleteStoreFilenames() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(
            "yaHerd-prelaunch-native-store-\(UUID().uuidString)",
            isDirectory: true
        )
        let directory = root.appendingPathComponent("yaHerd", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let store = directory.appendingPathComponent(CoreDataPersistentContainer.storeFileName)
        let obsoleteFile = root.appendingPathComponent("yaHerdStore.store")
        let obsoleteJournal = root.appendingPathComponent("default.store-journal")
        let marker = Data("obsolete local development file".utf8)
        try marker.write(to: obsoleteFile)
        try marker.write(to: obsoleteJournal)

        let first = try await CoreDataAppPersistenceAssembly.load(at: store)
        let firstHerdID = try first.makeDependencies(
            dataAccessMode: .readWrite
        ).herdRepository.fetchCurrentHerd().id

        XCTAssertTrue(manager.fileExists(atPath: store.path))
        XCTAssertEqual(try Data(contentsOf: obsoleteFile), marker)
        XCTAssertEqual(try Data(contentsOf: obsoleteJournal), marker)

        let reopened = try await CoreDataAppPersistenceAssembly.load(at: store)
        XCTAssertEqual(
            try reopened.makeDependencies(dataAccessMode: .readWrite)
                .herdRepository.fetchCurrentHerd().id,
            firstHerdID
        )
    }

    @MainActor
    func testCoreDataAppGraphRoutesFieldCheckAndWorkingMutationsToActiveConsumers() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        let dependencies = CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID
        ).makeDependencies(dataAccessMode: .readWrite)
        let center = dependencies.applicationMutationCenter

        // Observe the same stream injected into the live Home, Field Check,
        // Working and Animal feature dependency containers.
        XCTAssertEqual(
            dependencies.homeFeatureDependencies.mutationStream.currentSequence,
            center.currentSequence
        )
        XCTAssertEqual(
            dependencies.fieldCheckFeatureDependencies.mutationStream.currentSequence,
            center.currentSequence
        )
        XCTAssertEqual(
            dependencies.workingSessionFeatureDependencies.mutationStream.currentSequence,
            center.currentSequence
        )
        XCTAssertEqual(
            dependencies.animalFeatureDependencies.mutationStream.currentSequence,
            center.currentSequence
        )

        center.recordSuccessfulMutation(reason: .fieldCheck)
        XCTAssertEqual(center.currentSequence, 1)
        XCTAssertEqual(center.homeRevision, 1)
        XCTAssertEqual(center.dashboardRevision, 1)
        XCTAssertEqual(center.fieldCheckRevision, 1)
        XCTAssertEqual(center.pastureRevision, 1)
        XCTAssertEqual(center.animalRevision, 0)
        XCTAssertEqual(center.workingSessionRevision, 0)

        var fieldEventIterator = center.events(after: 0).makeAsyncIterator()
        let fieldEvent = await fieldEventIterator.next()
        XCTAssertEqual(fieldEvent?.source, .local(.fieldCheck))
        XCTAssertEqual(
            fieldEvent?.affectedAreas,
            Set([.home, .dashboard, .pastures, .fieldChecks])
        )

        center.recordSuccessfulMutation(reason: .working)
        XCTAssertEqual(center.currentSequence, 2)
        XCTAssertEqual(center.homeRevision, 2)
        XCTAssertEqual(center.dashboardRevision, 2)
        XCTAssertEqual(center.fieldCheckRevision, 2)
        XCTAssertEqual(center.pastureRevision, 2)
        XCTAssertEqual(center.animalRevision, 1)
        XCTAssertEqual(center.workingSessionRevision, 1)
        XCTAssertEqual(
            dependencies.homeFeatureDependencies.mutationStream.homeRevision,
            2
        )
        XCTAssertEqual(
            dependencies.fieldCheckFeatureDependencies.mutationStream.fieldCheckRevision,
            2
        )
        XCTAssertEqual(
            dependencies.workingSessionFeatureDependencies.mutationStream.workingSessionRevision,
            1
        )
        XCTAssertEqual(
            dependencies.animalFeatureDependencies.mutationStream.animalRevision,
            1
        )

        var workingEventIterator = center.events(after: 1).makeAsyncIterator()
        let workingEvent = await workingEventIterator.next()
        XCTAssertEqual(workingEvent?.source, .local(.working))
        XCTAssertEqual(
            workingEvent?.affectedAreas,
            Set([.home, .dashboard, .animals, .pastures, .fieldChecks, .workingSessions])
        )

        // New subscribers receive the latest revision even if they attach
        // after a mutation, as the active .task observers may do on navigation.
        var homeRevisions = center.revisions(for: .home, after: 0).makeAsyncIterator()
        var animalRevisions = center.revisions(for: .animals, after: 0).makeAsyncIterator()
        var workingRevisions = center.revisions(
            for: .workingSessions,
            after: 0
        ).makeAsyncIterator()
        let homeRevision = await homeRevisions.next()
        let animalRevision = await animalRevisions.next()
        let workingRevision = await workingRevisions.next()
        XCTAssertEqual(homeRevision, 2)
        XCTAssertEqual(animalRevision, 1)
        XCTAssertEqual(workingRevision, 1)
    }

    @MainActor
    func testAppCurrentHerdSelectionExposesOnlyTheSelectedApplicationID() {
        let firstID = UUID()
        let secondID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstID)

        XCTAssertEqual(selection.currentHerdID, firstID)

        selection.select(secondID)
        XCTAssertEqual(selection.currentHerdID, secondID)

        selection.select(nil)
        XCTAssertNil(selection.currentHerdID)
    }

    @MainActor
    func testRecoveryExportDistinguishesAbsentDirectoryFromEnumerationFailure() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("yaHerd-recovery-inventory-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let controller = RecoveryModeController(
            context: RecoveryModeContext(startupError: "Store unavailable"),
            applicationSupportURL: root
        )

        // Absent Core Data directory is an actual empty inventory.
        XCTAssertNil(controller.diagnosticsErrorMessage)
        XCTAssertTrue(controller.diagnostics.recoverableStoreFiles.isEmpty)
        controller.prepareExport()
        XCTAssertNil(controller.exportErrorMessage)
        XCTAssertNotNil(controller.exportDocument)

        controller.clearPreparedExport()

        // A path that exists but cannot be enumerated is not an empty directory.
        let storeDirectory = root.appendingPathComponent("yaHerd", isDirectory: true)
        try Data("not a directory".utf8).write(to: storeDirectory)
        controller.refreshDiagnostics()
        XCTAssertNotNil(controller.diagnosticsErrorMessage)
        XCTAssertTrue(controller.diagnostics.recoverableStoreFiles.isEmpty)
        controller.prepareExport()
        XCTAssertNil(controller.exportDocument)
        XCTAssertNotNil(controller.exportErrorMessage)

        // Once access is restored, diagnostics and export recover without restart.
        try manager.removeItem(at: storeDirectory)
        try manager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeFile = storeDirectory.appendingPathComponent(
            CoreDataPersistentContainer.storeFileName
        )
        try Data("store data".utf8).write(to: storeFile)
        controller.refreshDiagnostics()
        XCTAssertNil(controller.diagnosticsErrorMessage)
        XCTAssertEqual(controller.diagnostics.recoverableStoreFiles.count, 1)
        controller.prepareExport()
        XCTAssertNil(controller.exportErrorMessage)
        XCTAssertNotNil(controller.exportDocument)

        // Native Core Data rollback journals remain part of recovery; old
        // SwiftData-style filenames are ignored by the inventory.
        controller.clearPreparedExport()
        let coreDataJournal = URL(fileURLWithPath: storeFile.path + "-journal")
        let legacyJournal = root.appendingPathComponent("default.store-journal")
        try Data("core rollback".utf8).write(to: coreDataJournal)
        try Data("legacy rollback".utf8).write(to: legacyJournal)
        controller.refreshDiagnostics()
        XCTAssertNil(controller.diagnosticsErrorMessage)
        XCTAssertEqual(
            Set(controller.diagnostics.recoverableStoreFiles.map(\.archiveName)),
            Set([
                storeFile.lastPathComponent,
                coreDataJournal.lastPathComponent,
            ])
        )
        controller.prepareExport()
        XCTAssertNil(controller.exportErrorMessage)
        XCTAssertNotNil(controller.exportDocument)
        XCTAssertTrue(manager.fileExists(atPath: coreDataJournal.path))
        XCTAssertTrue(manager.fileExists(atPath: legacyJournal.path))
    }

    @MainActor
    func testReadOnlyRecoveryProbeDoesNotCreateMissingStoreOrTouchOrphanedJournal() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("yaHerd-recovery-probe-missing-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let storeDirectory = root.appendingPathComponent("yaHerd", isDirectory: true)
        let storeURL = storeDirectory.appendingPathComponent(CoreDataPersistentContainer.storeFileName)
        let controller = RecoveryModeController(
            context: RecoveryModeContext(startupError: "Original store unavailable"),
            fileManager: manager,
            applicationSupportURL: root,
            automaticallyRefreshDiagnostics: false
        )

        await controller.checkPersistentStoreReadOnly()
        guard case .some(.failed(let initialMessage)) = controller.storeCheckResult else {
            XCTFail("An absent main store must fail its recovery probe.")
            return
        }
        XCTAssertTrue(initialMessage.contains("does not exist"))
        XCTAssertFalse(controller.isCheckingPersistentStore)
        XCTAssertFalse(manager.fileExists(atPath: storeDirectory.path))
        XCTAssertFalse(manager.fileExists(atPath: storeURL.path))

        // An orphaned native Core Data rollback journal cannot make the
        // read-only diagnostic probe create a replacement database.
        try manager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let orphanedJournal = URL(fileURLWithPath: storeURL.path + "-journal")
        let originalBytes = Data("orphaned Core Data journal".utf8)
        try originalBytes.write(to: orphanedJournal)

        await controller.checkPersistentStoreReadOnly()
        guard case .some(.failed(let repeatedMessage)) = controller.storeCheckResult else {
            XCTFail("An orphaned Core Data sidecar cannot make the probe succeed.")
            return
        }
        XCTAssertTrue(repeatedMessage.contains("does not exist"))
        XCTAssertFalse(controller.isCheckingPersistentStore)
        XCTAssertTrue(manager.fileExists(atPath: storeDirectory.path))
        XCTAssertFalse(manager.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try Data(contentsOf: orphanedJournal), originalBytes)
    }

    @MainActor
    func testReadOnlyRecoveryProbeRejectsEmptyHerdThenReadsExistingSQLiteOnRetry() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("yaHerd-recovery-probe-existing-\(UUID().uuidString)", isDirectory: true)
        let storeDirectory = root.appendingPathComponent("yaHerd", isDirectory: true)
        try manager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let storeURL = storeDirectory.appendingPathComponent(CoreDataPersistentContainer.storeFileName)
        let writer = try await CoreDataPersistenceAssembly.load(storeURL: storeURL)
        let controller = RecoveryModeController(
            context: RecoveryModeContext(startupError: "Recovery session remains active"),
            fileManager: manager,
            applicationSupportURL: root,
            automaticallyRefreshDiagnostics: false
        )

        // Opening a valid but unbootstrapped database is not sufficient:
        // exactly one persisted Herd must be present.
        await controller.checkPersistentStoreReadOnly()
        guard case .some(.failed) = controller.storeCheckResult else {
            XCTFail("A SQLite store with zero Herd roots must fail the recovery probe.")
            return
        }
        XCTAssertFalse(controller.isCheckingPersistentStore)

        let originalHerdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: writer
        )
        let sqliteBeforeProbe = try Data(contentsOf: storeURL)

        await controller.checkPersistentStoreReadOnly()
        guard case .some(.succeeded(let message)) = controller.storeCheckResult else {
            XCTFail("A valid Core Data store with one Herd must pass its read-only probe.")
            return
        }
        XCTAssertTrue(message.contains("read-only"))
        XCTAssertTrue(message.contains("Restart"))
        XCTAssertFalse(controller.isCheckingPersistentStore)
        XCTAssertEqual(try Data(contentsOf: storeURL), sqliteBeforeProbe)
        XCTAssertEqual(controller.context.startupError, "Recovery session remains active")

        let independentlyReopened = try await CoreDataPersistenceAssembly.load(
            storeURL: storeURL,
            accessMode: .readOnly
        )
        let readContext = independentlyReopened.contextFactory.makeReadContext()
        let persistedHerdIDs = try readContext.performAndWait {
            try readContext.fetch(
                NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            ).compactMap(\.id)
        }
        XCTAssertEqual(persistedHerdIDs, [originalHerdID])
    }

    @MainActor
    func testReadOnlyRecoveryProbeRejectsNonFileAndCorruptSQLiteWithoutReplacingThem() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("yaHerd-recovery-probe-invalid-\(UUID().uuidString)", isDirectory: true)
        let storeDirectory = root.appendingPathComponent("yaHerd", isDirectory: true)
        try manager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let storeURL = storeDirectory.appendingPathComponent(CoreDataPersistentContainer.storeFileName)
        let controller = RecoveryModeController(
            context: RecoveryModeContext(startupError: "Invalid original store"),
            fileManager: manager,
            applicationSupportURL: root,
            automaticallyRefreshDiagnostics: false
        )

        try manager.createDirectory(at: storeURL, withIntermediateDirectories: false)
        await controller.checkPersistentStoreReadOnly()
        guard case .some(.failed(let directoryMessage)) = controller.storeCheckResult else {
            XCTFail("A directory at the SQLite path must fail the recovery probe.")
            return
        }
        XCTAssertTrue(directoryMessage.contains("not a regular file"))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(manager.fileExists(atPath: storeURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        try manager.removeItem(at: storeURL)
        let corruptBytes = Data("original invalid sqlite payload".utf8)
        try corruptBytes.write(to: storeURL)

        await controller.checkPersistentStoreReadOnly()
        guard case .some(.failed) = controller.storeCheckResult else {
            XCTFail("Unreadable SQLite bytes must not pass the recovery probe.")
            return
        }
        XCTAssertFalse(controller.isCheckingPersistentStore)
        XCTAssertEqual(try Data(contentsOf: storeURL), corruptBytes)
    }


    // Release-qualification fixtures deliberately populate every entity in the
    // production Core Data model. Existing permanent repository contracts own
    // the individual field mutation and rollback semantics.
    @MainActor
    func testAnimalListSampleActionsCreateCompleteCoreDataGraphs() async throws {
        let entityNames = [
            "Herd", "TagColorDefinition", "AnimalStatusReference", "PastureGroup",
            "Pasture", "Animal", "AnimalTag", "MovementRecord", "StatusRecord",
            "HealthRecord", "PregnancyCheck", "FieldCheckSession",
            "FieldCheckAnimalCheck", "FieldCheckFinding",
            "WorkingTreatmentTemplate", "WorkingSession", "WorkingQueueItem",
            "WorkingTreatmentRecord"
        ]

        for (isLarge, expectedAnimals) in [(false, 18), (true, 480)] {
            let harness = try CoreDataPersistenceHarness()
            let app = try await CoreDataAppPersistenceAssembly.load(at: harness.storeURL)
            let dependencies = app.makeDependencies(dataAccessMode: .readWrite)
            let originalHerdID = try dependencies.herdRepository.fetchCurrentHerd().id
            guard let seeder = dependencies.animalFeatureDependencies.sampleDataSeeder else {
                XCTFail("Core Data app composition must expose the original sample actions")
                return
            }

            let inserted = try await (isLarge
                ? seeder.seedLargeSampleDataIfNeeded()
                : seeder.seedSampleDataIfNeeded())
            XCTAssertTrue(inserted)
            XCTAssertEqual(dependencies.applicationMutationCenter.currentSequence, 1)
            XCTAssertEqual(dependencies.applicationMutationCenter.animalRevision, 1)
            XCTAssertEqual(dependencies.applicationMutationCenter.workingSessionRevision, 1)

            let records = try dependencies.animalFeatureDependencies.listRepository.fetchAnimals()
            XCTAssertEqual(records.count, expectedAnimals)
            XCTAssertTrue(records.contains { $0.status == .sold })
            XCTAssertTrue(records.contains { $0.status == .dead })
            XCTAssertTrue(records.contains { $0.sex == .male })
            XCTAssertTrue(records.contains { $0.sex == .female })
            XCTAssertTrue(records.contains { $0.animalType == .calf })
            XCTAssertTrue(records.contains { $0.animalType == .cow })
            XCTAssertTrue(records.contains { $0.animalType == .steer })
            XCTAssertTrue(records.contains { $0.animalType == .bull })
            XCTAssertFalse(try dependencies.fieldCheckFeatureDependencies.overviewReader.fetchSessions().isEmpty)
            XCTAssertFalse(try dependencies.workingSessionFeatureDependencies.sessionsRepository.fetchSessions().isEmpty)
            XCTAssertFalse(try dependencies.pastureFeatureDependencies.listRepository.fetchPastures().isEmpty)
            let dashboardPastures = try await dependencies.homeFeatureDependencies
                .dashboardQueryReader.fetchDashboardPastureRecords()
            XCTAssertEqual(dashboardPastures.count, 12)
            let openFindings = try dependencies.fieldCheckFeatureDependencies
                .overviewReader.fetchOpenFindings(limit: 100)
            XCTAssertFalse(openFindings.isEmpty)

            let repeated = try await seeder.seedLargeSampleDataIfNeeded()
            XCTAssertFalse(repeated)
            XCTAssertEqual(dependencies.applicationMutationCenter.currentSequence, 1)
            XCTAssertEqual(
                try dependencies.animalFeatureDependencies.listRepository.fetchAnimals().count,
                expectedAnimals
            )

            let reopened = try await CoreDataAppPersistenceAssembly.load(at: harness.storeURL)
            let reopenedDependencies = reopened.makeDependencies(dataAccessMode: .readWrite)
            XCTAssertEqual(
                try reopenedDependencies.herdRepository.fetchCurrentHerd().id,
                originalHerdID
            )
            XCTAssertEqual(
                try reopenedDependencies.animalFeatureDependencies.listRepository.fetchAnimals().count,
                expectedAnimals
            )

            let independentlyRead = try await harness.makeAssembly(accessMode: .readOnly)
            let context = independentlyRead.contextFactory.makeReadContext()
            let counts = try context.performAndWait { () -> [String: Int] in
                var totals: [String: Int] = [:]
                for name in entityNames {
                    totals[name] = try context.count(
                        for: NSFetchRequest<NSManagedObject>(entityName: name)
                    )
                }
                return totals
            }
            XCTAssertEqual(counts["Animal"], expectedAnimals)
            for name in entityNames {
                XCTAssertGreaterThan(
                    counts[name] ?? 0, 0,
                    "Expected persisted \(name) records in \(isLarge ? "large" : "compact") fixture"
                )
            }

            guard let readOnlySeeder = reopened.makeDependencies(
                dataAccessMode: .recoveryReadOnly
            ).animalFeatureDependencies.sampleDataSeeder else {
                return XCTFail("Read-only app graph should still supply a guarded seed action")
            }
            do {
                _ = try await readOnlySeeder.seedSampleDataIfNeeded()
                XCTFail("Read-only recovery must not permit sample writes")
            } catch {
                XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
            }
            XCTAssertEqual(
                try reopenedDependencies.animalFeatureDependencies.listRepository.fetchAnimals().count,
                expectedAnimals
            )
        }
    }

    @MainActor
    func testSampleActionsDoNotModifyExistingPastureOnlyHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let app = try await CoreDataAppPersistenceAssembly.load(at: harness.storeURL)
        let dependencies = app.makeDependencies(dataAccessMode: .readWrite)
        let pasture = try dependencies.pastureFeatureDependencies.createRepository.create(
            input: PastureInput(
                name: "Original Pasture",
                acreage: 32,
                usableAcreage: 25,
                targetAcresPerHead: 3
            )
        )
        guard let seeder = dependencies.animalFeatureDependencies.sampleDataSeeder else {
            return XCTFail("Expected sample seed action")
        }
        let originalSequence = dependencies.applicationMutationCenter.currentSequence
        let inserted = try await seeder.seedLargeSampleDataIfNeeded()
        XCTAssertFalse(inserted)
        XCTAssertEqual(dependencies.applicationMutationCenter.currentSequence, originalSequence)
        XCTAssertTrue(try dependencies.animalFeatureDependencies.listRepository.fetchAnimals().isEmpty)
        XCTAssertEqual(
            try dependencies.pastureFeatureDependencies.listRepository.fetchPastures().map(\.id),
            [pasture.id]
        )
    }

}
