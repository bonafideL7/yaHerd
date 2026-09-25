import Foundation
import XCTest
@testable import yaHerd

enum PersistenceTransactionPreconditionFailure: Equatable, Sendable {
    case staleAnimalAggregate(animalID: UUID)
    case animalAggregateMissing(animalID: UUID)
    case pastureMissing(pastureID: UUID)
    case pastureResidentSetChanged(pastureID: UUID)
}

/// Target-runner probe for the Animal editor revision lifecycle.
///
/// The writer and readers must be the real target implementations of
/// `AnimalAggregateTransactionWriting` and `AnimalAggregateEditReading`. Each `makeReader` call
/// must create a fresh access scope so returned revisions and aggregate state are proven durable.
///
/// The fixture must provide:
/// - one valid tagged aggregate create transaction;
/// - a scalar-only update that materially changes editor-owned Animal attributes;
/// - a tag-only update that materially changes tag state without relying on scalar changes;
/// - a distinct stale update built from the snapshot immediately before the tag-only update.
///
/// `classifyError` must return `.staleAnimalAggregate` only for the target persistence layer's
/// stale-revision rejection. Validation, missing-record, unsupported-operation, and other failures
/// must return nil so they cannot satisfy this contract.
@MainActor
struct AnimalAggregateRevisionContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let createTransaction: CreateAnimalAggregateTransaction
    let makeScalarUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
    let makeTagOnlyUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
    let makeStaleUpdateTransaction: (
        _ staleBase: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
    let classifyError: (
        _ error: Error
    ) -> PersistenceTransactionPreconditionFailure?
    let freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot
    let recoveryProbe: PersistenceTransactionRollbackRecoveryProbe
}

/// Target-runner probe for an Animal editor whose aggregate was hard-deleted after it was loaded.
///
/// Fixture setup must create one valid aggregate, capture `staleBase` through a fresh
/// `AnimalAggregateEditReading` scope, and build `updateTransaction` from that captured
/// application UUID/revision with materially changed desired editor state.
///
/// `deleter` must be the real target `AnimalDeleting` implementation. The contract invokes
/// `delete(ids:)` for `staleBase.animal.id` only after proving a fresh reader
/// still returns `staleBase`, then attempts the stale editor save against the now-missing row.
/// `classifyError` must map only the target persistence layer's missing-aggregate rejection to
/// `.animalAggregateMissing`; stale-revision, validation, unsupported-operation, and other failures
/// must return nil.
@MainActor
struct AnimalAggregateMissingPreconditionContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let staleBase: AnimalAggregateEditSnapshot
    let updateTransaction: UpdateAnimalAggregateTransaction
    let deleter: any AnimalDeleting
    let classifyError: (
        _ error: Error
    ) -> PersistenceTransactionPreconditionFailure?
    let freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot
    let recoveryProbe: PersistenceTransactionRollbackRecoveryProbe
}

/// Target-runner probe for stale Pasture deletion plans.
///
/// The plan must have been valid when Domain observed the expected state, but the fixture must alter
/// the current persisted state before returning the probe so the expected state is stale at
/// execution time. The writer must be the real `PastureDeletionTransactionWriting` implementation.
///
/// `classifyError` must translate only the target persistence layer's stale-plan rejection to the
/// supplied `expectedFailure`; unrelated validation or implementation failures must return nil.
@MainActor
struct PastureDeletionPreconditionContractProbe {
    let writer: any PastureDeletionTransactionWriting
    let plan: DeletePasturesTransactionPlan
    let expectedFailure: PersistenceTransactionPreconditionFailure
    let classifyError: (
        _ error: Error
    ) -> PersistenceTransactionPreconditionFailure?
    let freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot
    let recoveryProbe: PersistenceTransactionRollbackRecoveryProbe
}

@MainActor
struct PersistenceTransactionPreconditionContractFixture {
    let makeAnimalAggregateRevisionProbe: () throws -> AnimalAggregateRevisionContractProbe
    let makeAnimalAggregateMissingProbe: () throws -> AnimalAggregateMissingPreconditionContractProbe
    let makePastureResidentSetChangedProbe: () throws -> PastureDeletionPreconditionContractProbe
    let makePastureMissingProbe: () throws -> PastureDeletionPreconditionContractProbe
}

