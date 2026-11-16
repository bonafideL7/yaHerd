import CoreData
import XCTest
@testable import yaHerd

final class CoreDataHerdCatalogTests: XCTestCase {
    func testDiscoveryFindsMultipleOwnedAndSharedHerdsWithoutCreatingOrSelecting() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        let privateID = UUID()
        let otherPrivateID = UUID()
        let sharedID = UUID()
        let writer = try assembly.contextFactory.makeWriteContext()

        try writer.performAndWait {
            let stores = try XCTUnwrap(writer.persistentStoreCoordinator?.persistentStores)
            let ownedStore = try XCTUnwrap(stores.first {
                $0.url?.lastPathComponent == CoreDataPersistentContainer.storeFileName
            })
            let sharedStore = try XCTUnwrap(stores.first {
                $0.url?.lastPathComponent == CoreDataPersistentContainer.sharedStoreFileName
            })
            for (id, name, store) in [
                (privateID, "North", ownedStore),
                (otherPrivateID, "South", ownedStore),
                (sharedID, "Partner", sharedStore)
            ] {
                let herd = CDHerd(context: writer)
                herd.id = id
                herd.name = name
                herd.createdAt = Date(timeIntervalSince1970: 1)
                herd.updatedAt = Date(timeIntervalSince1970: 1)
                writer.assign(herd, to: store)
            }
            try writer.save()
        }

        let catalog = try CoreDataAppHerdBootstrapper.discoverAvailableHerds(
            assembly: assembly
        )
        XCTAssertEqual(catalog.herds.count, 3)
        XCTAssertEqual(catalog.incompleteRootCount, 0)
        XCTAssertEqual(catalog.herds.first { $0.id == privateID }?.category, .owned)
        XCTAssertEqual(catalog.herds.first { $0.id == otherPrivateID }?.category, .owned)
        XCTAssertEqual(catalog.herds.first { $0.id == sharedID }?.category, .shared)
        XCTAssertEqual(
            try CoreDataAppHerdBootstrapper.discoverAvailableHerds(
                assembly: assembly
            ).herds.count,
            3
        )
    }

    func testEmptyMirroredStoresStayEmptyUntilDeliberatePrivateCreation() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        XCTAssertTrue(
            try CoreDataAppHerdBootstrapper.discoverAvailableHerds(
                assembly: assembly
            ).herds.isEmpty
        )

        let created = try await CoreDataAppHerdBootstrapper.createOwnedHerd(
            assembly: assembly,
            named: "  Home Ranch  "
        )
        XCTAssertEqual(created.name, "Home Ranch")
        let catalog = try CoreDataAppHerdBootstrapper.discoverAvailableHerds(
            assembly: assembly
        )
        XCTAssertEqual(
            catalog.herds,
            [AvailableHerd(id: created.id, name: "Home Ranch", category: .owned)]
        )
        let reader = assembly.contextFactory.makeReadContext()
        try reader.performAndWait {
            let herd = try XCTUnwrap(CoreDataLookup().herd(id: created.id, in: reader))
            XCTAssertEqual(
                herd.objectID.persistentStore?.url?.lastPathComponent,
                CoreDataPersistentContainer.storeFileName
            )
        }
    }

    func testIncompleteImportedRootIsNotOfferedForSelection() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let partial = CDHerd(context: writer)
            partial.id = UUID()
            partial.name = nil
            partial.createdAt = Date()
            partial.updatedAt = Date()
            try writer.save()
        }
        let catalog = try CoreDataAppHerdBootstrapper.discoverAvailableHerds(
            assembly: assembly
        )
        XCTAssertEqual(catalog.incompleteRootCount, 1)
        XCTAssertTrue(catalog.herds.isEmpty)
    }

    func testEmptyHerdNameNeverWritesARecord() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        do {
            _ = try await CoreDataAppHerdBootstrapper.createOwnedHerd(
                assembly: assembly,
                named: " \n "
            )
            XCTFail("Expected an empty name to be rejected")
        } catch let error as HerdRepositoryError {
            XCTAssertEqual(error, .emptyName)
        }
        XCTAssertTrue(
            try CoreDataAppHerdBootstrapper.discoverAvailableHerds(
                assembly: assembly
            ).herds.isEmpty
        )
    }
}
