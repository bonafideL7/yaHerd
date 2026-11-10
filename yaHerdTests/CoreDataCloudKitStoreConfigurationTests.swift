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
        // A directory cannot be opened as the shared SQLite file.
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
}
