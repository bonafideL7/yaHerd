import Foundation
import XCTest
@testable import yaHerd

enum PersistenceTransactionRollbackOperation: String, Sendable {
    case animalAggregateCreate
    case animalAggregateUpdate
    case pastureDeletion
}

/// Persistence-neutral snapshot of the complete isolated store used by one rollback probe.
///
/// `businessStateFingerprint` must deterministically include every persisted business value and
/// application-UUID relationship target for every durable record in the isolated store. Framework
/// object IDs, context identity, store URLs, temporary IDs, and other persistence-native values are
/// forbidden.
///
/// `applicationIDsByKind` independently inventories every durable application UUID by entity kind.
/// `persistedRowCountsByKind` preserves physical multiplicity so two persisted rows carrying the
/// same application UUID cannot collapse into one set entry and hide a rollback leak. Both maps must
/// include all `IdentityContractEntityKind.allCases` keys, using an empty set / zero count when no
/// row of that kind exists. Together these fields make partial value/relationship changes plus
/// leaked/deleted/duplicated rows observable after a failed transaction.
struct PersistenceTransactionRollbackStateSnapshot: Equatable, Sendable {
    let businessStateFingerprint: String
    let applicationIDsByKind: [IdentityContractEntityKind: Set<UUID>]
    let persistedRowCountsByKind: [IdentityContractEntityKind: Int]
}

/// Post-failure policy for the exact write scope used by a fault-injected transaction.
///
/// A reusable scope must already have been rolled back/reset by production failure handling before
/// the transaction method returns. The contract then saves that exact failed scope again without any
/// additional test-side reset; no staged transaction state may leak into durable storage.
///
/// A one-shot scope may instead be discarded after failure. The runner must verify that exact failed
/// scope is no longer reusable/owned by the transaction executor.
enum PersistenceTransactionRollbackRecoveryProbe {
    case reusableWriteScope(
        saveFailedWriteScopeWithoutAdditionalReset: () throws -> Void
    )
    case discardedWriteScope(
        verifyFailedWriteScopeWasDisposed: () -> Bool
    )
}

/// Fault-injected probe for `AnimalAggregateTransactionWriting.createAnimal`.
///
/// The supplied writer must be the real target transaction implementation configured so the call to
/// `createAnimal` fails only after the Animal and at least one aggregate relationship/tag/history
/// effect have been staged but before commit succeeds.
@MainActor
struct AnimalAggregateCreateRollbackProbe {
    let writer: any AnimalAggregateTransactionWriting
    let transaction: CreateAnimalAggregateTransaction
    let didReachInjectedRollbackFailpoint: () -> Bool
    let freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot
    let recoveryProbe: PersistenceTransactionRollbackRecoveryProbe
}

/// Fault-injected probe for `AnimalAggregateTransactionWriting.updateAnimal`.
///
/// The supplied transaction must be otherwise valid, including a current `expectedRevision`. The
/// configured failpoint must occur only after at least one requested existing-value, relationship,
/// tag, or history change has been staged but before commit succeeds. Stale-revision rejection is a
/// separate precondition behavior and must not satisfy this rollback probe.
@MainActor
struct AnimalAggregateUpdateRollbackProbe {
    let writer: any AnimalAggregateTransactionWriting
    let transaction: UpdateAnimalAggregateTransaction
    let didReachInjectedRollbackFailpoint: () -> Bool
    let freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot
    let recoveryProbe: PersistenceTransactionRollbackRecoveryProbe
}

/// Fault-injected probe for `PastureDeletionTransactionWriting.deletePastures`.
///
/// The plan must be valid when execution begins. The configured failpoint must occur only after at
/// least one supplied plan operation has staged its durable effect but before the logical transaction
/// commits. Stale-plan rejection is a separate precondition behavior and must not satisfy this probe.
@MainActor
struct PastureDeletionRollbackProbe {
    let writer: any PastureDeletionTransactionWriting
    let plan: DeletePasturesTransactionPlan
    let didReachInjectedRollbackFailpoint: () -> Bool
    let freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot
    let recoveryProbe: PersistenceTransactionRollbackRecoveryProbe
}

/// Permanent fixture for target transaction rollback semantics.
///
/// Each factory must create a fresh isolated persistent store. No SwiftData compatibility runner
/// should be introduced for this contract.
@MainActor
struct PersistenceTransactionRollbackContractFixture {
    let makeAnimalAggregateCreateProbe: () throws -> AnimalAggregateCreateRollbackProbe
    let makeAnimalAggregateUpdateProbe: () throws -> AnimalAggregateUpdateRollbackProbe
    let makePastureDeletionProbe: () throws -> PastureDeletionRollbackProbe
}

