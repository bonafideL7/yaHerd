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

    func testCancelledCreateDoesNotPersistAnUnwantedHerd() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let repository = CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(), assembly: assembly
        )

        // The user's Create task can be cancelled before the repository runs,
        // for example when the Herd chooser is dismissed.
        let creation = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.createOwnedHerd(named: "Dismissed")
        }

        do {
            _ = try await creation.value
            XCTFail("A cancelled Create task must not persist a Herd.")
        } catch is CancellationError {
            // The request was abandoned before any Core Data work.
        }

        XCTAssertTrue(try repository.fetchAccessibleHerds().isEmpty)
        let created = try await repository.createOwnedHerd(named: "Intended")
        XCTAssertEqual(try repository.fetchAccessibleHerds().map(\.id), [created.id])
    }

    func testCancellationAfterStagingRollsBackTheNewHerd() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let repository = CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(), assembly: assembly
        )
        let staged = expectation(description: "Herd is staged before save")
        let releaseSave = DispatchSemaphore(value: 0)
        defer { releaseSave.signal() }

        let creation = Task { @MainActor in
            try await repository.createOwnedHerd(named: "Dismissed", beforeSave: { _ in
                staged.fulfill()
                guard releaseSave.wait(timeout: .now() + 10) == .success else {
                    throw CancellationError()
                }
            })
        }

        await fulfillment(of: [staged], timeout: 5)
        creation.cancel()
        releaseSave.signal()

        do {
            _ = try await creation.value
            XCTFail("A cancelled staged Herd must not be saved.")
        } catch is CancellationError {
            // The pending insert was rolled back before committing.
        }

        XCTAssertTrue(try repository.fetchAccessibleHerds().isEmpty)
        let created = try await repository.createOwnedHerd(named: "Intended")
        XCTAssertEqual(try repository.fetchAccessibleHerds().map(\.id), [created.id])
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

    func testImportedRootWithoutUUIDDoesNotHideCompleteHerdOrCreateReplacement() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = try assembly.contextFactory.makeWriteContext()
        let completeID = UUID()
        try context.performAndWait {
            let ready = CDHerd(context: context)
            ready.id = completeID
            ready.name = "Available"
            ready.createdAt = Date(timeIntervalSince1970: 100)
            ready.updatedAt = ready.createdAt

            let importing = CDHerd(context: context)
            importing.id = nil
            importing.name = "Import pending"
            importing.createdAt = Date(timeIntervalSince1970: 200)
            importing.updatedAt = importing.createdAt
            try context.save()
        }

        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()
        XCTAssertEqual(directory.inventoryState, .incomplete)
        XCTAssertEqual(directory.herds.map(\.id), [completeID])
        XCTAssertNil(directory.selectedHerdID)

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            XCTAssertEqual(try read.count(for: request), 2)
        }
    }

    func testIncompleteImportedRootIsNotOfferedAsSelectable() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = try assembly.contextFactory.makeWriteContext()
        let validID = UUID()
        let incompleteID = UUID()
        try context.performAndWait {
            let complete = CDHerd(context: context)
            complete.id = validID
            complete.name = "Ready"
            complete.createdAt = Date(timeIntervalSince1970: 100)
            complete.updatedAt = Date(timeIntervalSince1970: 100)
            let incomplete = CDHerd(context: context)
            incomplete.id = incompleteID
            incomplete.name = nil
            incomplete.createdAt = nil
            incomplete.updatedAt = nil
            try context.save()
        }
        let repository = CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(), assembly: assembly
        )
        let inventory = try repository.fetchHerdInventory()
        XCTAssertEqual(inventory.herds.map(\.id), [validID])
        XCTAssertTrue(inventory.hasIncompleteRoots)
        XCTAssertEqual(try repository.fetchAccessibleHerds().map(\.id), [validID])

        let selection = AppCurrentHerdSelection()
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        directory.refresh()
        XCTAssertEqual(directory.inventoryState, .incomplete)
        XCTAssertEqual(directory.herds.map(\.id), [validID])

        // When the remaining import metadata arrives, the original root
        // becomes selectable without creating or rewriting its identity.
        let updateContext = try assembly.contextFactory.makeWriteContext()
        try updateContext.performAndWait {
            let imported = try XCTUnwrap(CoreDataLookup().herd(id: incompleteID, in: updateContext))
            imported.name = "Imported"
            imported.createdAt = Date(timeIntervalSince1970: 200)
            imported.updatedAt = Date(timeIntervalSince1970: 200)
            try updateContext.save()
        }

        directory.refresh()
        XCTAssertEqual(directory.inventoryState, .available)
        XCTAssertEqual(Set(directory.herds.map(\.id)), Set([validID, incompleteID]))
        XCTAssertNil(directory.selectedHerdID)
    }

    func testDeferredSampleSeedDoesNotWriteToNewlySelectedHerd() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let repository = CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(), assembly: assembly
        )
        let origin = try await repository.createOwnedHerd(named: "Original")
        let destination = try await repository.createOwnedHerd(named: "New selection")
        let app = CoreDataAppPersistenceAssembly(
            assembly: assembly, currentHerdID: origin.id
        )
        let dependencies = app.makeDependencies(dataAccessMode: .readWrite)
        let seeder = try XCTUnwrap(dependencies.animalFeatureDependencies.sampleDataSeeder)

        // The empty-state action began in the original Herd, but its Task was
        // scheduled after navigation switched to another empty Herd.
        app.currentHerdSelection.select(destination.id)
        for useLargeFixture in [false, true] {
            do {
                if useLargeFixture {
                    _ = try await seeder.seedLargeSampleDataIfNeeded(for: origin.id)
                } else {
                    _ = try await seeder.seedSampleDataIfNeeded(for: origin.id)
                }
                XCTFail("An old-Herd request must not seed the newly selected Herd.")
            } catch {
                XCTAssertEqual(error as? HerdRepositoryError, .missingHerd)
            }
        }

        XCTAssertTrue(
            try dependencies.animalFeatureDependencies.listRepository.fetchAnimals().isEmpty
        )
        app.currentHerdSelection.select(origin.id)
        XCTAssertTrue(
            try dependencies.animalFeatureDependencies.listRepository.fetchAnimals().isEmpty
        )

        // A valid request still seeds its own selected Herd without touching
        // the other Herd's empty records.
        let inserted = try await seeder.seedSampleDataIfNeeded(for: origin.id)
        XCTAssertTrue(inserted)
        XCTAssertEqual(
            try dependencies.animalFeatureDependencies.listRepository.fetchAnimals().count, 18
        )
        app.currentHerdSelection.select(destination.id)
        XCTAssertTrue(
            try dependencies.animalFeatureDependencies.listRepository.fetchAnimals().isEmpty
        )
    }

}