/// Permanent persistence-neutral contract for target transaction preconditions that do not exist on
/// the outgoing repository surface.
///
/// Fault-injected rollback after partial staging remains owned by
/// `PersistenceTransactionRollbackContract`; mutation publication remains owned by
/// `MutationBoundaryContract`.
@MainActor
enum PersistenceTransactionPreconditionContract {
    static func assertAnimalAggregateRevisionLifecycleAndStaleRejection(
        using fixture: PersistenceTransactionPreconditionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let probe = try fixture.makeAnimalAggregateRevisionProbe()

        let created = try probe.writer.createAnimal(probe.createTransaction)
        XCTAssertEqual(
            created.animal.id,
            probe.createTransaction.animalID,
            "Aggregate create must preserve the application-assigned Animal UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(created.animal.activeTags.map(\.id) + created.animal.inactiveTags.map(\.id)),
            Set(probe.createTransaction.tags.map(\.id)),
            "Aggregate create must preserve the application-assigned tag UUIDs.",
            file: file,
            line: line
        )

        let reloadedCreated = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.createTransaction.animalID),
            "A fresh aggregate reader must resolve the created Animal by application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedCreated,
            created,
            "Create must return the same aggregate state and revision that a fresh reader observes.",
            file: file,
            line: line
        )

        let scalarUpdate = try probe.makeScalarUpdateTransaction(reloadedCreated)
        XCTAssertEqual(scalarUpdate.animalID, reloadedCreated.animal.id, file: file, line: line)
        XCTAssertEqual(scalarUpdate.expectedRevision, reloadedCreated.revision, file: file, line: line)
        XCTAssertEqual(
            scalarUpdate.tags,
            probe.createTransaction.tags,
            "The scalar-update fixture must leave complete tag state unchanged.",
            file: file,
            line: line
        )

        let scalarUpdated = try probe.writer.updateAnimal(scalarUpdate)
        XCTAssertEqual(scalarUpdated.animal.id, reloadedCreated.animal.id, file: file, line: line)
        XCTAssertNotEqual(
            scalarUpdated.animal,
            reloadedCreated.animal,
            "The scalar-update fixture must materially change editor-owned Animal state.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            scalarUpdated.revision,
            reloadedCreated.revision,
            "A successful scalar aggregate update must rotate the editor revision.",
            file: file,
            line: line
        )

        let reloadedScalarUpdated = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: scalarUpdated.animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedScalarUpdated,
            scalarUpdated,
            "A fresh reader must observe the scalar update and rotated revision returned by the transaction.",
            file: file,
            line: line
        )

        let tagUpdate = try probe.makeTagOnlyUpdateTransaction(reloadedScalarUpdated)
        XCTAssertEqual(tagUpdate.animalID, reloadedScalarUpdated.animal.id, file: file, line: line)
        XCTAssertEqual(tagUpdate.expectedRevision, reloadedScalarUpdated.revision, file: file, line: line)
        XCTAssertEqual(
            tagUpdate.attributes,
            scalarUpdate.attributes,
            "The tag-only fixture must leave editor-owned scalar/relationship attributes unchanged.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            tagUpdate.tags,
            scalarUpdate.tags,
            "The tag-only fixture must request materially different tag state.",
            file: file,
            line: line
        )

        let tagUpdated = try probe.writer.updateAnimal(tagUpdate)
        XCTAssertEqual(tagUpdated.animal.id, reloadedScalarUpdated.animal.id, file: file, line: line)
        XCTAssertTrue(
            tagUpdated.animal.activeTags != reloadedScalarUpdated.animal.activeTags
                || tagUpdated.animal.inactiveTags != reloadedScalarUpdated.animal.inactiveTags,
            "The tag-only fixture must materially change persisted tag state.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            tagUpdated.revision,
            reloadedScalarUpdated.revision,
            "A successful tag-only aggregate update must rotate the editor revision.",
            file: file,
            line: line
        )

        let reloadedTagUpdated = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: tagUpdated.animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedTagUpdated,
            tagUpdated,
            "A fresh reader must observe the tag-only update and its rotated revision.",
            file: file,
            line: line
        )

        let staleUpdate = try probe.makeStaleUpdateTransaction(reloadedScalarUpdated)
        XCTAssertEqual(staleUpdate.animalID, reloadedTagUpdated.animal.id, file: file, line: line)
        XCTAssertEqual(
            staleUpdate.expectedRevision,
            reloadedScalarUpdated.revision,
            "The stale-update fixture must reuse the revision that was current before the tag-only update.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            staleUpdate.expectedRevision,
            reloadedTagUpdated.revision,
            "The stale-update fixture must actually carry an obsolete editor revision.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            staleUpdate.attributes != tagUpdate.attributes || staleUpdate.tags != tagUpdate.tags,
            "The stale-update fixture must attempt a materially different aggregate state so silent overwrite would be observable.",
            file: file,
            line: line
        )

        let beforeStaleAttempt = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(beforeStaleAttempt, operation: "stale Animal aggregate update", file: file, line: line)
        var classifiedFailure: PersistenceTransactionPreconditionFailure?
        XCTAssertThrowsError(
            try probe.writer.updateAnimal(staleUpdate),
            "An update using an obsolete aggregate revision must be rejected before mutation.",
            file: file,
            line: line
        ) { error in
            classifiedFailure = probe.classifyError(error)
        }
        XCTAssertEqual(
            classifiedFailure,
            .staleAnimalAggregate(animalID: reloadedTagUpdated.animal.id),
            "The stale aggregate update must surface the persistence-neutral stale-revision classification.",
            file: file,
            line: line
        )

        let afterStaleAttempt = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(afterStaleAttempt, operation: "stale Animal aggregate update", file: file, line: line)
        XCTAssertEqual(
            afterStaleAttempt,
            beforeStaleAttempt,
            "Rejecting a stale aggregate update must leave the complete committed store unchanged.",
            file: file,
            line: line
        )
        try assertFailedWriteScopeRecovery(
            probe.recoveryProbe,
            baseline: beforeStaleAttempt,
            freshPersistedStateSnapshot: probe.freshPersistedStateSnapshot,
            operation: "stale Animal aggregate update",
            file: file,
            line: line
        )
        let afterStaleAggregate = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: reloadedTagUpdated.animal.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterStaleAggregate,
            reloadedTagUpdated,
            "A stale editor must not overwrite the newer aggregate state or revision.",
            file: file,
            line: line
        )
    }

    static func assertAnimalAggregateUpdateRejectsDeletedAggregateWithoutRecreation(
        using fixture: PersistenceTransactionPreconditionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let probe = try fixture.makeAnimalAggregateMissingProbe()
        let animalID = probe.staleBase.animal.id

        XCTAssertEqual(
            probe.updateTransaction.animalID,
            animalID,
            "The deleted-aggregate probe must target the same application UUID the editor originally loaded.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            probe.updateTransaction.expectedRevision,
            probe.staleBase.revision,
            "The deleted-aggregate probe must carry the revision captured before hard deletion.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            probe.updateTransaction.attributes != attributes(from: probe.staleBase.animal)
                || Set(probe.updateTransaction.tags) != tagTransactionStateSet(from: probe.staleBase.animal),
            "The deleted-aggregate probe must attempt a material editor-owned change so accidental recreation would be observable.",
            file: file,
            line: line
        )

        XCTAssertEqual(
            try XCTUnwrap(
                probe.makeReader().fetchAnimalAggregateForEditing(id: animalID),
                "The aggregate must still exist immediately before the contract executes the hard-delete race.",
                file: file,
                line: line
            ),
            probe.staleBase,
            "The pre-delete fresh editor read must match the exact state/revision captured by the stale editor.",
            file: file,
            line: line
        )

        try probe.deleter.delete(ids: [animalID])

        XCTAssertNil(
            try probe.makeReader().fetchAnimalAggregateForEditing(id: animalID),
            "The real Animal deletion boundary must remove the aggregate before the stale editor attempts to save.",
            file: file,
            line: line
        )

        let before = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(
            before,
            operation: "missing Animal aggregate update",
            file: file,
            line: line
        )

        var classifiedFailure: PersistenceTransactionPreconditionFailure?
        XCTAssertThrowsError(
            try probe.writer.updateAnimal(probe.updateTransaction),
            "Updating an aggregate that was hard-deleted after the editor loaded it must fail before mutation.",
            file: file,
            line: line
        ) { error in
            classifiedFailure = probe.classifyError(error)
        }
        XCTAssertEqual(
            classifiedFailure,
            .animalAggregateMissing(animalID: animalID),
            "The missing aggregate update must surface the persistence-neutral missing-record classification rather than stale revision or validation failure.",
            file: file,
            line: line
        )

        let after = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(
            after,
            operation: "missing Animal aggregate update",
            file: file,
            line: line
        )
        XCTAssertEqual(
            after,
            before,
            "Rejecting an update for a hard-deleted aggregate must not recreate the Animal, tags, relationships, history, or any unrelated row.",
            file: file,
            line: line
        )
        XCTAssertNil(
            try probe.makeReader().fetchAnimalAggregateForEditing(id: animalID),
            "A failed stale-editor save must not recreate a hard-deleted Animal aggregate.",
            file: file,
            line: line
        )
        try assertFailedWriteScopeRecovery(
            probe.recoveryProbe,
            baseline: before,
            freshPersistedStateSnapshot: probe.freshPersistedStateSnapshot,
            operation: "missing Animal aggregate update",
            file: file,
            line: line
        )
        XCTAssertNil(
            try probe.makeReader().fetchAnimalAggregateForEditing(id: animalID),
            "Recovery/save of the failed write scope must not resurrect the deleted aggregate.",
            file: file,
            line: line
        )
    }

    static func assertPastureDeletionRejectsStaleExpectedStateBeforeMutation(
        using fixture: PersistenceTransactionPreconditionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertPastureDeletionRejectsStaleExpectedState(
            probe: fixture.makePastureResidentSetChangedProbe(),
            requiredFailureCase: .residentSetChanged,
            file: file,
            line: line
        )
        try assertPastureDeletionRejectsStaleExpectedState(
            probe: fixture.makePastureMissingProbe(),
            requiredFailureCase: .missingPasture,
            file: file,
            line: line
        )
    }

    private enum RequiredPastureFailureCase {
        case residentSetChanged
        case missingPasture
    }

    private static func assertPastureDeletionRejectsStaleExpectedState(
        probe: PastureDeletionPreconditionContractProbe,
        requiredFailureCase: RequiredPastureFailureCase,
        file: StaticString,
        line: UInt
    ) throws {
        let expectedPastureID: UUID
        switch (requiredFailureCase, probe.expectedFailure) {
        case let (.residentSetChanged, .pastureResidentSetChanged(pastureID)):
            expectedPastureID = pastureID
        case let (.missingPasture, .pastureMissing(pastureID)):
            expectedPastureID = pastureID
        default:
            XCTFail(
                "Pasture stale-state fixture returned the wrong expected failure classification.",
                file: file,
                line: line
            )
            return
        }

        XCTAssertGreaterThanOrEqual(
            probe.plan.expectedStates.count,
            2,
            "Each stale Pasture precondition probe must exercise a batched plan with at least two expected Pastures.",
            file: file,
            line: line
        )
        let expectedPastureIDs = probe.plan.expectedStates.map(\.pastureID)
        XCTAssertEqual(
            Set(expectedPastureIDs).count,
            expectedPastureIDs.count,
            "Stale Pasture probes must begin from a normalized plan with unique expected-state Pasture IDs.",
            file: file,
            line: line
        )
        let deleteOperations = probe.plan.operations.compactMap { operation -> [UUID]? in
            guard case .deletePastures(let ids) = operation else { return nil }
            return ids
        }
        XCTAssertEqual(
            deleteOperations.count,
            1,
            "Stale Pasture probes must contain exactly one normalized final delete operation.",
            file: file,
            line: line
        )
        let deletedPastureIDs = try XCTUnwrap(deleteOperations.first, file: file, line: line)
        XCTAssertEqual(
            Set(deletedPastureIDs).count,
            deletedPastureIDs.count,
            "The stale probe's final delete operation must not repeat Pasture IDs.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(deletedPastureIDs),
            Set(expectedPastureIDs),
            "Stale precondition probes must delete every and only Pasture represented by expectedStates.",
            file: file,
            line: line
        )
        let staleExpectedStateIndex = try XCTUnwrap(
            probe.plan.expectedStates.firstIndex { $0.pastureID == expectedPastureID },
            "The stale Pasture classification must identify a Pasture represented in the Domain-authored expected state.",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            staleExpectedStateIndex,
            0,
            "The stale Pasture must be a non-first expected-state member so the contract proves every Pasture in a batch is revalidated.",
            file: file,
            line: line
        )

        let before = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(before, operation: "stale Pasture deletion", file: file, line: line)
        var classifiedFailure: PersistenceTransactionPreconditionFailure?
        XCTAssertThrowsError(
            try probe.writer.deletePastures(probe.plan),
            "A stale Pasture deletion plan must be rejected before any supplied plan operation mutates durable state.",
            file: file,
            line: line
        ) { error in
            classifiedFailure = probe.classifyError(error)
        }
        XCTAssertEqual(
            classifiedFailure,
            probe.expectedFailure,
            "Pasture deletion must surface the expected persistence-neutral stale-state classification.",
            file: file,
            line: line
        )
        let after = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(after, operation: "stale Pasture deletion", file: file, line: line)
        XCTAssertEqual(
            after,
            before,
            "Stale Pasture deletion rejection must leave the complete committed store unchanged.",
            file: file,
            line: line
        )
        try assertFailedWriteScopeRecovery(
            probe.recoveryProbe,
            baseline: before,
            freshPersistedStateSnapshot: probe.freshPersistedStateSnapshot,
            operation: "stale Pasture deletion",
            file: file,
            line: line
        )
    }

    private static func attributes(
        from detail: AnimalDetailSnapshot
    ) -> AnimalAggregateAttributes {
        AnimalAggregateAttributes(
            name: detail.name,
            sex: detail.sex,
            birthDate: detail.birthDate,
            status: detail.status,
            pastureID: detail.pastureID,
            sireID: detail.sireID,
            damID: detail.damID,
            distinguishingFeatures: detail.distinguishingFeatures,
            saleDate: detail.saleDate,
            salePrice: detail.salePrice,
            reasonSold: detail.reasonSold,
            deathDate: detail.deathDate,
            causeOfDeath: detail.causeOfDeath,
            statusReferenceID: detail.statusReferenceID
        )
    }

    private static func tagTransactionStateSet(
        from detail: AnimalDetailSnapshot
    ) -> Set<AnimalTagTransactionState> {
        Set((detail.activeTags + detail.inactiveTags).map {
            AnimalTagTransactionState(
                id: $0.id,
                number: $0.number,
                colorID: $0.colorID,
                isPrimary: $0.isPrimary,
                isActive: $0.isActive
            )
        })
    }

    private static func assertFailedWriteScopeRecovery(
        _ recoveryProbe: PersistenceTransactionRollbackRecoveryProbe,
        baseline: PersistenceTransactionRollbackStateSnapshot,
        freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot,
        operation: String,
        file: StaticString,
        line: UInt
    ) throws {
        switch recoveryProbe {
        case .reusableWriteScope(let saveFailedWriteScopeWithoutAdditionalReset):
            try saveFailedWriteScopeWithoutAdditionalReset()
            let afterRecoverySave = try freshPersistedStateSnapshot()
            assertCompleteStoreSnapshot(afterRecoverySave, operation: operation, file: file, line: line)
            XCTAssertEqual(
                afterRecoverySave,
                baseline,
                "Re-saving the exact failed write scope for \(operation) without an additional test-side reset must not persist rejected staged state.",
                file: file,
                line: line
            )

        case .discardedWriteScope(let verifyFailedWriteScopeWasDisposed):
            XCTAssertTrue(
                verifyFailedWriteScopeWasDisposed(),
                "A one-shot failed write scope for \(operation) must be disposed so rejected staged state cannot be saved later.",
                file: file,
                line: line
            )
        }
    }

    private static func assertCompleteStoreSnapshot(
        _ snapshot: PersistenceTransactionRollbackStateSnapshot,
        operation: String,
        file: StaticString,
        line: UInt
    ) {
        let expectedKinds = Set(IdentityContractEntityKind.allCases)
        XCTAssertEqual(
            Set(snapshot.applicationIDsByKind.keys),
            expectedKinds,
            "The complete-store snapshot for \(operation) must inventory every durable entity kind by application UUID, including empty sets.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(snapshot.persistedRowCountsByKind.keys),
            expectedKinds,
            "The complete-store snapshot for \(operation) must inventory physical row counts for every durable entity kind.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            snapshot.persistedRowCountsByKind.values.allSatisfy { $0 >= 0 },
            "Persisted row counts for \(operation) must never be negative.",
            file: file,
            line: line
        )
    }
}
