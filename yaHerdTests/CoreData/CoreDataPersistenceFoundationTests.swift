@preconcurrency import CoreData
import XCTest
@testable import yaHerd

final class CoreDataPersistenceFoundationTests: XCTestCase {
    private enum ProbeError: Error {
        case injectedFailure
    }

    func testSQLiteStoreSavesAndReloadsApplicationIdentityInFreshContext() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let herdID = UUID()
        let pastureID = UUID()

        try await assembly.transactionExecutor.performWrite { context in
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Foundation Herd"
            herd.createdAt = Date(timeIntervalSince1970: 100)
            herd.updatedAt = Date(timeIntervalSince1970: 100)

            let pasture = CDPasture(context: context)
            pasture.id = pastureID
            pasture.name = "Foundation Pasture"
            pasture.sortOrder = 0
            pasture.herd = herd
        }

        let readContext = assembly.contextFactory.makeReadContext()
        try readContext.performAndWait {
            let herd = try XCTUnwrap(
                assembly.lookup.herd(id: herdID, in: readContext)
            )
            XCTAssertEqual(herd.id, herdID)

            let pasture = try XCTUnwrap(
                assembly.lookup.herdOwned(
                    CDPasture.self,
                    id: pastureID,
                    herdID: herdID,
                    in: readContext
                )
            )
            XCTAssertEqual(pasture.id, pastureID)
            XCTAssertEqual(pasture.herd.id, herdID)
            XCTAssertEqual(pasture.name, "Foundation Pasture")
        }
    }

    func testStoreLoadFailureSurfacesPersistenceErrorWithoutFallback() async throws {
        let harness = try CoreDataPersistenceHarness()

        do {
            _ = try await CoreDataPersistenceAssembly.load(
                storeURL: harness.directoryURL
            )
            XCTFail("Loading SQLite at a directory URL must fail.")
        } catch let error as CoreDataPersistenceError {
            guard case .storeLoadFailed = error else {
                XCTFail("Expected storeLoadFailed, received \(error).")
                return
            }
        } catch {
            XCTFail("Expected CoreDataPersistenceError, received \(type(of: error)).")
        }
    }

    func testHerdLookupRejectsStoreGlobalDuplicateApplicationID() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let duplicateHerdID = UUID()

        try await assembly.transactionExecutor.performWrite { context in
            _ = Self.makeHerd(id: duplicateHerdID, name: "Duplicate Herd A", in: context)
            _ = Self.makeHerd(id: duplicateHerdID, name: "Duplicate Herd B", in: context)
        }

        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertThrowsError(
                try CoreDataLookup().herd(id: duplicateHerdID, in: context)
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataPersistenceError,
                    .duplicateApplicationID(
                        entity: CDHerd.coreDataEntityName,
                        id: duplicateHerdID,
                        herdID: nil
                    )
                )
            }
        }
    }

    func testHerdOwnedLookupScopesSameApplicationUUIDByHerd() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdAID = UUID()
        let herdBID = UUID()
        let sharedPastureID = UUID()

        try await assembly.transactionExecutor.performWrite { context in
            let herdA = Self.makeHerd(id: herdAID, name: "Herd A", in: context)
            let herdB = Self.makeHerd(id: herdBID, name: "Herd B", in: context)

            let pastureA = CDPasture(context: context)
            pastureA.id = sharedPastureID
            pastureA.name = "A Pasture"
            pastureA.sortOrder = 0
            pastureA.herd = herdA

            let pastureB = CDPasture(context: context)
            pastureB.id = sharedPastureID
            pastureB.name = "B Pasture"
            pastureB.sortOrder = 0
            pastureB.herd = herdB
        }

        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let pastureA = try XCTUnwrap(
                assembly.lookup.herdOwned(
                    CDPasture.self,
                    id: sharedPastureID,
                    herdID: herdAID,
                    in: context
                )
            )
            let pastureB = try XCTUnwrap(
                assembly.lookup.herdOwned(
                    CDPasture.self,
                    id: sharedPastureID,
                    herdID: herdBID,
                    in: context
                )
            )

            XCTAssertEqual(pastureA.name, "A Pasture")
            XCTAssertEqual(pastureA.herd.id, herdAID)
            XCTAssertEqual(pastureB.name, "B Pasture")
            XCTAssertEqual(pastureB.herd.id, herdBID)
        }
    }

    func testHerdOwnedLookupRejectsDuplicateStoreGlobalHerdRoot() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let duplicateHerdID = UUID()
        let pastureID = UUID()

        try await assembly.transactionExecutor.performWrite { context in
            let herdA = Self.makeHerd(
                id: duplicateHerdID,
                name: "Duplicate Root A",
                in: context
            )
            _ = Self.makeHerd(
                id: duplicateHerdID,
                name: "Duplicate Root B",
                in: context
            )

            let pasture = CDPasture(context: context)
            pasture.id = pastureID
            pasture.name = "Only Child"
            pasture.sortOrder = 0
            pasture.herd = herdA
        }

        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertThrowsError(
                try CoreDataLookup().herdOwned(
                    CDPasture.self,
                    id: pastureID,
                    herdID: duplicateHerdID,
                    in: context
                )
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataPersistenceError,
                    .duplicateApplicationID(
                        entity: CDHerd.coreDataEntityName,
                        id: duplicateHerdID,
                        herdID: nil
                    )
                )
            }
        }
    }

    func testLookupRejectsDuplicateApplicationIDInsideOneHerdScope() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = UUID()
        let duplicatePastureID = UUID()

        try await assembly.transactionExecutor.performWrite { context in
            let herd = Self.makeHerd(id: herdID, name: "Duplicate Herd", in: context)

            for name in ["Duplicate A", "Duplicate B"] {
                let pasture = CDPasture(context: context)
                pasture.id = duplicatePastureID
                pasture.name = name
                pasture.sortOrder = 0
                pasture.herd = herd
            }
        }

        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertThrowsError(
                try assembly.lookup.herdOwned(
                    CDPasture.self,
                    id: duplicatePastureID,
                    herdID: herdID,
                    in: context
                )
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataPersistenceError,
                    .duplicateApplicationID(
                        entity: CDPasture.coreDataEntityName,
                        id: duplicatePastureID,
                        herdID: herdID
                    )
                )
            }
        }
    }

    func testFailedTransactionRollsBackAllStagedChangesAndPreservesControlState() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = UUID()
        let failedPastureID = UUID()

        try await assembly.transactionExecutor.performWrite { context in
            _ = Self.makeHerd(id: herdID, name: "Control Herd", in: context)
        }

        do {
            try await assembly.transactionExecutor.performWrite { context in
                let herd = try XCTUnwrap(
                    CoreDataLookup().herd(id: herdID, in: context)
                )
                let pasture = CDPasture(context: context)
                pasture.id = failedPastureID
                pasture.name = "Must Roll Back"
                pasture.sortOrder = 0
                pasture.herd = herd

                throw ProbeError.injectedFailure
            }
            XCTFail("The injected transaction failure must propagate.")
        } catch {
            XCTAssertTrue(error is ProbeError)
        }

        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertNotNil(try assembly.lookup.herd(id: herdID, in: context))
            XCTAssertNil(
                try assembly.lookup.herdOwned(
                    CDPasture.self,
                    id: failedPastureID,
                    herdID: herdID,
                    in: context
                )
            )
        }
    }

    func testSaveFailureRollsBackStagedState() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let invalidHerdID = UUID()

        do {
            try await assembly.transactionExecutor.performWrite { context in
                let invalidHerd = CDHerd(context: context)
                invalidHerd.id = invalidHerdID
                invalidHerd.createdAt = Date(timeIntervalSince1970: 100)
                invalidHerd.updatedAt = Date(timeIntervalSince1970: 100)
                // Required name intentionally left unset to force Core Data validation failure.
            }
            XCTFail("Saving an invalid required persisted value must fail.")
        } catch let error as CoreDataPersistenceError {
            guard case .saveFailed = error else {
                XCTFail("Expected saveFailed, received \(error).")
                return
            }
        }

        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertNil(
                try CoreDataLookup().herd(id: invalidHerdID, in: context),
                "A failed save must not leave the invalid Herd durable."
            )
        }
    }

    func testReadOnlyStoreUsesSameStoreAndRejectsTransactions() async throws {
        let harness = try CoreDataPersistenceHarness()
        let writer = try await harness.makeAssembly()
        let herdID = UUID()

        try await writer.transactionExecutor.performWrite { context in
            _ = Self.makeHerd(id: herdID, name: "Read Only Herd", in: context)
        }

        let readOnly = try await harness.makeAssembly(accessMode: .readOnly)
        let readContext = readOnly.contextFactory.makeReadContext()

        try readContext.performAndWait {
            XCTAssertEqual(
                try readOnly.lookup.herd(id: herdID, in: readContext)?.name,
                "Read Only Herd"
            )
        }

        do {
            try await readOnly.transactionExecutor.performWrite { _ in
                XCTFail("A read-only transaction must be rejected before its mutation block executes.")
            }
            XCTFail("A read-only store must reject write transactions.")
        } catch {
            XCTAssertEqual(error as? CoreDataPersistenceError, .readOnlyStore)
        }
    }

    func testContextFactoryUsesPrivateQueueContextsAndOneCoordinator() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let readContext = assembly.contextFactory.makeReadContext()
        let writeContext = try assembly.contextFactory.makeWriteContext()

        XCTAssertEqual(readContext.concurrencyType, .privateQueueConcurrencyType)
        XCTAssertEqual(writeContext.concurrencyType, .privateQueueConcurrencyType)
        XCTAssertTrue(
            readContext.persistentStoreCoordinator
                === writeContext.persistentStoreCoordinator
        )
        XCTAssertEqual(
            (readContext.mergePolicy as? NSMergePolicy)?.mergeType,
            .errorMergePolicyType
        )
        XCTAssertEqual(
            (writeContext.mergePolicy as? NSMergePolicy)?.mergeType,
            .errorMergePolicyType
        )
    }

    func testUnsavedStateDoesNotLeakAcrossSiblingContexts() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let unsavedHerdID = UUID()
        let writeContext = try assembly.contextFactory.makeWriteContext()

        writeContext.performAndWait {
            _ = Self.makeHerd(
                id: unsavedHerdID,
                name: "Unsaved Herd",
                in: writeContext
            )
        }

        let readContext = assembly.contextFactory.makeReadContext()
        try readContext.performAndWait {
            XCTAssertNil(
                try CoreDataLookup().herd(id: unsavedHerdID, in: readContext),
                "A sibling context must not observe another context's unsaved inserts."
            )
        }

        writeContext.performAndWait {
            writeContext.rollback()
        }
    }

    private static func makeHerd(
        id: UUID,
        name: String,
        in context: NSManagedObjectContext
    ) -> CDHerd {
        let herd = CDHerd(context: context)
        herd.id = id
        herd.name = name
        herd.createdAt = Date(timeIntervalSince1970: 100)
        herd.updatedAt = Date(timeIntervalSince1970: 100)
        return herd
    }
}
