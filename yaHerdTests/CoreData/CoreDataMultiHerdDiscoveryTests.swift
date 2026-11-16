import CoreData
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataMultiHerdDiscoveryTests: XCTestCase {
    func testStage3HerdSwitchResetsNavigationAndRejectsUnavailableRoots() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let first = UUID()
        let second = UUID()
        try await assembly.transactionExecutor.performWrite { context in
            for id in [first, second] {
                let root = CDHerd(context: context)
                root.id = id
                root.name = id == first ? "First" : "Second"
                root.createdAt = Date(timeIntervalSince1970: 100)
                root.updatedAt = Date(timeIntervalSince1970: 100)
            }
        }
        let selected = AppCurrentHerdSelection(currentHerdID: first)
        let repository = CoreDataHerdRepository(selection: selected, assembly: assembly)
        let navigation = AppNavigationState()
        navigation.selectedHerdID = first
        navigation.herdRouter.path = [.animal(UUID())]
        navigation.herdRouter.searchText = "First tag"
        navigation.openWorkArea(.session(UUID()))
        let lifecycle = AppHerdLifecycle(
            repository: repository, selection: selected, isMirroring: false
        )
        lifecycle.refresh(navigation: navigation)
        lifecycle.select(second, navigation: navigation)
        XCTAssertEqual(selected.currentHerdID, second)
        XCTAssertEqual(navigation.selectedHerdID, second)
        XCTAssertTrue(navigation.herdRouter.path.isEmpty)
        XCTAssertEqual(navigation.herdRouter.searchText, "")
        XCTAssertNil(navigation.fullScreenWorkflow)

        lifecycle.select(UUID(), navigation: navigation)
        XCTAssertEqual(selected.currentHerdID, second)
        XCTAssertEqual(navigation.selectedHerdID, second)
        XCTAssertNotNil(lifecycle.errorMessage)
    }

    func testStage3HerdSelectionRestoresOnlyAccessibleSnapshot() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let first = UUID()
        let second = UUID()
        try await assembly.transactionExecutor.performWrite { context in
            let root = CDHerd(context: context)
            root.id = first
            root.name = "First"
            root.createdAt = Date(timeIntervalSince1970: 100)
            root.updatedAt = Date(timeIntervalSince1970: 100)
        }
        let selected = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selected, assembly: assembly)
        let navigation = AppNavigationState()
        let lifecycle = AppHerdLifecycle(
            repository: repository, selection: selected, isMirroring: false
        )
        lifecycle.refresh(navigation: navigation)
        let inaccessible = AppNavigationState()
        inaccessible.selectedHerdID = second
        lifecycle.restoreSelection(
            from: try XCTUnwrap(inaccessible.restorationPayload()),
            navigation: navigation
        )
        XCTAssertNil(selected.currentHerdID)
        let accessible = AppNavigationState()
        accessible.selectedHerdID = first
        lifecycle.restoreSelection(
            from: try XCTUnwrap(accessible.restorationPayload()),
            navigation: navigation
        )
        XCTAssertEqual(selected.currentHerdID, first)
        XCTAssertEqual(navigation.selectedHerdID, first)
    }


    func testStage3AppLaunchWithMultipleOwnedHerdsShowsSelectionWithoutWriting() async throws {
        let harness = try CoreDataPersistenceHarness()
        let foundation = try await CoreDataPersistenceAssembly.load(storeURL: harness.storeURL)
        let firstID = UUID()
        let secondID = UUID()
        try await foundation.transactionExecutor.performWrite { context in
            for (id, name) in [(firstID, "First"), (secondID, "Second")] {
                let herd = CDHerd(context: context)
                herd.id = id
                herd.name = name
                herd.createdAt = Date(timeIntervalSince1970: 100)
                herd.updatedAt = Date(timeIntervalSince1970: 100)
            }
        }

        let app = try await CoreDataAppPersistenceAssembly.load(at: harness.storeURL)
        let dependencies = app.makeDependencies(dataAccessMode: .readWrite)
        XCTAssertNil(dependencies.herdSelection.currentHerdID)
        XCTAssertEqual(
            Set(try dependencies.herdRepository.fetchAccessibleHerds().map(\.id)),
            Set([firstID, secondID])
        )
    }

    func testStage3SelectingAvailableHerdUpdatesActiveRepositories() async throws {
        let foundation = try await CoreDataPersistenceAssembly.inMemory()
        let firstID = UUID()
        let secondID = UUID()
        try await foundation.transactionExecutor.performWrite { context in
            for (id, name) in [(firstID, "First"), (secondID, "Second")] {
                let herd = CDHerd(context: context)
                herd.id = id
                herd.name = name
                herd.createdAt = Date(timeIntervalSince1970: 100)
                herd.updatedAt = Date(timeIntervalSince1970: 100)
            }
        }
        let app = CoreDataAppPersistenceAssembly(assembly: foundation, currentHerdID: nil)
        let dependencies = app.makeDependencies(dataAccessMode: .readWrite)
        dependencies.herdSelection.select(firstID)
        XCTAssertEqual(try dependencies.herdRepository.fetchCurrentHerd().id, firstID)
        dependencies.herdSelection.select(secondID)
        XCTAssertEqual(try dependencies.herdRepository.fetchCurrentHerd().id, secondID)
    }

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
}