/// Permanent persistence-neutral contract for all-or-nothing rollback of the final transaction ports.
///
/// Successful feature behavior remains owned by the corresponding Animal/Pasture contracts.
/// Mutation publication is owned by `MutationBoundaryContract`. This contract owns only durable
/// rollback after a material partial transaction write has been staged.
@MainActor
enum PersistenceTransactionRollbackContract {
    static func assertFailedTargetTransactionsRollBackAllDurableState(
        using fixture: PersistenceTransactionRollbackContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let createProbe = try fixture.makeAnimalAggregateCreateProbe()
        try assertRollback(
            operation: .animalAggregateCreate,
            didReachInjectedRollbackFailpoint: createProbe.didReachInjectedRollbackFailpoint,
            freshPersistedStateSnapshot: createProbe.freshPersistedStateSnapshot,
            recoveryProbe: createProbe.recoveryProbe,
            performFailingTransaction: {
                _ = try createProbe.writer.createAnimal(createProbe.transaction)
            },
            file: file,
            line: line
        )

        let updateProbe = try fixture.makeAnimalAggregateUpdateProbe()
        try assertRollback(
            operation: .animalAggregateUpdate,
            didReachInjectedRollbackFailpoint: updateProbe.didReachInjectedRollbackFailpoint,
            freshPersistedStateSnapshot: updateProbe.freshPersistedStateSnapshot,
            recoveryProbe: updateProbe.recoveryProbe,
            performFailingTransaction: {
                _ = try updateProbe.writer.updateAnimal(updateProbe.transaction)
            },
            file: file,
            line: line
        )

        let pastureProbe = try fixture.makePastureDeletionProbe()
        try assertRollback(
            operation: .pastureDeletion,
            didReachInjectedRollbackFailpoint: pastureProbe.didReachInjectedRollbackFailpoint,
            freshPersistedStateSnapshot: pastureProbe.freshPersistedStateSnapshot,
            recoveryProbe: pastureProbe.recoveryProbe,
            performFailingTransaction: {
                try pastureProbe.writer.deletePastures(pastureProbe.plan)
            },
            file: file,
            line: line
        )
    }

    private static func assertRollback(
        operation: PersistenceTransactionRollbackOperation,
        didReachInjectedRollbackFailpoint: () -> Bool,
        freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot,
        recoveryProbe: PersistenceTransactionRollbackRecoveryProbe,
        performFailingTransaction: () throws -> Void,
        file: StaticString,
        line: UInt
    ) throws {
        let expectedKinds = Set(IdentityContractEntityKind.allCases)

        XCTAssertFalse(
            didReachInjectedRollbackFailpoint(),
            "Rollback fixture setup for \(operation.rawValue) must not report that the injected failpoint was already reached.",
            file: file,
            line: line
        )

        let before = try freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(
            before,
            expectedKinds: expectedKinds,
            operation: operation,
            phase: "before failure",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try performFailingTransaction(),
            "The rollback probe for \(operation.rawValue) must surface its injected persistence failure.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            didReachInjectedRollbackFailpoint(),
            "The rollback probe for \(operation.rawValue) must prove a material partial transaction write was staged before failure.",
            file: file,
            line: line
        )

        let after = try freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(
            after,
            expectedKinds: expectedKinds,
            operation: operation,
            phase: "after failure",
            file: file,
            line: line
        )
        XCTAssertEqual(
            after,
            before,
            "A failed \(operation.rawValue) target transaction must leave the complete committed isolated store unchanged.",
            file: file,
            line: line
        )

        switch recoveryProbe {
        case .reusableWriteScope(let saveFailedWriteScopeWithoutAdditionalReset):
            try saveFailedWriteScopeWithoutAdditionalReset()
            let afterRecoverySave = try freshPersistedStateSnapshot()
            assertCompleteStoreSnapshot(
                afterRecoverySave,
                expectedKinds: expectedKinds,
                operation: operation,
                phase: "after recovery save",
                file: file,
                line: line
            )
            XCTAssertEqual(
                afterRecoverySave,
                before,
                "Re-saving the exact failed \(operation.rawValue) write scope without an additional test-side reset must not flush staged partial transaction state.",
                file: file,
                line: line
            )

        case .discardedWriteScope(let verifyFailedWriteScopeWasDisposed):
            XCTAssertTrue(
                verifyFailedWriteScopeWasDisposed(),
                "A one-shot failed \(operation.rawValue) write scope must be disposed so staged partial state cannot be saved later.",
                file: file,
                line: line
            )
        }
    }

    private static func assertCompleteStoreSnapshot(
        _ snapshot: PersistenceTransactionRollbackStateSnapshot,
        expectedKinds: Set<IdentityContractEntityKind>,
        operation: PersistenceTransactionRollbackOperation,
        phase: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(
            Set(snapshot.applicationIDsByKind.keys),
            expectedKinds,
            "The rollback snapshot for \(operation.rawValue) \(phase) must inventory every durable entity kind by application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(snapshot.persistedRowCountsByKind.keys),
            expectedKinds,
            "The rollback snapshot for \(operation.rawValue) \(phase) must inventory physical row counts for every durable entity kind.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            snapshot.persistedRowCountsByKind.values.allSatisfy { $0 >= 0 },
            "Persisted row counts for \(operation.rawValue) \(phase) must never be negative.",
            file: file,
            line: line
        )
    }
}
