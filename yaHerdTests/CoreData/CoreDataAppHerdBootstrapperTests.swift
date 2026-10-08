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
        XCTAssertNil(graph.animalFeatureDependencies.sampleDataSeeder)

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
        XCTAssertNil(dependencies.animalFeatureDependencies.sampleDataSeeder)
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

    func testLegacyStorePreflightBlocksSilentFirstCoreDataOpenAndAllowsExistingCoreData() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("yaHerd-legacy-preflight-\(UUID().uuidString)", isDirectory: true)
        let coreDataDirectory = root.appendingPathComponent("yaHerd", isDirectory: true)
        try fileManager.createDirectory(
            at: coreDataDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: root) }

        let newStore = coreDataDirectory.appendingPathComponent(
            CoreDataPersistentContainer.storeFileName
        )
        let legacyStore = root.appendingPathComponent("yaHerdStore.store")
        let legacyJournal = root.appendingPathComponent("yaHerdStore.store-wal")
        let rollbackJournal = root.appendingPathComponent("yaHerdStore.store-journal")
        try Data("legacy data".utf8).write(to: legacyStore)
        try Data("legacy wal".utf8).write(to: legacyJournal)
        try Data("legacy rollback journal".utf8).write(to: rollbackJournal)

        let artifacts = CoreDataLegacyStorePreflight.legacyArtifacts(
            in: root,
            fileManager: fileManager
        )
        XCTAssertEqual(artifacts.map(\.lastPathComponent), [
            legacyStore.lastPathComponent,
            rollbackJournal.lastPathComponent,
            legacyJournal.lastPathComponent
        ])

        XCTAssertThrowsError(
            try CoreDataLegacyStorePreflight.ensureSafeFirstOpen(
                at: newStore,
                fileManager: fileManager
            )
        ) { error in
            guard let typedError = error as? CoreDataLegacyStorePreflightError,
                  case .legacyStoreFound(let files) = typedError else {
                XCTFail("Expected a recognized legacy store.")
                return
            }
            XCTAssertEqual(Set(files), Set([
                legacyStore.lastPathComponent,
                rollbackJournal.lastPathComponent,
                legacyJournal.lastPathComponent
            ]))
        }
        XCTAssertFalse(fileManager.fileExists(atPath: newStore.path))
        XCTAssertTrue(fileManager.fileExists(atPath: legacyStore.path))

        // A migrated Core Data store is authoritative even when archived
        // legacy files are still present for backup.
        try Data("new store exists".utf8).write(to: newStore)
        XCTAssertNoThrow(
            try CoreDataLegacyStorePreflight.ensureSafeFirstOpen(
                at: newStore,
                fileManager: fileManager
            )
        )
    }

    func testFirstOpenRejectsOrphanedRollbackJournalsWithoutModifyingThem() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("yaHerd-orphaned-journals-\(UUID().uuidString)", isDirectory: true)
        let storeDirectory = root.appendingPathComponent("yaHerd", isDirectory: true)
        try manager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let store = storeDirectory.appendingPathComponent(CoreDataPersistentContainer.storeFileName)
        let legacyJournal = root.appendingPathComponent("default.store-journal")
        let legacyBytes = Data("legacy rollback".utf8)
        try legacyBytes.write(to: legacyJournal)

        // A rollback journal without its legacy main file still blocks first open.
        XCTAssertThrowsError(try CoreDataLegacyStorePreflight.ensureSafeFirstOpen(at: store, fileManager: manager)) { error in
            guard case .legacyStoreFound(let files) = error as? CoreDataLegacyStorePreflightError else {
                XCTFail("Expected orphaned legacy rollback journal protection.")
                return
            }
            XCTAssertEqual(files, [legacyJournal.lastPathComponent])
        }
        XCTAssertFalse(manager.fileExists(atPath: store.path))
        XCTAssertEqual(try Data(contentsOf: legacyJournal), legacyBytes)

        try manager.removeItem(at: legacyJournal)

        let coreDataJournal = URL(fileURLWithPath: store.path + "-journal")
        let coreDataBytes = Data("core data rollback".utf8)
        try coreDataBytes.write(to: coreDataJournal)
        XCTAssertThrowsError(try CoreDataLegacyStorePreflight.ensureSafeFirstOpen(at: store, fileManager: manager)) { error in
            guard case .orphanedCoreDataSidecars(let files) = error as? CoreDataLegacyStorePreflightError else {
                XCTFail("Expected orphaned Core Data rollback journal protection.")
                return
            }
            XCTAssertEqual(files, [coreDataJournal.lastPathComponent])
        }
        XCTAssertFalse(manager.fileExists(atPath: store.path))
        XCTAssertEqual(try Data(contentsOf: coreDataJournal), coreDataBytes)

        // Once the parent store exists, it remains authoritative even with journals.
        try Data("existing core data".utf8).write(to: store)
        XCTAssertNoThrow(try CoreDataLegacyStorePreflight.ensureSafeFirstOpen(at: store, fileManager: manager))
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

        // Rollback journals are part of the required recovery payload, including
        // legacy journals without their main database.
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
                "LegacyAppSupport/default.store-journal"
            ])
        )
        controller.prepareExport()
        XCTAssertNil(controller.exportErrorMessage)
        XCTAssertNotNil(controller.exportDocument)
        XCTAssertTrue(manager.fileExists(atPath: coreDataJournal.path))
        XCTAssertTrue(manager.fileExists(atPath: legacyJournal.path))
    }

}
