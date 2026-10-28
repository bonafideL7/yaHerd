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

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let readContext = reopened.contextFactory.makeReadContext()
        try readContext.performAndWait {
            let herd = try XCTUnwrap(
                CoreDataLookup().herd(id: herdID, in: readContext)
            )
            XCTAssertEqual(herd.id, herdID)

            let pasture = try XCTUnwrap(
                CoreDataLookup().herdOwned(
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
                CoreDataLookup().herdOwned(
                    CDPasture.self,
                    id: sharedPastureID,
                    herdID: herdAID,
                    in: context
                )
            )
            let pastureB = try XCTUnwrap(
                CoreDataLookup().herdOwned(
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
                try CoreDataLookup().herdOwned(
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

    func testSQLiteReopenRejectsDuplicateHerdIDForRootAndOwnedLookups() async throws {
        let harness = try CoreDataPersistenceHarness()
        let writer = try await harness.makeAssembly()
        let duplicateHerdID = UUID()
        let controlHerdID = UUID()
        let pastureID = UUID()

        try await writer.transactionExecutor.performWrite { context in
            let first = Self.makeHerd(
                id: duplicateHerdID, name: "First Root", in: context
            )
            _ = Self.makeHerd(
                id: duplicateHerdID, name: "Second Root", in: context
            )
            _ = Self.makeHerd(
                id: controlHerdID, name: "Unaffected Root", in: context
            )
            _ = Self.makePasture(
                id: pastureID, name: "First Root Pasture", herd: first, in: context
            )
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let context = reopened.contextFactory.makeReadContext()
        try context.performAndWait {
            let expectedError = CoreDataPersistenceError.duplicateApplicationID(
                entity: CDHerd.coreDataEntityName,
                id: duplicateHerdID,
                herdID: nil
            )
            XCTAssertThrowsError(
                try CoreDataLookup().herd(id: duplicateHerdID, in: context)
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }
            XCTAssertThrowsError(
                try CoreDataLookup().herdOwned(
                    CDPasture.self,
                    id: pastureID,
                    herdID: duplicateHerdID,
                    in: context
                )
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }

            XCTAssertEqual(
                try CoreDataLookup().herd(id: controlHerdID, in: context)?.name,
                "Unaffected Root"
            )
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self,
                id: pastureID,
                herdID: controlHerdID,
                in: context
            ))
        }
    }

    func testSQLiteReopenScopesIdenticalPastureIDsToDistinctHerds() async throws {
        let harness = try CoreDataPersistenceHarness()
        let writer = try await harness.makeAssembly()
        let herdAID = UUID()
        let herdBID = UUID()
        let sharedPastureID = UUID()

        try await writer.transactionExecutor.performWrite { context in
            let herdA = Self.makeHerd(id: herdAID, name: "Herd A", in: context)
            let herdB = Self.makeHerd(id: herdBID, name: "Herd B", in: context)
            _ = Self.makePasture(
                id: sharedPastureID, name: "A Pasture", herd: herdA, in: context
            )
            _ = Self.makePasture(
                id: sharedPastureID, name: "B Pasture", herd: herdB, in: context
            )
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let context = reopened.contextFactory.makeReadContext()
        try context.performAndWait {
            let pastureA = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self,
                id: sharedPastureID,
                herdID: herdAID,
                in: context
            ))
            let pastureB = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self,
                id: sharedPastureID,
                herdID: herdBID,
                in: context
            ))

            XCTAssertEqual(pastureA.id, sharedPastureID)
            XCTAssertEqual(pastureA.herd.id, herdAID)
            XCTAssertEqual(pastureA.name, "A Pasture")
            XCTAssertEqual(pastureB.id, sharedPastureID)
            XCTAssertEqual(pastureB.herd.id, herdBID)
            XCTAssertEqual(pastureB.name, "B Pasture")
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self,
                id: UUID(),
                herdID: herdAID,
                in: context
            ))
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self,
                id: sharedPastureID,
                herdID: UUID(),
                in: context
            ))
        }
    }

    func testSQLiteReopenRejectsSameHerdDuplicateWithoutHidingOtherHerd() async throws {
        let harness = try CoreDataPersistenceHarness()
        let writer = try await harness.makeAssembly()
        let duplicateHerdID = UUID()
        let controlHerdID = UUID()
        let sharedPastureID = UUID()

        try await writer.transactionExecutor.performWrite { context in
            let duplicateHerd = Self.makeHerd(
                id: duplicateHerdID, name: "Duplicate Child Herd", in: context
            )
            let controlHerd = Self.makeHerd(
                id: controlHerdID, name: "Control Herd", in: context
            )
            for name in ["First Pasture", "Second Pasture"] {
                _ = Self.makePasture(
                    id: sharedPastureID,
                    name: name,
                    herd: duplicateHerd,
                    in: context
                )
            }
            _ = Self.makePasture(
                id: sharedPastureID, name: "Control Pasture", herd: controlHerd,
                in: context
            )
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let context = reopened.contextFactory.makeReadContext()
        try context.performAndWait {
            XCTAssertThrowsError(
                try CoreDataLookup().herdOwned(
                    CDPasture.self,
                    id: sharedPastureID,
                    herdID: duplicateHerdID,
                    in: context
                )
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataPersistenceError,
                    .duplicateApplicationID(
                        entity: CDPasture.coreDataEntityName,
                        id: sharedPastureID,
                        herdID: duplicateHerdID
                    )
                )
            }

            let control = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self,
                id: sharedPastureID,
                herdID: controlHerdID,
                in: context
            ))
            XCTAssertEqual(control.id, sharedPastureID)
            XCTAssertEqual(control.herd.id, controlHerdID)
            XCTAssertEqual(control.name, "Control Pasture")
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
            XCTAssertNotNil(try CoreDataLookup().herd(id: herdID, in: context))
            XCTAssertNil(
                try CoreDataLookup().herdOwned(
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

    func testSQLiteReopenRollsBackStagedUpdateDeleteAndInsertWhenOperationThrows() async throws {
        let harness = try CoreDataPersistenceHarness()
        let writer = try await harness.makeAssembly()
        let lookup = CoreDataLookup()
        let herdID = UUID()
        let removedPastureID = UUID()
        let controlPastureID = UUID()
        let rejectedPastureID = UUID()
        let originalUpdatedAt = Date(timeIntervalSince1970: 100)

        try await writer.transactionExecutor.performWrite { context in
            let herd = Self.makeHerd(id: herdID, name: "Original Herd", in: context)
            _ = Self.makePasture(
                id: removedPastureID, name: "Original Pasture", herd: herd, in: context
            )
            _ = Self.makePasture(
                id: controlPastureID, name: "Control Pasture", herd: herd, in: context
            )
        }

        do {
            try await writer.transactionExecutor.performWrite { context in
                let herd = try XCTUnwrap(lookup.herd(id: herdID, in: context))
                let pasture = try XCTUnwrap(lookup.herdOwned(
                    CDPasture.self, id: removedPastureID, herdID: herdID, in: context
                ))
                herd.name = "Uncommitted Herd"
                herd.updatedAt = Date(timeIntervalSince1970: 200)
                context.delete(pasture)
                _ = Self.makePasture(
                    id: rejectedPastureID,
                    name: "Uncommitted Pasture",
                    herd: herd,
                    in: context
                )
                throw ProbeError.injectedFailure
            }
            XCTFail("The post-staging error must propagate.")
        } catch {
            XCTAssertTrue(error is ProbeError)
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let context = reopened.contextFactory.makeReadContext()
        try context.performAndWait {
            let herd = try XCTUnwrap(CoreDataLookup().herd(id: herdID, in: context))
            XCTAssertEqual(herd.name, "Original Herd")
            XCTAssertEqual(herd.createdAt, originalUpdatedAt)
            XCTAssertEqual(herd.updatedAt, originalUpdatedAt)

            let original = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: removedPastureID, herdID: herdID, in: context
            ))
            XCTAssertEqual(original.name, "Original Pasture")
            XCTAssertEqual(original.herd.id, herdID)
            let control = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: controlPastureID, herdID: herdID, in: context
            ))
            XCTAssertEqual(control.name, "Control Pasture")
            XCTAssertEqual(control.herd.id, herdID)
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self, id: rejectedPastureID, herdID: herdID, in: context
            ))
        }
    }

    func testSQLiteReopenRollsBackMixedActualSaveFailureAndAllowsNextCommit() async throws {
        let harness = try CoreDataPersistenceHarness()
        let writer = try await harness.makeAssembly()
        let lookup = CoreDataLookup()
        let herdID = UUID()
        let pastureID = UUID()
        let controlPastureID = UUID()
        let rejectedPastureID = UUID()
        let invalidHerdID = UUID()
        let committedPastureID = UUID()
        let originalUpdatedAt = Date(timeIntervalSince1970: 100)
        let committedUpdatedAt = Date(timeIntervalSince1970: 300)

        try await writer.transactionExecutor.performWrite { context in
            let herd = Self.makeHerd(id: herdID, name: "Stable Herd", in: context)
            _ = Self.makePasture(
                id: pastureID, name: "Stable Pasture", herd: herd, in: context
            )
            _ = Self.makePasture(
                id: controlPastureID, name: "Control Pasture", herd: herd, in: context
            )
        }

        do {
            try await writer.transactionExecutor.performWrite { context in
                let herd = try XCTUnwrap(lookup.herd(id: herdID, in: context))
                let pasture = try XCTUnwrap(lookup.herdOwned(
                    CDPasture.self, id: pastureID, herdID: herdID, in: context
                ))
                herd.name = "Rejected Herd Rename"
                herd.updatedAt = Date(timeIntervalSince1970: 200)
                pasture.name = "Rejected Pasture Rename"
                _ = Self.makePasture(
                    id: rejectedPastureID, name: "Rejected Insert", herd: herd, in: context
                )

                let invalid = CDHerd(context: context)
                invalid.id = invalidHerdID
                invalid.createdAt = originalUpdatedAt
                invalid.updatedAt = originalUpdatedAt
                // Required name is absent: Core Data's actual save must fail validation.
            }
            XCTFail("The mixed transaction must fail during Core Data save.")
        } catch let error as CoreDataPersistenceError {
            guard case .saveFailed = error else {
                XCTFail("Expected saveFailed, received \(error).")
                return
            }
        } catch {
            XCTFail("Expected CoreDataPersistenceError, received \(type(of: error)).")
            return
        }

        let failedReopen = try await harness.makeAssembly(accessMode: .readOnly)
        let failedContext = failedReopen.contextFactory.makeReadContext()
        try failedContext.performAndWait {
            let herd = try XCTUnwrap(CoreDataLookup().herd(id: herdID, in: failedContext))
            XCTAssertEqual(herd.name, "Stable Herd")
            XCTAssertEqual(herd.createdAt, originalUpdatedAt)
            XCTAssertEqual(herd.updatedAt, originalUpdatedAt)
            let pasture = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: pastureID, herdID: herdID, in: failedContext
            ))
            XCTAssertEqual(pasture.name, "Stable Pasture")
            XCTAssertEqual(pasture.herd.id, herdID)
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self, id: rejectedPastureID, herdID: herdID, in: failedContext
            ))
            XCTAssertNil(try CoreDataLookup().herd(id: invalidHerdID, in: failedContext))
            let control = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: controlPastureID, herdID: herdID, in: failedContext
            ))
            XCTAssertEqual(control.name, "Control Pasture")
            XCTAssertEqual(control.herd.id, herdID)
        }

        try await writer.transactionExecutor.performWrite { context in
            let herd = try XCTUnwrap(lookup.herd(id: herdID, in: context))
            herd.name = "Committed Herd Rename"
            herd.updatedAt = committedUpdatedAt
            _ = Self.makePasture(
                id: committedPastureID, name: "Committed Insert", herd: herd, in: context
            )
        }

        let committedReopen = try await harness.makeAssembly(accessMode: .readOnly)
        let committedContext = committedReopen.contextFactory.makeReadContext()
        try committedContext.performAndWait {
            let herd = try XCTUnwrap(CoreDataLookup().herd(
                id: herdID, in: committedContext
            ))
            XCTAssertEqual(herd.id, herdID)
            XCTAssertEqual(herd.name, "Committed Herd Rename")
            XCTAssertEqual(herd.createdAt, originalUpdatedAt)
            XCTAssertEqual(herd.updatedAt, committedUpdatedAt)

            let committed = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: committedPastureID, herdID: herdID, in: committedContext
            ))
            XCTAssertEqual(committed.name, "Committed Insert")
            XCTAssertEqual(committed.herd.id, herdID)
            let original = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: pastureID, herdID: herdID, in: committedContext
            ))
            XCTAssertEqual(original.name, "Stable Pasture")
            let control = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: controlPastureID, herdID: herdID, in: committedContext
            ))
            XCTAssertEqual(control.name, "Control Pasture")
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self, id: rejectedPastureID, herdID: herdID, in: committedContext
            ))
            XCTAssertNil(try CoreDataLookup().herd(
                id: invalidHerdID, in: committedContext
            ))
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
                try CoreDataLookup().herd(id: herdID, in: readContext)?.name,
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

    func testPhysicalPastureDeletionPreservesCrossFeatureSnapshotsAndNullifiesLinks() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let herdID = UUID()
        let removedPastureID = UUID()
        let controlPastureID = UUID()
        let fieldSessionID = UUID()
        let workingSessionID = UUID()
        let queueID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        try await assembly.transactionExecutor.performWrite { context in
            let herd = Self.makeHerd(id: herdID, name: "Delete-Rule Herd", in: context)
            let pasture = Self.makePasture(
                id: removedPastureID,
                name: "Original Pasture",
                herd: herd,
                in: context
            )
            _ = Self.makePasture(
                id: controlPastureID,
                name: "Control Pasture",
                herd: herd,
                in: context
            )

            let fieldSession = Self.makeFieldCheckSession(
                id: fieldSessionID,
                pasture: pasture,
                herd: herd,
                startedAt: timestamp,
                in: context
            )
            fieldSession.completedAt = timestamp.addingTimeInterval(30)

            let workingSession = Self.makeWorkingSession(
                id: workingSessionID,
                pasture: pasture,
                herd: herd,
                date: timestamp,
                in: context
            )
            let queue = CDWorkingQueueItem(context: context)
            queue.id = queueID
            queue.statusRawValue = WorkingQueueStatus.queued.rawValue
            queue.animalIDSnapshot = UUID()
            queue.animalTagNumberSnapshot = "17"
            queue.animalNameSnapshot = "Historical Cow"
            queue.animalSexRawValueSnapshot = Sex.female.rawValue
            queue.collectedFromPastureIDSnapshot = removedPastureID
            queue.collectedFromPastureNameSnapshot = pasture.name
            queue.destinationPastureIDSnapshot = removedPastureID
            queue.destinationPastureNameSnapshot = pasture.name
            queue.herd = herd
            queue.session = workingSession
            queue.collectedFromPasture = pasture
            queue.destinationPasture = pasture
        }

        try await assembly.transactionExecutor.performWrite { context in
            let pasture = try XCTUnwrap(
                CoreDataLookup().herdOwned(
                    CDPasture.self,
                    id: removedPastureID,
                    herdID: herdID,
                    in: context
                )
            )
            context.delete(pasture)
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let freshContext = reopened.contextFactory.makeReadContext()
        try freshContext.performAndWait {
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDPasture.self, id: removedPastureID, herdID: herdID, in: freshContext
            ))
            let control = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: controlPastureID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(control.name, "Control Pasture")
            XCTAssertNotNil(try CoreDataLookup().herd(id: herdID, in: freshContext))

            let fieldSession = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDFieldCheckSession.self, id: fieldSessionID, herdID: herdID, in: freshContext
            ))
            XCTAssertNil(fieldSession.pasture)
            XCTAssertEqual(fieldSession.pastureIDSnapshot, removedPastureID)
            XCTAssertEqual(fieldSession.pastureNameSnapshot, "Original Pasture")
            XCTAssertEqual(fieldSession.completedAt, timestamp.addingTimeInterval(30))

            let working = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDWorkingSession.self, id: workingSessionID, herdID: herdID, in: freshContext
            ))
            XCTAssertNil(working.sourcePasture)
            XCTAssertEqual(working.sourcePastureIDSnapshot, removedPastureID)
            XCTAssertEqual(working.sourcePastureNameSnapshot, "Original Pasture")

            let queue = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDWorkingQueueItem.self, id: queueID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(try XCTUnwrap(queue.session).id, workingSessionID)
            XCTAssertNil(queue.collectedFromPasture)
            XCTAssertNil(queue.destinationPasture)
            XCTAssertEqual(queue.collectedFromPastureIDSnapshot, removedPastureID)
            XCTAssertEqual(queue.collectedFromPastureNameSnapshot, "Original Pasture")
            XCTAssertEqual(queue.destinationPastureIDSnapshot, removedPastureID)
            XCTAssertEqual(queue.destinationPastureNameSnapshot, "Original Pasture")
        }
    }

    func testPhysicalAnimalDeletionCascadesOwnedRowsAndRetainsHistoricalReferences() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let herdID = UUID()
        let pastureID = UUID()
        let removedAnimalID = UUID()
        let controlAnimalID = UUID()
        let tagID = UUID()
        let movementID = UUID()
        let fieldSessionID = UUID()
        let checkID = UUID()
        let findingID = UUID()
        let workingSessionID = UUID()
        let queueID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        try await assembly.transactionExecutor.performWrite { context in
            let herd = Self.makeHerd(id: herdID, name: "Animal Delete-Rule Herd", in: context)
            let pasture = Self.makePasture(
                id: pastureID, name: "Animal Pasture", herd: herd, in: context
            )
            let animal = try Self.makeAnimal(
                id: removedAnimalID, name: "Historical Cow", herd: herd, in: context
            )
            _ = try Self.makeAnimal(
                id: controlAnimalID, name: "Control Cow", herd: herd, in: context
            )
            animal.currentPasture = pasture

            let tag = CDAnimalTag(context: context)
            tag.id = tagID
            tag.number = "17"
            tag.isPrimary = true
            tag.isActive = true
            tag.assignedAt = timestamp
            tag.herd = herd
            tag.animal = animal

            let movement = CDMovementRecord(context: context)
            movement.id = movementID
            movement.date = timestamp
            movement.toPastureIDSnapshot = pastureID
            movement.toPastureNameSnapshot = pasture.name
            movement.herd = herd
            movement.animal = animal

            let fieldSession = Self.makeFieldCheckSession(
                id: fieldSessionID,
                pasture: pasture,
                herd: herd,
                startedAt: timestamp,
                in: context
            )
            let check = CDFieldCheckAnimalCheck(context: context)
            check.id = checkID
            check.animalIDSnapshot = removedAnimalID
            check.rosterTagNumberSnapshot = "17"
            check.animalNameSnapshot = "Historical Cow"
            check.animalSexRawValueSnapshot = Sex.female.rawValue
            check.animalTypeRawValueSnapshot = "cow"
            check.wasExpectedAtStart = true
            check.herd = herd
            check.session = fieldSession
            check.animal = animal

            let finding = CDFieldCheckFinding(context: context)
            finding.id = findingID
            finding.recordedAt = timestamp
            finding.typeRawValue = "other"
            finding.severityRawValue = "low"
            finding.statusRawValue = "open"
            finding.note = "Historical finding"
            finding.animalIDSnapshot = removedAnimalID
            finding.animalDisplayTagNumberSnapshot = "17"
            finding.animalNameSnapshot = "Historical Cow"
            finding.pastureNameSnapshot = pasture.name
            finding.herd = herd
            finding.session = fieldSession
            finding.animal = animal

            let workingSession = Self.makeWorkingSession(
                id: workingSessionID,
                pasture: pasture,
                herd: herd,
                date: timestamp,
                in: context
            )
            animal.activeWorkingSession = workingSession

            let queue = CDWorkingQueueItem(context: context)
            queue.id = queueID
            queue.statusRawValue = WorkingQueueStatus.queued.rawValue
            queue.animalIDSnapshot = removedAnimalID
            queue.animalTagNumberSnapshot = "17"
            queue.animalNameSnapshot = "Historical Cow"
            queue.animalSexRawValueSnapshot = Sex.female.rawValue
            queue.herd = herd
            queue.session = workingSession
            queue.animal = animal
        }

        try await assembly.transactionExecutor.performWrite { context in
            let animal = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDAnimal.self, id: removedAnimalID, herdID: herdID, in: context
            ))
            let workingSession = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDWorkingSession.self, id: workingSessionID, herdID: herdID, in: context
            ))
            XCTAssertTrue(workingSession.activeAnimals?.contains(animal) == true)
            context.delete(animal)
        }

        let reopened = try await harness.makeAssembly(accessMode: .readOnly)
        let freshContext = reopened.contextFactory.makeReadContext()
        try freshContext.performAndWait {
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDAnimal.self, id: removedAnimalID, herdID: herdID, in: freshContext
            ))
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDAnimalTag.self, id: tagID, herdID: herdID, in: freshContext
            ))
            XCTAssertNil(try CoreDataLookup().herdOwned(
                CDMovementRecord.self, id: movementID, herdID: herdID, in: freshContext
            ))
            let control = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDAnimal.self, id: controlAnimalID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(control.name, "Control Cow")
            XCTAssertNotNil(try CoreDataLookup().herd(id: herdID, in: freshContext))

            let fieldSession = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDFieldCheckSession.self, id: fieldSessionID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(fieldSession.pasture?.id, pastureID)

            let check = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDFieldCheckAnimalCheck.self, id: checkID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(check.session.id, fieldSessionID)
            XCTAssertNil(check.animal)
            XCTAssertEqual(check.animalIDSnapshot, removedAnimalID)
            XCTAssertEqual(check.rosterTagNumberSnapshot, "17")
            XCTAssertEqual(check.animalNameSnapshot, "Historical Cow")

            let finding = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDFieldCheckFinding.self, id: findingID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(try XCTUnwrap(finding.session).id, fieldSessionID)
            XCTAssertNil(finding.animal)
            XCTAssertEqual(finding.animalIDSnapshot, removedAnimalID)
            XCTAssertEqual(finding.animalDisplayTagNumberSnapshot, "17")
            XCTAssertEqual(finding.animalNameSnapshot, "Historical Cow")
            XCTAssertEqual(finding.note, "Historical finding")

            let working = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDWorkingSession.self, id: workingSessionID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(working.sourcePasture?.id, pastureID)
            XCTAssertEqual(working.activeAnimals?.count ?? 0, 0)
            let queue = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDWorkingQueueItem.self, id: queueID, herdID: herdID, in: freshContext
            ))
            XCTAssertEqual(try XCTUnwrap(queue.session).id, workingSessionID)
            XCTAssertNil(queue.animal)
            XCTAssertEqual(queue.animalIDSnapshot, removedAnimalID)
            XCTAssertEqual(queue.animalTagNumberSnapshot, "17")
            XCTAssertEqual(queue.animalNameSnapshot, "Historical Cow")
        }
    }

    private static func makePasture(
        id: UUID,
        name: String,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) -> CDPasture {
        let pasture = CDPasture(context: context)
        pasture.id = id
        pasture.name = name
        pasture.sortOrder = 0
        pasture.herd = herd
        return pasture
    }

    private static func makeAnimal(
        id: UUID,
        name: String,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> CDAnimal {
        let animal = CDAnimal(context: context)
        animal.id = id
        animal.editorRevision = UUID()
        animal.name = name
        animal.sexRawValue = Sex.female.rawValue
        animal.birthDate = Date(timeIntervalSince1970: 1_700_000_000)
        animal.statusRawValue = AnimalStatus.active.rawValue
        animal.isArchived = false
        animal.distinguishingFeaturesData = try CoreDataAnimalPayloadCodec
            .encodeDistinguishingFeatures([])
        animal.herd = herd
        return animal
    }

    private static func makeFieldCheckSession(
        id: UUID,
        pasture: CDPasture,
        herd: CDHerd,
        startedAt: Date,
        in context: NSManagedObjectContext
    ) -> CDFieldCheckSession {
        let session = CDFieldCheckSession(context: context)
        session.id = id
        session.startedAt = startedAt
        session.notes = "Historical session"
        session.expectedHeadCountSnapshot = 1
        session.quickCowCount = 0
        session.quickHeiferCount = 0
        session.quickCalfCount = 0
        session.quickBullCount = 0
        session.quickSteerCount = 0
        session.pastureIDSnapshot = pasture.id
        session.pastureNameSnapshot = pasture.name
        session.herd = herd
        session.pasture = pasture
        return session
    }

    private static func makeWorkingSession(
        id: UUID,
        pasture: CDPasture,
        herd: CDHerd,
        date: Date,
        in context: NSManagedObjectContext
    ) -> CDWorkingSession {
        let session = CDWorkingSession(context: context)
        session.id = id
        session.date = date
        session.statusRawValue = WorkingSessionStatus.active.rawValue
        session.treatmentTemplateNameSnapshot = ""
        session.plannedTreatmentsData = Data("[]".utf8)
        session.sourcePastureIDSnapshot = pasture.id
        session.sourcePastureNameSnapshot = pasture.name
        session.herd = herd
        session.sourcePasture = pasture
        return session
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
