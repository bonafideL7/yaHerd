@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

final class CoreDataStoreOwnershipTests: XCTestCase {
    func testHerdLookupResolvesItsOwningSQLiteStoreAndScopesOwnedRecords() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let context = assembly.contextFactory.makeReadContext()
        let coordinator = try XCTUnwrap(context.persistentStoreCoordinator)
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-test-shared.sqlite"),
            options: [
                NSMigratePersistentStoresAutomaticallyOption: false,
                NSInferMappingModelAutomaticallyOption: false
            ]
        )
        let privateHerdID = UUID()
        let sharedHerdID = UUID()
        let pastureID = UUID()

        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let privateHerd = Self.makeHerd(
                id: privateHerdID, name: "Owned Herd", in: writer, store: privateStore
            )
            let sharedHerd = Self.makeHerd(
                id: sharedHerdID, name: "Shared Herd", in: writer, store: sharedStore
            )
            Self.makePasture(id: pastureID, name: "Owned Pasture", herd: privateHerd,
                        in: writer, store: privateStore)
            Self.makePasture(id: pastureID, name: "Shared Pasture", herd: sharedHerd,
                        in: writer, store: sharedStore)
            try writer.save()
        }

        let reader = assembly.contextFactory.makeReadContext()
        try reader.performAndWait {
            let lookup = CoreDataLookup()
            XCTAssertTrue(try lookup.store(forHerdID: privateHerdID, in: reader) === privateStore)
            XCTAssertTrue(try lookup.store(forHerdID: sharedHerdID, in: reader) === sharedStore)
            XCTAssertNil(try lookup.store(forHerdID: UUID(), in: reader))

            let owned = try XCTUnwrap(lookup.herdOwned(
                CDPasture.self, id: pastureID, herdID: privateHerdID, in: reader
            ))
            let shared = try XCTUnwrap(lookup.herdOwned(
                CDPasture.self, id: pastureID, herdID: sharedHerdID, in: reader
            ))
            XCTAssertEqual(owned.name, "Owned Pasture")
            XCTAssertEqual(shared.name, "Shared Pasture")
            XCTAssertTrue(owned.objectID.persistentStore === privateStore)
            XCTAssertTrue(shared.objectID.persistentStore === sharedStore)

            let unqualifiedRequest = NSFetchRequest<CDPasture>(
                entityName: CDPasture.coreDataEntityName
            )
            unqualifiedRequest.predicate = NSPredicate(
                format: "id == %@", pastureID as NSUUID
            )
            let privateHerd = try XCTUnwrap(lookup.herd(id: privateHerdID, in: reader))
            try lookup.scope(unqualifiedRequest, toHerd: privateHerd, in: reader)
            XCTAssertTrue(unqualifiedRequest.affectedStores?.first === privateStore)
            XCTAssertEqual(try reader.fetch(unqualifiedRequest).map(\.name), ["Owned Pasture"])

            let sharedHerd = try XCTUnwrap(lookup.herd(id: sharedHerdID, in: reader))
            try lookup.scope(unqualifiedRequest, toHerd: sharedHerd, in: reader)
            XCTAssertTrue(unqualifiedRequest.affectedStores?.first === sharedStore)
            XCTAssertEqual(try reader.fetch(unqualifiedRequest).map(\.name), ["Shared Pasture"])
        }
    }

    func testInsertedHerdCannotLeaveAReadUnscopedAcrossPrivateAndSharedStores() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        let context = assembly.contextFactory.makeReadContext()
        let herdID = UUID()

        try context.performAndWait {
            let unsavedHerd = CDHerd(context: context)
            unsavedHerd.id = herdID
            unsavedHerd.name = "Unpersisted Herd"

            // A newly inserted root does not identify its eventual SQLite
            // store. An unrestricted fetch would inspect BOTH databases.
            let request = NSFetchRequest<CDPasture>(
                entityName: CDPasture.coreDataEntityName
            )
            XCTAssertThrowsError(
                try CoreDataLookup().scope(request, toHerd: unsavedHerd, in: context)
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataPersistenceError,
                    .unresolvedHerdStore(id: herdID)
                )
            }
            context.rollback()
        }
    }

    func testInsertedHerdImportValidatorsRejectUnscopedTwoStoreReads() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        let context = assembly.contextFactory.makeReadContext()
        let herdID = UUID()

        try context.performAndWait {
            let unsavedHerd = CDHerd(context: context)
            unsavedHerd.id = herdID
            unsavedHerd.name = "Unpersisted Herd"
            let expected = CoreDataPersistenceError.unresolvedHerdStore(id: herdID)

            // These import-integrity checks must not fall back to fetching
            // from both stores when the root has no resolved store identity.
            XCTAssertThrowsError(
                try CoreDataAnimalMutation.validateUnownedImportedAnimals(
                    herd: unsavedHerd, in: context
                )
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expected)
            }
            XCTAssertThrowsError(
                try CoreDataAnimalMutation.validateUnownedImportedPastures(
                    herd: unsavedHerd, in: context
                )
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expected)
            }
            XCTAssertThrowsError(
                try CoreDataAnimalMutation.validateLinkedImportedHistoryHerdOwnership(
                    herd: unsavedHerd, in: context
                )
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expected)
            }
            context.rollback()
        }
    }

    func testInsertedHerdReadScopeRetainsSingleStoreBehavior() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()
        let store = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores.first)

        try context.performAndWait {
            let unsavedHerd = CDHerd(context: context)
            unsavedHerd.id = UUID()
            unsavedHerd.name = "Unpersisted Local Herd"

            let request = NSFetchRequest<CDPasture>(
                entityName: CDPasture.coreDataEntityName
            )
            try CoreDataLookup().scope(request, toHerd: unsavedHerd, in: context)
            XCTAssertEqual(request.affectedStores?.count, 1)
            XCTAssertTrue(request.affectedStores?.first === store)
            // Existing single-store bootstrap and local validation remain valid.
            XCTAssertNoThrow(try CoreDataAnimalMutation.validateUnownedImportedAnimals(
                herd: unsavedHerd, in: context
            ))
            XCTAssertNoThrow(try CoreDataAnimalMutation.validateUnownedImportedPastures(
                herd: unsavedHerd, in: context
            ))
            context.rollback()
        }
    }

    func testBackgroundPastureProjectionsUseOnlyTheSelectedHerdStore() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-test-shared.sqlite"),
            options: nil
        )
        let privateHerdID = UUID()
        let sharedHerdID = UUID()
        let matchingPastureID = UUID()

        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let privateHerd = Self.makeHerd(
                id: privateHerdID, name: "Private", in: writer, store: privateStore
            )
            let sharedHerd = Self.makeHerd(
                id: sharedHerdID, name: "Shared", in: writer, store: sharedStore
            )
            Self.makePasture(
                id: matchingPastureID, name: "Private Pasture", herd: privateHerd,
                in: writer, store: privateStore
            )
            Self.makePasture(
                id: matchingPastureID, name: "Shared Pasture", herd: sharedHerd,
                in: writer, store: sharedStore
            )
            try writer.save()
        }

        let privateReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { privateHerdID }
        )
        let sharedReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { sharedHerdID }
        )

        let privatePastures = try await privateReader.fetchDashboardPastureRecords()
        let sharedPastures = try await sharedReader.fetchDashboardPastureRecords()
        XCTAssertEqual(privatePastures.map(\.name), ["Private Pasture"])
        XCTAssertEqual(sharedPastures.map(\.name), ["Shared Pasture"])
        XCTAssertEqual(privatePastures.map(\.id), [matchingPastureID])
        XCTAssertEqual(sharedPastures.map(\.id), [matchingPastureID])
    }

    func testDuplicateHerdIDAcrossStoresNeverSelectsArbitraryOwner() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let context = assembly.contextFactory.makeReadContext()
        let coordinator = try XCTUnwrap(context.persistentStoreCoordinator)
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-test-shared.sqlite"),
            options: nil
        )
        let herdID = UUID()

        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            _ = Self.makeHerd(id: herdID, name: "First", in: writer, store: privateStore)
            _ = Self.makeHerd(id: herdID, name: "Second", in: writer, store: sharedStore)
            try writer.save()
        }

        let reader = assembly.contextFactory.makeReadContext()
        try reader.performAndWait {
            XCTAssertThrowsError(
                try CoreDataLookup().store(forHerdID: herdID, in: reader)
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, .duplicateApplicationID(
                    entity: CDHerd.coreDataEntityName, id: herdID, herdID: nil
                ))
            }
        }
    }

    func testHerdQualifiedTransactionAssignsNewChildToTheSharedStore() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-test-shared.sqlite"),
            options: nil
        )
        let privateHerdID = UUID()
        let sharedHerdID = UUID()
        let sharedPastureID = UUID()

        let seedContext = try assembly.contextFactory.makeWriteContext()
        try seedContext.performAndWait {
            _ = Self.makeHerd(
                id: privateHerdID, name: "Private", in: seedContext, store: privateStore
            )
            _ = Self.makeHerd(
                id: sharedHerdID, name: "Shared", in: seedContext, store: sharedStore
            )
            try seedContext.save()
        }

        try await assembly.transactionExecutor.performWrite(herdID: sharedHerdID) { context in
            let herd = try XCTUnwrap(CoreDataLookup().herd(id: sharedHerdID, in: context))
            let pasture = CDPasture(context: context)
            pasture.id = sharedPastureID
            pasture.name = "Shared Pasture"
            pasture.sortOrder = 0
            pasture.herd = herd
        }

        let readContext = assembly.contextFactory.makeReadContext()
        try readContext.performAndWait {
            let pasture = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self,
                id: sharedPastureID,
                herdID: sharedHerdID,
                in: readContext
            ))
            XCTAssertTrue(pasture.objectID.persistentStore === sharedStore)

            let privateRequest = NSFetchRequest<CDPasture>(
                entityName: CDPasture.coreDataEntityName
            )
            privateRequest.predicate = NSPredicate(
                format: "id == %@", sharedPastureID as NSUUID
            )
            privateRequest.affectedStores = [privateStore]
            XCTAssertEqual(try readContext.count(for: privateRequest), 0)
        }
    }

    func testHerdQualifiedTransactionRejectsReparentingAnExistingForeignChild() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selectedHerdID = UUID()
        let foreignHerdID = UUID()
        let foreignPastureID = UUID()

        let seed = try assembly.contextFactory.makeWriteContext()
        try seed.performAndWait {
            let selectedHerd = CDHerd(context: seed)
            selectedHerd.id = selectedHerdID
            selectedHerd.name = "Selected"
            selectedHerd.createdAt = Date(timeIntervalSince1970: 100)
            selectedHerd.updatedAt = Date(timeIntervalSince1970: 100)

            let foreignHerd = CDHerd(context: seed)
            foreignHerd.id = foreignHerdID
            foreignHerd.name = "Foreign"
            foreignHerd.createdAt = Date(timeIntervalSince1970: 100)
            foreignHerd.updatedAt = Date(timeIntervalSince1970: 100)

            let pasture = CDPasture(context: seed)
            pasture.id = foreignPastureID
            pasture.name = "Original Foreign Pasture"
            pasture.herd = foreignHerd
            try seed.save()
        }

        do {
            try await assembly.transactionExecutor.performWrite(herdID: selectedHerdID) { context in
                let lookup = CoreDataLookup()
                let selectedHerd = try XCTUnwrap(
                    lookup.herd(id: selectedHerdID, in: context)
                )
                let foreignPasture = try XCTUnwrap(
                    lookup.herdOwned(
                        CDPasture.self,
                        id: foreignPastureID,
                        herdID: foreignHerdID,
                        in: context
                    )
                )
                foreignPasture.herd = selectedHerd
                foreignPasture.name = "Stolen Pasture"
            }
            XCTFail("A selected Herd must not take ownership of an existing foreign child.")
        } catch let error as CoreDataPersistenceError {
            guard case let .wrongHerdMutation(entity, herdID) = error else {
                return XCTFail("Expected wrongHerdMutation, got \(error).")
            }
            XCTAssertTrue(
                [CDPasture.coreDataEntityName, CDHerd.coreDataEntityName].contains(entity)
            )
            XCTAssertEqual(herdID, selectedHerdID)
        }

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            let lookup = CoreDataLookup()
            let pasture = try XCTUnwrap(
                lookup.herdOwned(
                    CDPasture.self,
                    id: foreignPastureID,
                    herdID: foreignHerdID,
                    in: read
                )
            )
            XCTAssertEqual(pasture.name, "Original Foreign Pasture")
            XCTAssertEqual(pasture.herd?.id, foreignHerdID)
            XCTAssertNil(try lookup.herdOwned(
                CDPasture.self,
                id: foreignPastureID,
                herdID: selectedHerdID,
                in: read
            ))
        }
    }

    func testHerdQualifiedTransactionRejectsForeignHerdChangesAndRollsBack() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let privateHerdID = UUID()
        let foreignHerdID = UUID()
        let rejectedPastureID = UUID()

        let seedContext = try assembly.contextFactory.makeWriteContext()
        try seedContext.performAndWait {
            _ = Self.makeHerd(
                id: privateHerdID, name: "Private", in: seedContext, store: privateStore
            )
            _ = Self.makeHerd(
                id: foreignHerdID, name: "Foreign", in: seedContext, store: privateStore
            )
            try seedContext.save()
        }

        do {
            try await assembly.transactionExecutor.performWrite(herdID: privateHerdID) { context in
                let foreignHerd = try XCTUnwrap(
                    CoreDataLookup().herd(id: foreignHerdID, in: context)
                )
                foreignHerd.name = "Should Roll Back"
                let pasture = CDPasture(context: context)
                pasture.id = rejectedPastureID
                pasture.name = "Foreign Child"
                pasture.sortOrder = 0
                pasture.herd = foreignHerd
            }
            XCTFail("The write must not commit objects owned by another Herd.")
        } catch let error as CoreDataPersistenceError {
            guard case let .wrongHerdMutation(_, expectedHerdID) = error else {
                return XCTFail("Expected wrongHerdMutation, got \(error).")
            }
            XCTAssertEqual(expectedHerdID, privateHerdID)
        }

        let readContext = assembly.contextFactory.makeReadContext()
        try readContext.performAndWait {
            XCTAssertEqual(
                try CoreDataLookup().herd(id: foreignHerdID, in: readContext)?.name,
                "Foreign"
            )
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self,
                id: rejectedPastureID,
                herdID: foreignHerdID,
                in: readContext
            ))
        }
    }

    func testHerdQualifiedTransactionRejectsAnExplicitForeignStoreAssignment() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-test-shared.sqlite"),
            options: nil
        )
        let sharedURL = try XCTUnwrap(sharedStore.url)
        let privateHerdID = UUID()
        let rejectedPastureID = UUID()

        let seed = try assembly.contextFactory.makeWriteContext()
        try seed.performAndWait {
            _ = Self.makeHerd(
                id: privateHerdID,
                name: "Private",
                in: seed,
                store: privateStore
            )
            try seed.save()
        }

        do {
            try await assembly.transactionExecutor.performWrite(herdID: privateHerdID) { context in
                let herd = try XCTUnwrap(
                    CoreDataLookup().herd(id: privateHerdID, in: context)
                )
                let pasture = CDPasture(context: context)
                pasture.id = rejectedPastureID
                pasture.name = "Wrong Store"
                pasture.sortOrder = 0
                pasture.herd = herd
                let foreignStore = try XCTUnwrap(
                    context.persistentStoreCoordinator?.persistentStores.first {
                        $0.url == sharedURL
                    }
                )
                context.assign(pasture, to: foreignStore)
            }
            XCTFail("Explicitly assigning a private Herd child into the shared store must fail.")
        } catch let error as CoreDataPersistenceError {
            guard case .wrongStoreMutation = error else {
                return XCTFail("Expected wrongStoreMutation, got \(error).")
            }
        }

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self,
                id: rejectedPastureID,
                herdID: privateHerdID,
                in: read
            ))
        }
    }

    func testHerdQualifiedTransactionRejectsRelatedRecordFromAnotherHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let herdAID = UUID()
        let herdBID = UUID()
        let groupBID = UUID()
        let rejectedPastureID = UUID()

        let seed = try assembly.contextFactory.makeWriteContext()
        try seed.performAndWait {
            let herdA = CDHerd(context: seed)
            herdA.id = herdAID
            herdA.name = "Herd A"
            herdA.createdAt = Date(timeIntervalSince1970: 100)
            herdA.updatedAt = Date(timeIntervalSince1970: 100)

            let herdB = CDHerd(context: seed)
            herdB.id = herdBID
            herdB.name = "Herd B"
            herdB.createdAt = Date(timeIntervalSince1970: 100)
            herdB.updatedAt = Date(timeIntervalSince1970: 100)

            let groupB = CDPastureGroup(context: seed)
            groupB.id = groupBID
            groupB.name = "Foreign Group"
            groupB.grazeDays = 0
            groupB.restDays = 0
            groupB.herd = herdB
            try seed.save()
        }

        do {
            try await assembly.transactionExecutor.performWrite(herdID: herdAID) { context in
                let herdA = try XCTUnwrap(CoreDataLookup().herd(id: herdAID, in: context))
                let foreignGroup = try XCTUnwrap(CoreDataLookup().herdOwned(
                    CDPastureGroup.self,
                    id: groupBID,
                    herdID: herdBID,
                    in: context
                ))
                let pasture = CDPasture(context: context)
                pasture.id = rejectedPastureID
                pasture.name = "Invalid Relationship"
                pasture.sortOrder = 0
                pasture.herd = herdA
                pasture.group = foreignGroup
            }
            XCTFail("A selected Herd cannot link to another Herd's group.")
        } catch let error as CoreDataPersistenceError {
            guard case .wrongHerdMutation = error else {
                return XCTFail("Expected wrongHerdMutation, got \(error).")
            }
        }

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self,
                id: rejectedPastureID,
                herdID: herdAID,
                in: read
            ))
            XCTAssertNotNil(try CoreDataLookup().herdOwned(
                CDPastureGroup.self,
                id: groupBID,
                herdID: herdBID,
                in: read
            ))
        }
    }

    func testSelectedHerdDeletePreservesOwnershipThroughCascadingTagRemoval() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = UUID()
        let animalID = UUID()
        let tagID = UUID()
        let seed = try assembly.contextFactory.makeWriteContext()
        try seed.performAndWait {
            let herd = CDHerd(context: seed)
            herd.id = herdID
            herd.name = "Owned Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)

            let animal = CDAnimal(context: seed)
            animal.id = animalID
            animal.herd = herd
            animal.name = "Cow"
            animal.birthDate = Date(timeIntervalSince1970: 100)

            let tag = CDAnimalTag(context: seed)
            tag.id = tagID
            tag.number = "123"
            tag.herd = herd
            tag.animal = animal
            try seed.save()
        }

        try await assembly.transactionExecutor.performWrite(herdID: herdID) { context in
            let animal = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDAnimal.self, id: animalID, herdID: herdID, in: context
            ))
            context.delete(animal)
        }

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDAnimal.self, id: animalID, herdID: herdID, in: read
            ))
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDAnimalTag.self, id: tagID, herdID: herdID, in: read
            ))
        }
    }

    func testDeletingSelectedAnimalRejectsCascadeToForeignHerdTag() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selectedHerdID = UUID()
        let foreignHerdID = UUID()
        let animalID = UUID()
        let foreignTagID = UUID()
        let seed = try assembly.contextFactory.makeWriteContext()
        try seed.performAndWait {
            let selected = CDHerd(context: seed)
            selected.id = selectedHerdID
            selected.name = "Selected"
            selected.createdAt = Date(timeIntervalSince1970: 100)
            selected.updatedAt = Date(timeIntervalSince1970: 100)

            let foreign = CDHerd(context: seed)
            foreign.id = foreignHerdID
            foreign.name = "Foreign"
            foreign.createdAt = Date(timeIntervalSince1970: 100)
            foreign.updatedAt = Date(timeIntervalSince1970: 100)

            let animal = CDAnimal(context: seed)
            animal.id = animalID
            animal.name = "Selected Cow"
            animal.birthDate = Date(timeIntervalSince1970: 100)
            animal.herd = selected

            // Simulate an inconsistent relationship imported before the
            // associated Herd records have finished reconciling.
            let tag = CDAnimalTag(context: seed)
            tag.id = foreignTagID
            tag.number = "Foreign Tag"
            tag.herd = foreign
            tag.animal = animal
            try seed.save()
        }

        do {
            try await assembly.transactionExecutor.performWrite(herdID: selectedHerdID) { context in
                let animal = try XCTUnwrap(CoreDataLookup().herdOwned(
                    CDAnimal.self, id: animalID, herdID: selectedHerdID, in: context
                ))
                context.delete(animal)
            }
            XCTFail("Deleting a selected Animal must not cascade-delete a foreign Herd's tag.")
        } catch let error as CoreDataPersistenceError {
            guard case .wrongHerdMutation = error else {
                return XCTFail("Expected wrongHerdMutation, got \(error).")
            }
        }

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            XCTAssertNotNil(try CoreDataLookup().herdOwned(
                CDAnimal.self, id: animalID, herdID: selectedHerdID, in: read
            ))
            XCTAssertNotNil(try CoreDataLookup().herdOwned(
                CDAnimalTag.self, id: foreignTagID, herdID: foreignHerdID, in: read
            ))
        }
    }

    func testSelectedHerdDeleteStillRejectsForeignOwnedRecord() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selectedHerdID = UUID()
        let foreignHerdID = UUID()
        let foreignPastureID = UUID()
        let seed = try assembly.contextFactory.makeWriteContext()
        try seed.performAndWait {
            let selected = CDHerd(context: seed)
            selected.id = selectedHerdID
            selected.name = "Selected"
            selected.createdAt = Date(timeIntervalSince1970: 100)
            selected.updatedAt = Date(timeIntervalSince1970: 100)

            let foreign = CDHerd(context: seed)
            foreign.id = foreignHerdID
            foreign.name = "Foreign"
            foreign.createdAt = Date(timeIntervalSince1970: 100)
            foreign.updatedAt = Date(timeIntervalSince1970: 100)

            let pasture = CDPasture(context: seed)
            pasture.id = foreignPastureID
            pasture.name = "Foreign Pasture"
            pasture.herd = foreign
            try seed.save()
        }

        do {
            try await assembly.transactionExecutor.performWrite(herdID: selectedHerdID) { context in
                let pasture = try XCTUnwrap(CoreDataLookup().herdOwned(
                    CDPasture.self, id: foreignPastureID, herdID: foreignHerdID, in: context
                ))
                context.delete(pasture)
            }
            XCTFail("Deleting a foreign Herd's record must be rejected.")
        } catch let error as CoreDataPersistenceError {
            guard case .wrongHerdMutation = error else {
                return XCTFail("Expected wrongHerdMutation, got \(error).")
            }
        }

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            XCTAssertNotNil(try CoreDataLookup().herdOwned(
                CDPasture.self, id: foreignPastureID, herdID: foreignHerdID, in: read
            ))
        }
    }

    func testHerdQualifiedTransactionRefusesUnknownHerdWithoutPersistingInsert() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let unknownHerdID = UUID()
        let rejectedHerdID = UUID()

        do {
            try await assembly.transactionExecutor.performWrite(herdID: unknownHerdID) { context in
                let herd = CDHerd(context: context)
                herd.id = rejectedHerdID
                herd.name = "Unscoped Root"
                herd.createdAt = Date(timeIntervalSince1970: 100)
                herd.updatedAt = Date(timeIntervalSince1970: 100)
            }
            XCTFail("An unknown selected Herd must prevent committing a new root.")
        } catch {
            XCTAssertTrue(error is HerdRepositoryError)
        }

        let readContext = assembly.contextFactory.makeReadContext()
        try readContext.performAndWait {
            XCTAssertNil(try CoreDataLookup().herd(id: rejectedHerdID, in: readContext))
        }
    }

    @MainActor
    func testFieldCheckSessionReadsUseOwningStoreWithCollidingApplicationIDs() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-test-shared.sqlite"),
            options: nil
        )
        let privateHerdID = UUID()
        let sharedHerdID = UUID()
        let sessionID = UUID()

        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let privateHerd = Self.makeHerd(
                id: privateHerdID, name: "Private", in: writer, store: privateStore
            )
            let sharedHerd = Self.makeHerd(
                id: sharedHerdID, name: "Shared", in: writer, store: sharedStore
            )
            let privateSession = CDFieldCheckSession(context: writer)
            privateSession.id = sessionID
            privateSession.herd = privateHerd
            privateSession.startedAt = Date(timeIntervalSince1970: 100)
            privateSession.notes = "Private field check"
            privateSession.pastureNameSnapshot = "Private pasture"
            writer.assign(privateSession, to: privateStore)

            let sharedSession = CDFieldCheckSession(context: writer)
            sharedSession.id = sessionID
            sharedSession.herd = sharedHerd
            sharedSession.startedAt = Date(timeIntervalSince1970: 200)
            sharedSession.notes = "Shared field check"
            sharedSession.pastureNameSnapshot = "Shared pasture"
            writer.assign(sharedSession, to: sharedStore)
            try writer.save()
        }

        let privateRepository = CoreDataFieldCheckRepository(
            selection: AppCurrentHerdSelection(currentHerdID: privateHerdID),
            assembly: assembly
        )
        let sharedRepository = CoreDataFieldCheckRepository(
            selection: AppCurrentHerdSelection(currentHerdID: sharedHerdID),
            assembly: assembly
        )

        XCTAssertEqual(try privateRepository.fetchSessions().map(\.id), [sessionID])
        XCTAssertEqual(try sharedRepository.fetchSessions().map(\.id), [sessionID])
        XCTAssertEqual(
            try privateRepository.fetchSessionDetail(id: sessionID)?.notes,
            "Private field check"
        )
        XCTAssertEqual(
            try sharedRepository.fetchSessionDetail(id: sessionID)?.notes,
            "Shared field check"
        )
    }

    @MainActor
    func testReferenceCatalogsReadFromOnlyTheSelectedHerdStore() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-reference-shared.sqlite"),
            options: nil
        )
        let privateHerdID = UUID()
        let sharedHerdID = UUID()
        let statusID = UUID()
        let colorID = UUID()
        let templateID = UUID()

        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let privateHerd = Self.makeHerd(
                id: privateHerdID, name: "Private", in: writer, store: privateStore
            )
            let sharedHerd = Self.makeHerd(
                id: sharedHerdID, name: "Shared", in: writer, store: sharedStore
            )
            for (herd, store, suffix) in [
                (privateHerd, privateStore, "Private"),
                (sharedHerd, sharedStore, "Shared")
            ] {
                let status = CDAnimalStatusReference(context: writer)
                status.id = statusID
                status.name = "\(suffix) status"
                status.baseStatusRawValue = AnimalStatus.active.rawValue
                status.herd = herd
                writer.assign(status, to: store)

                let color = CDTagColorDefinition(context: writer)
                color.id = colorID
                color.name = "\(suffix) color"
                color.prefix = suffix
                color.red = 0.4
                color.green = 0.3
                color.blue = 0.2
                color.alpha = 1
                color.createdAt = Date(timeIntervalSince1970: 100)
                color.updatedAt = Date(timeIntervalSince1970: 100)
                color.herd = herd
                writer.assign(color, to: store)

                let template = CDWorkingTreatmentTemplate(context: writer)
                template.id = templateID
                template.name = "\(suffix) treatment"
                template.itemsData = Data("[]".utf8)
                template.herd = herd
                writer.assign(template, to: store)
            }
            try writer.save()
        }

        for (herdID, label, expectedStore) in [
            (privateHerdID, "Private", privateStore),
            (sharedHerdID, "Shared", sharedStore)
        ] {
            let selection = AppCurrentHerdSelection(currentHerdID: herdID)
            let statusRepository = CoreDataAnimalStatusReferenceRepository(
                selection: selection, assembly: assembly
            )
            let colorRepository = CoreDataTagColorRepository(
                selection: selection, assembly: assembly
            )
            let templateRepository = CoreDataWorkingTreatmentTemplateRepository(
                selection: selection, assembly: assembly
            )

            let statuses = try statusRepository.fetchStatusReferenceOptions()
            XCTAssertEqual(statuses.map(\.id), [statusID])
            XCTAssertEqual(statuses.map(\.name), ["\(label) status"])
            XCTAssertEqual(try colorRepository.fetchColor(id: colorID)?.name, "\(label) color")
            let allColors = try colorRepository.fetchColors()
            XCTAssertEqual(allColors.filter { $0.id == colorID }.map(\.name), [
                "\(label) color"
            ])
            XCTAssertEqual(try templateRepository.fetchTemplates().map(\.name), [
                "\(label) treatment"
            ])
            XCTAssertEqual(
                try templateRepository.fetchTemplateDetail(id: templateID)?.name,
                "\(label) treatment"
            )

            let read = assembly.contextFactory.makeReadContext()
            try read.performAndWait {
                let persisted = try XCTUnwrap(CoreDataLookup().herdOwned(
                    CDTagColorDefinition.self, id: colorID, herdID: herdID, in: read
                ))
                XCTAssertTrue(persisted.objectID.persistentStore === expectedStore)
            }
        }
    }


    @MainActor
    func testSampleSeedKeepsPrivateHerdIntactWhenSeedingSharedStore() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first)
        let sharedStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: harness.directoryURL.appendingPathComponent("yaHerd-seed-shared.sqlite"),
            options: nil
        )
        let privateHerdID = UUID()
        let sharedHerdID = UUID()
        let privatePastureID = UUID()

        let initial = try assembly.contextFactory.makeWriteContext()
        try initial.performAndWait {
            let privateHerd = Self.makeHerd(
                id: privateHerdID, name: "Private", in: initial, store: privateStore
            )
            _ = Self.makeHerd(
                id: sharedHerdID, name: "Shared", in: initial, store: sharedStore
            )
            Self.makePasture(
                id: privatePastureID, name: "Keep private pasture", herd: privateHerd,
                in: initial, store: privateStore
            )
            try initial.save()
        }

        let preflight = assembly.contextFactory.makeReadContext()
        try preflight.performAndWait {
            let lookup = CoreDataLookup()
            let privateHerd = try XCTUnwrap(lookup.herd(id: privateHerdID, in: preflight))
            let sharedHerd = try XCTUnwrap(lookup.herd(id: sharedHerdID, in: preflight))
            XCTAssertFalse(try CoreDataSampleHerdFactory.isEmpty(herd: privateHerd, in: preflight))
            XCTAssertTrue(try CoreDataSampleHerdFactory.isEmpty(herd: sharedHerd, in: preflight))
        }

        let inserted = try await assembly.transactionExecutor.performWrite(
            herdID: sharedHerdID
        ) { context in
            let herd = try XCTUnwrap(CoreDataLookup().herd(id: sharedHerdID, in: context))
            return try CoreDataSampleHerdFactory.insert(
                size: .compact, herd: herd, in: context
            )
        }
        XCTAssertTrue(inserted)

        let verification = assembly.contextFactory.makeReadContext()
        try verification.performAndWait {
            let lookup = CoreDataLookup()
            let privatePasture = try XCTUnwrap(lookup.herdOwned(
                CDPasture.self,
                id: privatePastureID,
                herdID: privateHerdID,
                in: verification
            ))
            XCTAssertTrue(privatePasture.objectID.persistentStore === privateStore)
            XCTAssertEqual(privatePasture.name, "Keep private pasture")

            let sharedAnimals = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            sharedAnimals.affectedStores = [sharedStore]
            sharedAnimals.predicate = NSPredicate(
                format: "herd.id == %@", sharedHerdID as NSUUID
            )
            XCTAssertEqual(
                try verification.count(for: sharedAnimals),
                CoreDataSampleHerdFactory.Size.compact.animalCount
            )

            let privateAnimals = NSFetchRequest<CDAnimal>(
                entityName: CDAnimal.coreDataEntityName
            )
            privateAnimals.affectedStores = [privateStore]
            XCTAssertEqual(try verification.count(for: privateAnimals), 0)
        }
    }

    func testTwoStoreUnscopedTransactionsCannotCreateAnAmbiguousHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        let attemptedHerdID = UUID()

        // The old one-store transaction entry point must not pick an arbitrary
        // private/shared destination when no owning Herd has been supplied.
        do {
            try await assembly.transactionExecutor.performWrite { context in
                let herd = CDHerd(context: context)
                herd.id = attemptedHerdID
                herd.name = "Unscoped Herd"
                herd.createdAt = Date(timeIntervalSince1970: 100)
                herd.updatedAt = Date(timeIntervalSince1970: 100)
            }
            XCTFail("An unscoped transaction must not write through a two-store container.")
        } catch let error as CoreDataPersistenceError {
            XCTAssertEqual(error, .unscopedMultiStoreWrite)
        }

        // Until the multi-Herd lifecycle is implemented, legacy single-Herd
        // bootstrap must also refuse to invent a root in either CloudKit scope.
        do {
            _ = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
                assembly: assembly
            )
            XCTFail("Legacy bootstrap must not choose a store for a new Herd.")
        } catch let error as CoreDataPersistenceError {
            XCTAssertEqual(error, .unscopedMultiStoreWrite)
        }

        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            XCTAssertEqual(try read.count(for: request), 0)
            XCTAssertNil(try CoreDataLookup().herd(id: attemptedHerdID, in: read))
        }
    }


    func testDashboardRejectsMissingImportedWorkingSessionIDOnlyInOwningStore() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: harness.storeURL,
            mirroringEnabled: false
        )
        let coordinator = try XCTUnwrap(
            assembly.contextFactory.makeReadContext().persistentStoreCoordinator
        )
        let privateStore = try XCTUnwrap(coordinator.persistentStores.first {
            $0.url == harness.storeURL
        })
        let sharedStoreURL = harness.directoryURL.appendingPathComponent(
            CoreDataPersistentContainer.sharedStoreFileName
        )
        let sharedStore = try XCTUnwrap(coordinator.persistentStores.first {
            $0.url == sharedStoreURL
        })
        let privateHerdID = UUID()
        let sharedHerdID = UUID()

        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            _ = Self.makeHerd(
                id: privateHerdID, name: "Private Herd", in: writer, store: privateStore
            )
            let sharedHerd = Self.makeHerd(
                id: sharedHerdID, name: "Shared Herd", in: writer, store: sharedStore
            )
            // A remotely imported finished session is outside the Dashboard's
            // active-session page. Its missing UUID must still be reported.
            let incomplete = CDWorkingSession(context: writer)
            incomplete.id = nil
            incomplete.herd = sharedHerd
            incomplete.date = Date(timeIntervalSince1970: 200)
            incomplete.statusRawValue = WorkingSessionStatus.finished.rawValue
            incomplete.treatmentTemplateNameSnapshot = "Imported Session"
            writer.assign(incomplete, to: sharedStore)
            try writer.save()
        }

        let privateReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { privateHerdID }
        )
        let sharedReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { sharedHerdID }
        )

        let privateDashboard = try await privateReader.fetchDashboardRecords()
        XCTAssertTrue(privateDashboard.workingSessions.isEmpty)

        do {
            _ = try await sharedReader.fetchDashboardRecords()
            XCTFail("A selected Herd must reject an imported session without its UUID.")
        } catch let error as CoreDataPersistenceError {
            XCTAssertEqual(
                error,
                .missingApplicationID(entity: CDWorkingSession.coreDataEntityName)
            )
        }

        // Restoring the imported UUID must restore normal reads without
        // altering the private Herd or recreating the shared session.
        let restoredID = UUID()
        try writer.performAndWait {
            let request = NSFetchRequest<CDWorkingSession>(
                entityName: CDWorkingSession.coreDataEntityName
            )
            request.affectedStores = [sharedStore]
            request.predicate = NSPredicate(
                format: "herd.id == %@ AND id == nil",
                sharedHerdID as NSUUID
            )
            let incomplete = try XCTUnwrap(writer.fetch(request).first)
            incomplete.id = restoredID
            try writer.save()
        }
        let restoredSharedDashboard = try await sharedReader.fetchDashboardRecords()
        XCTAssertTrue(restoredSharedDashboard.workingSessions.isEmpty)
        let restoredPrivateDashboard = try await privateReader.fetchDashboardRecords()
        XCTAssertTrue(restoredPrivateDashboard.workingSessions.isEmpty)
        let read = assembly.contextFactory.makeReadContext()
        try read.performAndWait {
            let sharedHerd = try XCTUnwrap(
                CoreDataLookup().herd(id: sharedHerdID, in: read)
            )
            let request = NSFetchRequest<CDWorkingSession>(
                entityName: CDWorkingSession.coreDataEntityName
            )
            request.affectedStores = [sharedStore]
            request.predicate = NSPredicate(format: "herd == %@", sharedHerd)
            XCTAssertEqual(try read.fetch(request).map(\.id), [restoredID])
        }
    }

    @discardableResult
    private static func makeHerd(
        id: UUID,
        name: String,
        in context: NSManagedObjectContext,
        store: NSPersistentStore
    ) -> CDHerd {
        let herd = CDHerd(context: context)
        herd.id = id
        herd.name = name
        herd.createdAt = Date(timeIntervalSince1970: 100)
        herd.updatedAt = Date(timeIntervalSince1970: 100)
        context.assign(herd, to: store)
        return herd
    }

    private static func makePasture(
        id: UUID,
        name: String,
        herd: CDHerd,
        in context: NSManagedObjectContext,
        store: NSPersistentStore
    ) {
        let pasture = CDPasture(context: context)
        pasture.id = id
        pasture.name = name
        pasture.sortOrder = 0
        pasture.herd = herd
        context.assign(pasture, to: store)
    }
}
