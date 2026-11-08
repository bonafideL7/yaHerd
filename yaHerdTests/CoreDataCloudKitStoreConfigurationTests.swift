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
        let privateStore = try XCTUnwrap(stores.first { $0.url == harness.storeURL })
        let sharedURL = harness.directoryURL.appendingPathComponent(
            CoreDataPersistentContainer.sharedStoreFileName
        )
        let sharedStore = try XCTUnwrap(stores.first { $0.url == sharedURL })

        let context = cloudContainer.makeBackgroundContext()
        try context.performAndWait {
            let ownedHerd = try XCTUnwrap(
                CoreDataLookup().herd(id: ownedHerdID, in: context)
            )
            XCTAssertTrue(ownedHerd.objectID.persistentStore === privateStore)

            let sharedHerd = CDHerd(context: context)
            sharedHerd.id = sharedHerdID
            sharedHerd.name = "Shared Herd"
            sharedHerd.createdAt = Date(timeIntervalSince1970: 200)
            sharedHerd.updatedAt = Date(timeIntervalSince1970: 200)
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
            XCTAssertTrue(sharedHerd.objectID.persistentStore === sharedStore)
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
        descriptions[1].url = harness.directoryURL

        do {
            _ = try await CoreDataPersistentContainer.loadCloudKit(
                storeDescriptions: descriptions
            )
            XCTFail("An invalid shared store must fail the entire two-store loader.")
        } catch let error as CoreDataPersistenceError {
            guard case .storeLoadFailed = error else {
                return XCTFail("Expected the actual shared-store load failure, got \\(error).")
            }
        }

        let reopenedLocal = try await harness.makeAssembly(accessMode: .readOnly)
        let context = reopenedLocal.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertEqual(
                try CoreDataLookup().herd(id: ownedHerdID, in: context)?.name,
                "Keep Existing Herd"
            )
        }
    }

}
