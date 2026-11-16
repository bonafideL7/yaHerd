import CoreData
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataMultiHerdDiscoveryTests: XCTestCase {
    func testDiscoveryIncludesOwnedAndSharedHerdsWithoutChangingSelection() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let selectedID = UUID()
        let sharedID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let stores = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores)
            let privateStore = try XCTUnwrap(stores.first {
                $0.url?.lastPathComponent == CoreDataPersistentContainer.storeFileName
            })
            let sharedStore = try XCTUnwrap(stores.first {
                $0.url?.lastPathComponent == CoreDataPersistentContainer.sharedStoreFileName
            })
            for (id, name, store) in [
                (selectedID, "Owned", privateStore),
                (sharedID, "Joined", sharedStore)
            ] {
                let herd = CDHerd(context: context)
                herd.id = id
                herd.name = name
                herd.createdAt = Date(timeIntervalSince1970: 100)
                herd.updatedAt = Date(timeIntervalSince1970: 200)
                context.assign(herd, to: store)
            }
            try context.save()
        }

        let selection = AppCurrentHerdSelection(currentHerdID: selectedID)
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let available = try repository.fetchAccessibleHerds()
        XCTAssertEqual(available.count, 2)
        XCTAssertEqual(Set(available.map(\.id)), [selectedID, sharedID])
        XCTAssertEqual(available.first { $0.id == selectedID }?.category, .owned)
        XCTAssertEqual(available.first { $0.id == sharedID }?.category, .shared)
        XCTAssertEqual(selection.currentHerdID, selectedID)
    }

    func testCreateOwnedHerdTargetsPrivateStoreAndPreservesSharedHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)

        let first = try await repository.createOwnedHerd(named: "North")
        let second = try await repository.createOwnedHerd(named: "South")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(selection.currentHerdID)
        XCTAssertEqual(try repository.fetchAccessibleHerds().count, 2)

        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let stores = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores)
            let privateStore = try XCTUnwrap(stores.first {
                $0.url?.lastPathComponent == CoreDataPersistentContainer.storeFileName
            })
            let sharedStore = try XCTUnwrap(stores.first {
                $0.url?.lastPathComponent == CoreDataPersistentContainer.sharedStoreFileName
            })
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            request.affectedStores = [privateStore]
            XCTAssertEqual(Set(try context.fetch(request).compactMap(\.id)), [first.id, second.id])
            request.affectedStores = [sharedStore]
            XCTAssertTrue(try context.fetch(request).isEmpty)
        }
        do {
            _ = try await repository.createOwnedHerd(named: "   ")
            XCTFail("A blank name must not create a root")
        } catch {
            XCTAssertEqual(error as? HerdRepositoryError, .emptyName)
        }
        XCTAssertEqual(try repository.fetchAccessibleHerds().count, 2)
    }

    func testDuplicateIDsAcrossStoresFailDiscoveryRatherThanSelectingOne() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL, mirroringEnabled: false
        )
        let duplicatedID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let stores = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores)
            for store in stores {
                let herd = CDHerd(context: context)
                herd.id = duplicatedID
                herd.name = "Duplicate"
                herd.createdAt = Date(timeIntervalSince1970: 100)
                herd.updatedAt = Date(timeIntervalSince1970: 100)
                context.assign(herd, to: store)
            }
            try context.save()
        }

        let repository = CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(), assembly: assembly
        )
        XCTAssertThrowsError(try repository.fetchAccessibleHerds()) {
            XCTAssertEqual(
                $0 as? CoreDataPersistenceError,
                .duplicateApplicationID(
                    entity: CDHerd.coreDataEntityName,
                    id: duplicatedID,
                    herdID: nil
                )
            )
        }
    }

    func testIncompleteImportedRootIsNotOfferedAsSelectable() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = try assembly.contextFactory.makeWriteContext()
        let validID = UUID()
        try context.performAndWait {
            let complete = CDHerd(context: context)
            complete.id = validID
            complete.name = "Ready"
            complete.createdAt = Date(timeIntervalSince1970: 100)
            complete.updatedAt = Date(timeIntervalSince1970: 100)
            let incomplete = CDHerd(context: context)
            incomplete.id = UUID()
            incomplete.name = nil
            incomplete.createdAt = nil
            incomplete.updatedAt = nil
            try context.save()
        }
        let repository = CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(), assembly: assembly
        )
        XCTAssertEqual(try repository.fetchAccessibleHerds().map(\.id), [validID])
    }

    func testSelectionSwitchesRepositoriesWithoutChangingStoredHerds() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let firstID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        let app = CoreDataAppPersistenceAssembly(
            assembly: assembly, currentHerdID: firstID
        )
        let repository = app.makeDependencies(dataAccessMode: .readWrite).herdRepository
        let second = try await repository.createOwnedHerd(named: "Second")
        XCTAssertEqual(try repository.fetchCurrentHerd().id, firstID)

        try app.selectAccessibleHerd(id: second.id)
        XCTAssertEqual(try repository.fetchCurrentHerd().id, second.id)

        XCTAssertThrowsError(try app.selectAccessibleHerd(id: UUID())) {
            XCTAssertEqual($0 as? HerdRepositoryError, .missingHerd)
        }
        XCTAssertEqual(try repository.fetchCurrentHerd().id, second.id)

        try app.selectAccessibleHerd(id: firstID)
        XCTAssertEqual(try repository.fetchCurrentHerd().id, firstID)
        XCTAssertEqual(try repository.fetchAccessibleHerds().count, 2)
    }

    func testSelectionRejectsIncompleteImportedHerdWithoutLosingCurrentSelection() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let firstID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        let incompleteID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let incomplete = CDHerd(context: context)
            incomplete.id = incompleteID
            incomplete.name = nil
            incomplete.createdAt = nil
            incomplete.updatedAt = nil
            try context.save()
        }

        let app = CoreDataAppPersistenceAssembly(
            assembly: assembly, currentHerdID: firstID
        )
        let repository = app.makeDependencies(dataAccessMode: .readWrite).herdRepository
        XCTAssertThrowsError(try app.selectAccessibleHerd(id: incompleteID)) {
            XCTAssertEqual($0 as? HerdRepositoryError, .missingHerd)
        }
        XCTAssertEqual(try repository.fetchCurrentHerd().id, firstID)
    }
}
