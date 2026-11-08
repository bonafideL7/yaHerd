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
            let privateHerd = makeHerd(
                id: privateHerdID, name: "Owned Herd", in: writer, store: privateStore
            )
            let sharedHerd = makeHerd(
                id: sharedHerdID, name: "Shared Herd", in: writer, store: sharedStore
            )
            makePasture(id: pastureID, name: "Owned Pasture", herd: privateHerd,
                        in: writer, store: privateStore)
            makePasture(id: pastureID, name: "Shared Pasture", herd: sharedHerd,
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
        }
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
            _ = makeHerd(id: herdID, name: "First", in: writer, store: privateStore)
            _ = makeHerd(id: herdID, name: "Second", in: writer, store: sharedStore)
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

    @discardableResult
    private func makeHerd(
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

    private func makePasture(
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
