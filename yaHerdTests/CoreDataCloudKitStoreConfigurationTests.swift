import CloudKit
import CoreData
import Foundation
import XCTest
@testable import yaHerd

final class CoreDataCloudKitStoreConfigurationTests: XCTestCase {
    func testCloudKitStoresReuseExistingSQLiteAsPrivateAndSeparateSharedURL() {
        let originalStore = URL(fileURLWithPath: "/tmp/yaHerd-existing/yaHerd.sqlite")
        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: originalStore
        )

        XCTAssertEqual(descriptions.count, 2)
        XCTAssertEqual(descriptions[0].url, originalStore)
        XCTAssertEqual(descriptions[1].url, originalStore.deletingLastPathComponent()
            .appendingPathComponent("yaHerd-shared.sqlite"))
        XCTAssertNotEqual(descriptions[0].url, descriptions[1].url)

        XCTAssertEqual(descriptions[0].cloudKitContainerOptions?.databaseScope, .private)
        XCTAssertEqual(descriptions[1].cloudKitContainerOptions?.databaseScope, .shared)
        for description in descriptions {
            XCTAssertEqual(description.type, NSSQLiteStoreType)
            XCTAssertEqual(
                description.cloudKitContainerOptions?.containerIdentifier,
                CoreDataPersistentContainer.cloudKitContainerIdentifier
            )
            XCTAssertFalse(description.shouldMigrateStoreAutomatically)
            XCTAssertFalse(description.shouldInferMappingModelAutomatically)
            XCTAssertEqual(
                description.options[NSPersistentHistoryTrackingKey] as? NSNumber,
                NSNumber(value: true)
            )
            XCTAssertEqual(
                description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber,
                NSNumber(value: true)
            )
        }
    }

    func testCloudKitStoreConfigurationDoesNotTouchLocalDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existingStore = directory.appendingPathComponent("yaHerd.sqlite")
        let original = Data("existing database sentinel".utf8)
        try original.write(to: existingStore)

        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: existingStore
        )

        XCTAssertEqual(descriptions.first?.url, existingStore)
        XCTAssertEqual(try Data(contentsOf: existingStore), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("yaHerd-shared.sqlite").path
        ))
    }

    @MainActor
    func testRecoveryInventoryIncludesBothCloudKitStoresAndTheirJournals() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yaHerd-recovery-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("yaHerd", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let storeNames = [
            CoreDataPersistentContainer.storeFileName,
            CoreDataPersistentContainer.storeFileName + "-wal",
            CoreDataPersistentContainer.sharedStoreFileName,
            CoreDataPersistentContainer.sharedStoreFileName + "-wal",
            CoreDataPersistentContainer.sharedStoreFileName + "-shm",
            CoreDataPersistentContainer.sharedStoreFileName + "-journal"
        ]
        for name in storeNames {
            try Data("preserve \(name)".utf8)
                .write(to: directory.appendingPathComponent(name))
        }
        try Data("unrelated".utf8)
            .write(to: directory.appendingPathComponent("unrelated.sqlite"))

        let controller = RecoveryModeController(
            context: RecoveryModeContext(startupError: "Simulated store failure"),
            applicationSupportURL: root,
            automaticallyRefreshDiagnostics: false
        )
        controller.refreshDiagnostics()

        XCTAssertNil(controller.diagnosticsErrorMessage)
        XCTAssertEqual(
            Set(controller.diagnostics.recoverableStoreFiles.map(\.archiveName)),
            Set(storeNames)
        )
        controller.prepareExport()
        XCTAssertNil(controller.exportErrorMessage)
        XCTAssertNotNil(controller.exportDocument)
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent(
                CoreDataPersistentContainer.sharedStoreFileName
            )),
            Data("preserve \(CoreDataPersistentContainer.sharedStoreFileName)".utf8)
        )
    }

    func testTwoStoreLoaderPreservesExistingPrivateHerdAndStoresSharedRecordsSeparately() async throws {
        let harness = try CoreDataPersistenceHarness()
        let localAssembly = try await harness.makeAssembly()
        let ownedHerdID = UUID()
        let sharedHerdID = UUID()

        try await localAssembly.transactionExecutor.performWrite { context in
            let herd = CDHerd(context: context)
            herd.id = ownedHerdID
            herd.name = "Existing Local Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)
        }

        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: harness.storeURL
        )
        // The CI simulator is unsigned; exercise the actual two-SQLite-store
        // loader without starting CloudKit mirroring.
        descriptions.forEach { $0.cloudKitContainerOptions = nil }

        let cloudContainer = try await CoreDataPersistentContainer.loadCloudKit(
            storeDescriptions: descriptions
        )
        let stores = cloudContainer.persistentStoreCoordinator.persistentStores
        XCTAssertEqual(stores.count, 2)
        let privateURL = harness.storeURL
        let sharedURL = harness.directoryURL.appendingPathComponent(
            CoreDataPersistentContainer.sharedStoreFileName
        )
        XCTAssertTrue(stores.contains { $0.url == privateURL })
        XCTAssertTrue(stores.contains { $0.url == sharedURL })

        let context = cloudContainer.makeBackgroundContext()
        try context.performAndWait {
            let ownedHerd = try XCTUnwrap(
                CoreDataLookup().herd(id: ownedHerdID, in: context)
            )
            XCTAssertEqual(ownedHerd.objectID.persistentStore?.url, privateURL)

            let sharedHerd = CDHerd(context: context)
            sharedHerd.id = sharedHerdID
            sharedHerd.name = "Shared Herd"
            sharedHerd.createdAt = Date(timeIntervalSince1970: 200)
            sharedHerd.updatedAt = Date(timeIntervalSince1970: 200)
            let sharedStore = try XCTUnwrap(
                context.persistentStoreCoordinator?.persistentStores.first {
                    $0.url == sharedURL
                }
            )
            context.assign(sharedHerd, to: sharedStore)
            try context.save()
        }

        let reopenedLocal = try await harness.makeAssembly(accessMode: .readOnly)
        let localContext = reopenedLocal.contextFactory.makeReadContext()
        try localContext.performAndWait {
            XCTAssertNotNil(try CoreDataLookup().herd(id: ownedHerdID, in: localContext))
            XCTAssertNil(try CoreDataLookup().herd(id: sharedHerdID, in: localContext))
        }

        let readContext = cloudContainer.makeBackgroundContext()
        try readContext.performAndWait {
            let sharedHerd = try XCTUnwrap(
                CoreDataLookup().herd(id: sharedHerdID, in: readContext)
            )
            XCTAssertEqual(sharedHerd.objectID.persistentStore?.url, sharedURL)
        }
    }

    func testTwoStoreLoadFailureDoesNotReplaceOrDeleteExistingPrivateHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let localAssembly = try await harness.makeAssembly()
        let ownedHerdID = UUID()

        try await localAssembly.transactionExecutor.performWrite { context in
            let herd = CDHerd(context: context)
            herd.id = ownedHerdID
            herd.name = "Keep Existing Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)
        }

        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: harness.storeURL
        )
        descriptions.forEach { $0.cloudKitContainerOptions = nil }
        // An invalid SQLite payload exercises the actual per-store load failure,
        // rather than being rejected by the topology preflight.
        let sharedURL = harness.directoryURL.appendingPathComponent(
            CoreDataPersistentContainer.sharedStoreFileName
        )
        let invalidSharedStore = Data("not a SQLite database".utf8)
        try invalidSharedStore.write(to: sharedURL)

        do {
            _ = try await CoreDataPersistentContainer.loadCloudKit(
                storeDescriptions: descriptions
            )
            XCTFail("An invalid shared store must fail the entire two-store loader.")
        } catch let error as CoreDataPersistenceError {
            guard case .storeLoadFailed = error else {
                return XCTFail("Expected the actual shared-store load failure, got \(error).")
            }
        }

        XCTAssertEqual(try Data(contentsOf: sharedURL), invalidSharedStore)
        let reopenedLocal = try await harness.makeAssembly(accessMode: .readOnly)
        let context = reopenedLocal.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertEqual(
                try CoreDataLookup().herd(id: ownedHerdID, in: context)?.name,
                "Keep Existing Herd"
            )
        }
    }

    @MainActor
    func testTwoStorePersistenceAssemblyConnectsSelectedHerdApplicationGraphs() async throws {
        let harness = try CoreDataPersistenceHarness()
        let existingAssembly = try await harness.makeAssembly()
        let privateHerdID = UUID()
        let sharedHerdID = UUID()

        // An existing development installation already has this private Herd.
        try await existingAssembly.transactionExecutor.performWrite { context in
            let herd = CDHerd(context: context)
            herd.id = privateHerdID
            herd.name = "Existing Private Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)
        }

        // Use the production two-store assembly without starting CloudKit in CI.
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        let sharedURL = harness.directoryURL.appendingPathComponent(
            CoreDataPersistentContainer.sharedStoreFileName
        )

        // Simulate a shared root imported into the shared SQLite store.
        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let sharedStore = try XCTUnwrap(
                writer.persistentStoreCoordinator?.persistentStores.first {
                    $0.url == sharedURL
                }
            )
            let herd = CDHerd(context: writer)
            herd.id = sharedHerdID
            herd.name = "Imported Shared Herd"
            herd.createdAt = Date(timeIntervalSince1970: 200)
            herd.updatedAt = Date(timeIntervalSince1970: 200)
            writer.assign(herd, to: sharedStore)
            try writer.save()
        }

        let privateDependencies = CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: privateHerdID
        ).makeDependencies(dataAccessMode: .readWrite)
        let sharedDependencies = CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: sharedHerdID
        ).makeDependencies(dataAccessMode: .readWrite)

        XCTAssertEqual(
            try privateDependencies.herdRepository.fetchCurrentHerd().name,
            "Existing Private Herd"
        )
        XCTAssertEqual(
            try sharedDependencies.herdRepository.fetchCurrentHerd().name,
            "Imported Shared Herd"
        )

        let privatePasture = try privateDependencies.pastureFeatureDependencies
            .createRepository.create(input: PastureInput(
                name: "Private Pasture",
                acreage: nil,
                usableAcreage: nil,
                targetAcresPerHead: nil
            ))
        let sharedPasture = try sharedDependencies.pastureFeatureDependencies
            .createRepository.create(input: PastureInput(
                name: "Shared Pasture",
                acreage: nil,
                usableAcreage: nil,
                targetAcresPerHead: nil
            ))

        XCTAssertEqual(
            try privateDependencies.pastureFeatureDependencies.listRepository
                .fetchPastures().map(\.id),
            [privatePasture.id]
        )
        XCTAssertEqual(
            try sharedDependencies.pastureFeatureDependencies.listRepository
                .fetchPastures().map(\.id),
            [sharedPasture.id]
        )

        // Reopen both SQLite stores, not just fresh contexts in the same assembly.
        let reopened = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        let privateURL = harness.storeURL
        let read = reopened.contextFactory.makeReadContext()
        try read.performAndWait {
            let lookup = CoreDataLookup()
            let owned = try XCTUnwrap(lookup.herdOwned(
                CDPasture.self,
                id: privatePasture.id,
                herdID: privateHerdID,
                in: read
            ))
            let shared = try XCTUnwrap(lookup.herdOwned(
                CDPasture.self,
                id: sharedPasture.id,
                herdID: sharedHerdID,
                in: read
            ))
            XCTAssertEqual(owned.name, "Private Pasture")
            XCTAssertEqual(shared.name, "Shared Pasture")
            XCTAssertEqual(owned.objectID.persistentStore?.url, privateURL)
            XCTAssertEqual(shared.objectID.persistentStore?.url, sharedURL)
            XCTAssertNil(try lookup.herdOwned(
                CDPasture.self,
                id: sharedPasture.id,
                herdID: privateHerdID,
                in: read
            ))
        }
    }

    func testTwoStoreLoaderRejectsDuplicateFileAndSymlinkBeforeTouchingPrivateData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let privateURL = directory.appendingPathComponent("yaHerd.sqlite")
        let original = Data("existing local Herd sentinel".utf8)
        try original.write(to: privateURL)

        let aliasURL = directory.appendingPathComponent("same-store-alias.sqlite")
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: privateURL)

        for duplicateURL in [privateURL, aliasURL] {
            let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
                privateStoreURL: privateURL
            )
            descriptions.forEach { $0.cloudKitContainerOptions = nil }
            descriptions[1].url = duplicateURL

            do {
                _ = try await CoreDataPersistentContainer.loadCloudKit(
                    storeDescriptions: descriptions
                )
                XCTFail("A private SQLite file cannot also be the shared store.")
            } catch let error as CoreDataPersistenceError {
                guard case .storeLoadFailed = error else {
                    return XCTFail("Expected a store topology error, got \(error).")
                }
            }
            XCTAssertEqual(try Data(contentsOf: privateURL), original)
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(
                CoreDataPersistentContainer.sharedStoreFileName
            ).path
        ))
    }

    func testTwoStoreLoaderRejectsHardLinkedPrivateAndSharedSQLiteFiles() async throws {
        let harness = try CoreDataPersistenceHarness()
        let existingAssembly = try await harness.makeAssembly()
        let herdID = UUID()

        try await existingAssembly.transactionExecutor.performWrite { context in
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Existing Private Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)
        }

        let sharedURL = harness.directoryURL.appendingPathComponent(
            CoreDataPersistentContainer.sharedStoreFileName
        )
        try FileManager.default.linkItem(at: harness.storeURL, to: sharedURL)
        XCTAssertNotEqual(harness.storeURL, sharedURL)

        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: harness.storeURL
        )
        descriptions.forEach { $0.cloudKitContainerOptions = nil }

        // Both a direct hard link and a symlink to a hard-linked alias must
        // fail before Core Data opens either store. Resolving only the URLs
        // (or looking up the symlink's inode) does not catch both cases.
        for variant in 0..<2 {
            if variant == 1 {
                let aliasURL = harness.directoryURL.appendingPathComponent(
                    "shared-hard-link-alias.sqlite"
                )
                try FileManager.default.moveItem(at: sharedURL, to: aliasURL)
                try FileManager.default.createSymbolicLink(
                    at: sharedURL,
                    withDestinationURL: aliasURL
                )
            }

            do {
                _ = try await CoreDataPersistentContainer.loadCloudKit(
                    storeDescriptions: descriptions
                )
                XCTFail("A hard link must not make one SQLite file both private and shared.")
            } catch let error as CoreDataPersistenceError {
                guard case .storeLoadFailed = error else {
                    return XCTFail("Expected a store topology error, got \(error).")
                }
            }
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let read = reopened.contextFactory.makeReadContext()
        try read.performAndWait {
            XCTAssertEqual(
                try CoreDataLookup().herd(id: herdID, in: read)?.name,
                "Existing Private Herd"
            )
        }
    }

    func testTwoStoreLoaderRejectsIncorrectCloudKitScopesWithoutOpeningStores() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let privateURL = directory.appendingPathComponent("yaHerd.sqlite")
        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: privateURL
        )
        let privateOptions = descriptions[0].cloudKitContainerOptions
        descriptions[0].cloudKitContainerOptions = descriptions[1].cloudKitContainerOptions
        descriptions[1].cloudKitContainerOptions = privateOptions

        do {
            _ = try await CoreDataPersistentContainer.loadCloudKit(
                storeDescriptions: descriptions
            )
            XCTFail("Swapped private and shared CloudKit scopes must be rejected.")
        } catch let error as CoreDataPersistenceError {
            guard case .storeLoadFailed = error else {
                return XCTFail("Expected a CloudKit scope error, got \(error).")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateURL.path))
    }

    func testTwoStoreLoaderRejectsMixedMirroredAndLocalConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let privateURL = directory.appendingPathComponent("yaHerd.sqlite")
        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: privateURL
        )
        descriptions[1].cloudKitContainerOptions = nil

        do {
            _ = try await CoreDataPersistentContainer.loadCloudKit(
                storeDescriptions: descriptions
            )
            XCTFail("A local-only shared store cannot accompany a mirrored private store.")
        } catch let error as CoreDataPersistenceError {
            guard case .storeLoadFailed = error else {
                return XCTFail("Expected a mismatched mirroring configuration error, got \(error).")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateURL.path))
    }

    func testTwoStoreLoaderRejectsSwappedSQLiteURLsBeforeTouchingExistingHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let existingAssembly = try await harness.makeAssembly()
        let ownedHerdID = UUID()

        try await existingAssembly.transactionExecutor.performWrite { context in
            let herd = CDHerd(context: context)
            herd.id = ownedHerdID
            herd.name = "Existing Private Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)
        }

        let descriptions = CoreDataPersistentContainer.cloudKitStoreDescriptions(
            privateStoreURL: harness.storeURL
        )
        // Exercise the same production store loader on the unsigned CI runner.
        descriptions.forEach { $0.cloudKitContainerOptions = nil }

        // Both files have valid local URLs; merely checking that URLs differ or
        // CloudKit scopes are in order cannot prevent reversed file ownership.
        let sharedURL = try XCTUnwrap(descriptions[1].url)
        descriptions[0].url = sharedURL
        descriptions[1].url = harness.storeURL

        do {
            _ = try await CoreDataPersistentContainer.loadCloudKit(
                storeDescriptions: descriptions
            )
            XCTFail("Swapped private and shared SQLite URLs must be rejected.")
        } catch let error as CoreDataPersistenceError {
            guard case .storeLoadFailed = error else {
                return XCTFail("Expected a store topology error, got \(error).")
            }
        }

        // A failed preflight must not create the shared database or alter the
        // existing local-only installation's private Herd.
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedURL.path))
        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let context = reopened.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertEqual(
                try CoreDataLookup().herd(id: ownedHerdID, in: context)?.name,
                "Existing Private Herd"
            )
        }
    }

    #if DEBUG
    func testSchemaDryRunRejectsLocalOnlyStoreDescriptions() async throws {
        let harness = try CoreDataPersistenceHarness()
        let container = try await CoreDataPersistentContainer.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )

        XCTAssertThrowsError(try container.validateCloudKitSchemaDryRun()) { error in
            guard case .storeLoadFailed = error as? CoreDataPersistenceError else {
                return XCTFail("Expected mirrored-store preflight failure, got \(error).")
            }
        }
        XCTAssertThrowsError(try container.initializeDevelopmentCloudKitSchema()) { error in
            guard case .storeLoadFailed = error as? CoreDataPersistenceError else {
                return XCTFail("Expected mirrored-store preflight failure, got \(error).")
            }
        }
    }

    func testSignedDevelopmentExistingLocalStoreAdoptsPrivateMirroringWithoutChangingRecords() async throws {
        // Explicit, signed-development acceptance check. Loading a mirrored
        // private store may export local records to this Apple Account; never
        // run automatically in CI or against a user's application database.
        guard ProcessInfo.processInfo.environment["YAHERD_CLOUDKIT_STORE_ADOPTION"] == "1" else {
            throw XCTSkip(
                "Run M04 first, then opt in with YAHERD_CLOUDKIT_STORE_ADOPTION=1 " +
                "on a development-signed device using the intended Apple Account."
            )
        }

        let harness = try CoreDataPersistenceHarness()
        let original = try await harness.makeAssembly()
        let herdID = UUID()
        let animalID = UUID()
        let tagID = UUID()
        let pastureID = UUID()

        // Populate a real local-only SQLite store before enabling mirroring.
        try await original.transactionExecutor.performWrite { context in
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Existing Local Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)

            let pasture = CDPasture(context: context)
            pasture.id = pastureID
            pasture.name = "Existing Pasture"
            pasture.herd = herd

            let animal = CDAnimal(context: context)
            animal.id = animalID
            animal.name = "Existing Cow"
            animal.birthDate = Date(timeIntervalSince1970: 100)
            animal.herd = herd
            animal.currentPasture = pasture

            let tag = CDAnimalTag(context: context)
            tag.id = tagID
            tag.number = "001"
            tag.herd = herd
            tag.animal = animal
        }

        // Unlike unsigned two-store tests, this loads the actual mirrored
        // private/shared CloudKit configuration against the populated store.
        let mirrored = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: true
        )
        // Capture Sendable URLs, not the mutable test harness, in the
        // Core Data context's isolated closure.
        let privateStoreURL = harness.storeURL
        let sharedStoreURL = harness.directoryURL.appendingPathComponent(
            CoreDataPersistentContainer.sharedStoreFileName
        )
        let context = mirrored.contextFactory.makeReadContext()
        try context.performAndWait {
            let stores = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores)
            XCTAssertEqual(stores.count, 2)
            let privateStore = try XCTUnwrap(stores.first { $0.url == privateStoreURL })
            let sharedStore = try XCTUnwrap(stores.first { $0.url == sharedStoreURL })
            XCTAssertFalse(privateStore === sharedStore)

            let lookup = CoreDataLookup()
            let herd = try XCTUnwrap(lookup.herd(id: herdID, in: context))
            XCTAssertEqual(herd.name, "Existing Local Herd")
            XCTAssertTrue(herd.objectID.persistentStore === privateStore)

            let pasture = try XCTUnwrap(lookup.herdOwned(
                CDPasture.self, id: pastureID, herdID: herdID, in: context
            ))
            let animal = try XCTUnwrap(lookup.herdOwned(
                CDAnimal.self, id: animalID, herdID: herdID, in: context
            ))
            let tag = try XCTUnwrap(lookup.herdOwned(
                CDAnimalTag.self, id: tagID, herdID: herdID, in: context
            ))
            XCTAssertTrue(pasture.objectID.persistentStore === privateStore)
            XCTAssertTrue(animal.objectID.persistentStore === privateStore)
            XCTAssertTrue(tag.objectID.persistentStore === privateStore)
            XCTAssertEqual(animal.currentPasture?.id, pastureID)
            XCTAssertEqual(tag.animal?.id, animalID)

            let wrongStoreRequest = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            wrongStoreRequest.predicate = NSPredicate(format: "id == %@", herdID as NSUUID)
            wrongStoreRequest.affectedStores = [sharedStore]
            XCTAssertTrue(try context.fetch(wrongStoreRequest).isEmpty)
        }

        // Exercise the selected-Herd save boundary on the actual mirrored
        // private store and verify no temporary copy or duplicate root arose.
        try await mirrored.transactionExecutor.performWrite(herdID: herdID) { context in
            let pasture = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: pastureID, herdID: herdID, in: context
            ))
            pasture.name = "Updated Pasture"
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let read = reopened.contextFactory.makeReadContext()
        try read.performAndWait {
            let lookup = CoreDataLookup()
            let herd = try XCTUnwrap(lookup.herd(id: herdID, in: read))
            XCTAssertEqual(herd.id, herdID)
            let pasture = try XCTUnwrap(lookup.herdOwned(
                CDPasture.self, id: pastureID, herdID: herdID, in: read
            ))
            let animal = try XCTUnwrap(lookup.herdOwned(
                CDAnimal.self, id: animalID, herdID: herdID, in: read
            ))
            XCTAssertEqual(pasture.name, "Updated Pasture")
            XCTAssertEqual(animal.currentPasture?.id, pastureID)
            XCTAssertNotNil(try lookup.herdOwned(
                CDAnimalTag.self, id: tagID, herdID: herdID, in: read
            ))
        }
    }

    func testSignedDevelopmentCloudKitSchemaDryRun() async throws {
        // Run explicitly from a development-signed Xcode test scheme with
        // YAHERD_CLOUDKIT_SCHEMA_DRY_RUN=1 in the test process environment.
        // CI deliberately uses unsigned simulator builds and skips this test.
        guard ProcessInfo.processInfo.environment["YAHERD_CLOUDKIT_SCHEMA_DRY_RUN"] == "1" else {
            throw XCTSkip(
                "Signed CloudKit schema validation requires explicit opt-in: " +
                "set YAHERD_CLOUDKIT_SCHEMA_DRY_RUN=1 in the signed development test scheme."
            )
        }

        // This fresh, isolated store pair must never open the user's existing
        // database or initialize CloudKit schema on application startup.
        let harness = try CoreDataPersistenceHarness()
        let container = try await CoreDataPersistentContainer.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: true
        )
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.count, 2)

        // Apple's dry-run validates schema compatibility and does not upload
        // representative records to CloudKit.
        try container.validateCloudKitSchemaDryRun()
    }

    func testSignedDevelopmentCloudKitSchemaInitialization() async throws {
        // This test uploads representative records to the DEVELOPMENT
        // CloudKit environment. Run only with a development-provisioned
        // test host and YAHERD_CLOUDKIT_SCHEMA_INITIALIZE=1 explicitly set.
        // It must never run during ordinary app launch or unsigned CI.
        guard ProcessInfo.processInfo.environment["YAHERD_CLOUDKIT_SCHEMA_INITIALIZE"] == "1" else {
            throw XCTSkip(
                "Development CloudKit schema initialization requires explicit opt-in: " +
                "set YAHERD_CLOUDKIT_SCHEMA_INITIALIZE=1 in a development-signed test scheme."
            )
        }

        let harness = try CoreDataPersistenceHarness()
        let container = try await CoreDataPersistentContainer.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: true
        )
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.count, 2)

        // Validate locally before creating record types in the development
        // CloudKit schema. Isolated SQLite files leave existing data untouched.
        try container.validateCloudKitSchemaDryRun()
        try container.initializeDevelopmentCloudKitSchema()
    }
    #endif
}
