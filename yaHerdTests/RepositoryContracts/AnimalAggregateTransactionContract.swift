import Foundation
import XCTest
@testable import yaHerd

enum AnimalAggregateTagValidationFailure: CaseIterable, Equatable, Sendable {
    case activeTagsRequirePrimary
    case multipleActivePrimaryTags
    case inactiveTagCannotBePrimary
    case duplicateTagApplicationIDs
}

enum AnimalAggregateInvalidTagMethod: CaseIterable, Equatable, Sendable {
    case create
    case update
}

enum AnimalAggregateInvalidTagOperation {
    case create(CreateAnimalAggregateTransaction)
    case update(UpdateAnimalAggregateTransaction)

    var method: AnimalAggregateInvalidTagMethod {
        switch self {
        case .create: return .create
        case .update: return .update
        }
    }
}

/// Target-runner probe for one valid tagged aggregate create.
///
/// Relationship/support rows referenced by `transaction.attributes` and tag color IDs must already
/// exist in the isolated store. The representative tagged create must supply non-nil Pasture, dam,
/// sire, and status-reference application UUIDs so initial relationship wiring/read projections are
/// exercised. The fixture must also make this created Animal an eligible sole inferred sire for at
/// least one preexisting active dam in the selected Pasture. The writer/readers must be the real
/// target transaction/repository ports.
@MainActor
struct AnimalAggregateTaggedCreateContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makePastureRepository: () -> any PastureRepository
    let makeWorkingOwnershipControl: () -> any AnimalAggregateWorkingOwnershipContractTestControl
    let transaction: CreateAnimalAggregateTransaction
}

/// Target-runner probe for one valid untagged aggregate create.
///
/// `transaction.tags` must be empty. In the final model tags are the sole source of display-tag
/// state, so an untagged aggregate must expose an empty display number and nil display color.
@MainActor
struct AnimalAggregateUntaggedCreateContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makeWorkingOwnershipControl: () -> any AnimalAggregateWorkingOwnershipContractTestControl
    let transaction: CreateAnimalAggregateTransaction
}

/// Target-runner probe for one materially complete aggregate update.
///
/// Fixture setup must prepare an existing tagged Animal plus any referenced parents/pastures/support
/// rows. `makeUpdateTransaction` must return a valid complete desired state that:
/// - changes editor-owned scalar state;
/// - changes status to `.active` and selects a different non-nil custom status reference;
/// - moves between two distinct non-nil Pastures;
/// - replaces one non-nil dam relationship with a different non-nil dam;
/// - clears an existing sire relationship by supplying nil;
/// - retires at least one previously active tag;
/// - edits the number or color payload of at least one previously persisted active tag that remains active;
/// - selects a different active primary tag; and
/// - creates at least one new tag application UUID; and
/// - changes at least one active dam's inferred-sire projection with this Animal as the prior or new sire.
///
/// This representative update exercises the aggregate-specific composition of fields, relationships,
/// tag reconciliation, retirement history, movement/status history, and inverse/read projections.
/// Equivalent individual field permutations remain owned by `AnimalRepositoryContract`.
@MainActor
struct AnimalAggregateUpdateContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makePastureRepository: () -> any PastureRepository
    let animalID: UUID
    let makeUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
}

/// Target-runner probe isolating an active-to-active Pasture move through the aggregate writer.
///
/// Fixture setup must prepare an active, unarchived Animal in one concrete Pasture and a distinct
/// concrete destination Pasture. The transaction must change only `pastureID`; all other editor
/// attributes and the complete tag state must remain unchanged. This proves source and destination
/// resident/stocking projections are repaired without relying on a simultaneous status transition.
@MainActor
struct AnimalAggregateActivePastureMoveContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makePastureRepository: () -> any PastureRepository
    let animalID: UUID
    let makeUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
}

/// Target-runner probe isolating a dam current-tag payload edit.
///
/// Fixture setup must prepare a female dam with an active primary tag and at least one visible
/// persisted offspring. The update transaction must preserve every editor attribute, every tag UUID,
/// and every active/primary flag while changing both the current primary tag number and color.
/// The dependent offspring ID identifies the child whose derived dam display and primary Birth
/// projection must refresh without rotating that child editor revision.
@MainActor
struct AnimalAggregateDamRetagContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let damID: UUID
    let offspringID: UUID
    let makeUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
}

/// Target-runner probe isolating same-base-status metadata replacement.
///
/// Fixture setup must prepare a .dead Animal with non-nil death date/cause and custom status
/// reference. makeUpdateTransaction must keep the base status .dead, preserve every other editor
/// attribute and the complete tag state, and change death date, cause, and custom status-reference
/// UUID. The update is a real editor-owned mutation but must not synthesize another status transition.
@MainActor
struct AnimalAggregateSameStatusMetadataContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let animalID: UUID
    let makeUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
}

/// Target-runner probe for the valid "currently untagged, retained retired history" aggregate state.
///
/// Fixture setup must begin with at least one active persisted tag. `makeUpdateTransaction` must keep
/// the exact preexisting tag UUID set and scalar/relationship attributes while marking every tag
/// inactive/non-primary. The Animal must be the inferred sire for at least one active dam, and its
/// tagged display must differ from the untagged fallback so the dependent sire display transition is
/// observable. This exercises retirement of the final active tag without deleting history.
@MainActor
struct AnimalAggregateAllTagsRetiredUpdateContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let animalID: UUID
    let makeUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
}

/// Persistence-neutral target-runner control for the live Working ownership relationship.
///
/// This is test-only contract infrastructure, not a production repository port. The Core Data runner
/// must resolve the persisted `Animal.activeWorkingSession` relationship by application UUID without
/// exposing managed objects, contexts, or storage-native identifiers.
@MainActor
protocol AnimalAggregateWorkingOwnershipContractTestControl {
    func activeWorkingSessionID(forAnimalID animalID: UUID) throws -> UUID?
}

/// Target-runner probe proving aggregate editor writes preserve Animal state they do not own.
///
/// Fixture setup must prepare an archived Animal currently owned by an active Working session
/// (`location == .workingPen`, no current Pasture), with a non-nil archive timestamp/reason plus at
/// least one persisted health record and one persisted pregnancy check. That Working session must
/// contain exactly one queue item for the Animal. The update transaction must materially change
/// editor-owned scalar or tag state without changing status/pasture so preservation of archive
/// metadata, the exact Working ownership relationship/session queue membership, and non-owned child
/// history is isolated from other history-producing writes. Reader/control factories used after the
/// write must provide fresh persistence access scopes.
@MainActor
struct AnimalAggregateNonOwnedStatePreservationContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let makeReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makeWorkingReader: () -> any WorkingSessionDetailReader
    let makeWorkingOwnershipControl: () -> any AnimalAggregateWorkingOwnershipContractTestControl
    let makeHealthControl: () -> any HealthRepositoryContractTestControl
    let animalID: UUID
    let makeUpdateTransaction: (
        _ current: AnimalAggregateEditSnapshot
    ) throws -> UpdateAnimalAggregateTransaction
}

/// Target-runner probe for aggregate tag-state validation.
///
/// The transaction must be otherwise valid and must fail only for `expectedFailure`. For
/// `.duplicateTagApplicationIDs`, repeating a tag UUID must be the sole intended invalid condition;
/// primary cardinality and inactive-primary rules must otherwise be valid so an unrelated validation
/// cannot satisfy the probe. `classifyError` must return nil for unrelated validation/lookup/implementation failures so those
/// errors cannot satisfy this contract. Complete-store snapshots must use fresh persistence scopes.
@MainActor
struct AnimalAggregateInvalidTagContractProbe {
    let writer: any AnimalAggregateTransactionWriting
    let operation: AnimalAggregateInvalidTagOperation
    let expectedFailure: AnimalAggregateTagValidationFailure
    let classifyError: (
        _ error: Error
    ) -> AnimalAggregateTagValidationFailure?
    let freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot
    let recoveryProbe: PersistenceTransactionRollbackRecoveryProbe
}

@MainActor
struct AnimalAggregateTransactionContractFixture {
    let makeTaggedCreateProbe: () throws -> AnimalAggregateTaggedCreateContractProbe
    let makeUntaggedCreateProbe: () throws -> AnimalAggregateUntaggedCreateContractProbe
    let makeUpdateProbe: () throws -> AnimalAggregateUpdateContractProbe
    let makeActivePastureMoveProbe: () throws -> AnimalAggregateActivePastureMoveContractProbe
    let makeDamRetagProbe: () throws -> AnimalAggregateDamRetagContractProbe
    let makeSameStatusMetadataProbe: () throws -> AnimalAggregateSameStatusMetadataContractProbe
    let makeAllTagsRetiredUpdateProbe: () throws -> AnimalAggregateAllTagsRetiredUpdateContractProbe
    let makeNonOwnedStatePreservationProbe: () throws -> AnimalAggregateNonOwnedStatePreservationContractProbe
    let makeInvalidTagProbe: (
        _ expectedFailure: AnimalAggregateTagValidationFailure,
        _ method: AnimalAggregateInvalidTagMethod
    ) throws -> AnimalAggregateInvalidTagContractProbe
}

/// Permanent persistence-neutral contract for the success and validation semantics unique to the
/// final Animal aggregate transaction port.
///
/// Fault-injected rollback is owned by `PersistenceTransactionRollbackContract`; revision rotation
/// and stale-editor rejection are owned by `PersistenceTransactionPreconditionContract`; mutation
/// publication is owned by `MutationBoundaryContract`.
@MainActor
enum AnimalAggregateTransactionContract {
    static func assertTaggedAndUntaggedCreatePersistCompleteAggregateState(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let taggedProbe = try fixture.makeTaggedCreateProbe()
        try assertValidTagState(
            taggedProbe.transaction.tags,
            requireAtLeastOneActiveTag: true,
            file: file,
            line: line
        )
        let taggedPastureID = try XCTUnwrap(
            taggedProbe.transaction.attributes.pastureID,
            "The representative tagged create must exercise initial Pasture relationship wiring.",
            file: file,
            line: line
        )
        let taggedDamID = try XCTUnwrap(
            taggedProbe.transaction.attributes.damID,
            "The representative tagged create must exercise initial dam relationship wiring.",
            file: file,
            line: line
        )
        _ = try XCTUnwrap(
            taggedProbe.transaction.attributes.sireID,
            "The representative tagged create must exercise initial sire relationship wiring.",
            file: file,
            line: line
        )
        let taggedStatusReferenceID = try XCTUnwrap(
            taggedProbe.transaction.attributes.statusReferenceID,
            "The representative tagged create must exercise initial custom status-reference wiring.",
            file: file,
            line: line
        )
        let taggedSireInferenceBefore = try activeDamSireInferenceSnapshots(
            repository: taggedProbe.makeAnimalRepository(),
            file: file,
            line: line
        )

        let taggedCreated = try taggedProbe.writer.createAnimal(taggedProbe.transaction)
        XCTAssertEqual(taggedCreated.animal.id, taggedProbe.transaction.animalID, file: file, line: line)
        try assertNewAggregateDefaults(
            detail: taggedCreated.animal,
            workingOwnershipControl: taggedProbe.makeWorkingOwnershipControl(),
            file: file,
            line: line
        )
        assertAttributes(
            taggedCreated.animal,
            match: taggedProbe.transaction.attributes,
            file: file,
            line: line
        )
        assertTags(
            taggedCreated.animal,
            match: taggedProbe.transaction.tags,
            preservingHistoryByID: [:],
            file: file,
            line: line
        )
        let taggedStatusReference = try XCTUnwrap(
            taggedProbe.makeAnimalRepository()
                .fetchStatusReferenceOptions()
                .first { $0.id == taggedStatusReferenceID },
            "The representative aggregate create must resolve the selected custom status reference.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            taggedCreated.animal.statusReferenceName,
            taggedStatusReference.name,
            "Aggregate create must expose the selected status-reference display name through Animal detail projection.",
            file: file,
            line: line
        )
        try assertCreateTimelineProjection(
            detail: taggedCreated.animal,
            repository: taggedProbe.makeAnimalRepository(),
            expectedTags: taggedCreated.animal.activeTags + taggedCreated.animal.inactiveTags,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(
                taggedProbe.makeReader().fetchAnimalAggregateForEditing(id: taggedProbe.transaction.animalID),
                file: file,
                line: line
            ),
            taggedCreated,
            "A fresh editor reader must observe the exact tagged aggregate and revision returned by create.",
            file: file,
            line: line
        )
        try await assertFreshAnimalReadProjections(
            detail: taggedCreated.animal,
            repository: taggedProbe.makeAnimalRepository(),
            listQueryReader: taggedProbe.makeAnimalListQueryReader(),
            dashboardQueryReader: taggedProbe.makeDashboardQueryReader(),
            preservingSummaryOnlyFieldsFrom: nil,
            preservingDashboardOnlyFieldsFrom: nil,
            file: file,
            line: line
        )
        let taggedProjectionRepository = taggedProbe.makeAnimalRepository()
        let taggedSireInferenceAfter = try activeDamSireInferenceSnapshots(
            repository: taggedProjectionRepository,
            file: file,
            line: line
        )
        let taggedCreatedParentDisplay = try XCTUnwrap(
            taggedProjectionRepository
                .fetchParentOptions(excluding: nil)
                .first { $0.id == taggedCreated.animal.id },
            file: file,
            line: line
        ).displayName
        XCTAssertTrue(
            taggedSireInferenceAfter.contains { damID, after in
                taggedSireInferenceBefore[damID] != after
                    && after.inferredSireID == taggedCreated.animal.id
                    && after.inferredSireDisplayName == taggedCreatedParentDisplay
            },
            "The representative tagged create must make the new Animal the inferred sire for at least one preexisting active dam so cross-Animal Add Offspring inference is exercised.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try taggedProbe.makePastureRepository()
                .fetchResidentAnimals(pastureID: taggedPastureID)
                .contains { $0.id == taggedProbe.transaction.animalID },
            "Aggregate create must add the new Animal to the selected Pasture resident projection.",
            file: file,
            line: line
        )
        try await assertPastureCountProjectionsMatchResidents(
            pastureID: taggedPastureID,
            dashboardReader: taggedProbe.makeDashboardQueryReader(),
            pastureRepository: taggedProbe.makePastureRepository(),
            file: file,
            line: line
        )
        let taggedDam = try XCTUnwrap(
            taggedProbe.makeAnimalRepository().fetchAnimalDetail(id: taggedDamID),
            file: file,
            line: line
        )
        XCTAssertTrue(
            taggedDam.maternalOffspring.contains { $0.id == taggedProbe.transaction.animalID },
            "Aggregate create must update the dam inverse offspring projection.",
            file: file,
            line: line
        )

        let untaggedProbe = try fixture.makeUntaggedCreateProbe()
        XCTAssertTrue(
            untaggedProbe.transaction.tags.isEmpty,
            "The untagged create fixture must contain no tag state.",
            file: file,
            line: line
        )

        let untaggedCreated = try untaggedProbe.writer.createAnimal(untaggedProbe.transaction)
        XCTAssertEqual(untaggedCreated.animal.id, untaggedProbe.transaction.animalID, file: file, line: line)
        try assertNewAggregateDefaults(
            detail: untaggedCreated.animal,
            workingOwnershipControl: untaggedProbe.makeWorkingOwnershipControl(),
            file: file,
            line: line
        )
        assertAttributes(
            untaggedCreated.animal,
            match: untaggedProbe.transaction.attributes,
            file: file,
            line: line
        )
        XCTAssertTrue(untaggedCreated.animal.activeTags.isEmpty, file: file, line: line)
        XCTAssertTrue(untaggedCreated.animal.inactiveTags.isEmpty, file: file, line: line)
        XCTAssertTrue(
            untaggedCreated.animal.displayTagNumber.isEmpty,
            "An untagged final aggregate must not synthesize or persist a scalar fallback tag number.",
            file: file,
            line: line
        )
        XCTAssertNil(
            untaggedCreated.animal.displayTagColorID,
            "An untagged final aggregate must not retain a scalar fallback tag color.",
            file: file,
            line: line
        )
        try assertCreateTimelineProjection(
            detail: untaggedCreated.animal,
            repository: untaggedProbe.makeAnimalRepository(),
            expectedTags: [],
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(
                untaggedProbe.makeReader().fetchAnimalAggregateForEditing(id: untaggedProbe.transaction.animalID),
                file: file,
                line: line
            ),
            untaggedCreated,
            "A fresh editor reader must observe the exact untagged aggregate and revision returned by create.",
            file: file,
            line: line
        )
        try await assertFreshAnimalReadProjections(
            detail: untaggedCreated.animal,
            repository: untaggedProbe.makeAnimalRepository(),
            listQueryReader: untaggedProbe.makeAnimalListQueryReader(),
            dashboardQueryReader: untaggedProbe.makeDashboardQueryReader(),
            preservingSummaryOnlyFieldsFrom: nil,
            preservingDashboardOnlyFieldsFrom: nil,
            file: file,
            line: line
        )
    }

    static func assertCompleteUpdateReconcilesRelationshipsTagsAndHistory(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeUpdateProbe()
        let current = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            "The aggregate update fixture must prepare an existing Animal.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            current.animal.isArchived,
            "The representative complete aggregate update must begin with an unarchived Animal so parent-option and Add Offspring projections are observable.",
            file: file,
            line: line
        )
        let summaryBefore = try fetchAnimalSummary(
            id: probe.animalID,
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        let dashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.animalID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        let sireInferenceBefore = try activeDamSireInferenceSnapshots(
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        let beforeTags = current.animal.activeTags + current.animal.inactiveTags
        let beforeTagGroups = Dictionary(grouping: beforeTags, by: \.id)
        XCTAssertTrue(
            beforeTagGroups.values.allSatisfy { $0.count == 1 },
            "The prepared aggregate must not contain duplicate tag application UUIDs.",
            file: file,
            line: line
        )
        let beforeTagsByID = beforeTagGroups.compactMapValues { $0.first }
        let beforeTagIDs = Set(beforeTagsByID.keys)
        let beforePrimaryID = current.animal.activeTags.first(where: { $0.isPrimary })?.id
        XCTAssertNotNil(
            beforePrimaryID,
            "The representative aggregate update must begin with a tagged Animal and an active primary tag.",
            file: file,
            line: line
        )
        let beforeTimeline = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)

        let transaction = try probe.makeUpdateTransaction(current)
        XCTAssertEqual(transaction.animalID, current.animal.id, file: file, line: line)
        XCTAssertEqual(transaction.expectedRevision, current.revision, file: file, line: line)
        try assertValidTagState(
            transaction.tags,
            requireAtLeastOneActiveTag: true,
            file: file,
            line: line
        )

        XCTAssertTrue(
            attributesDiffer(transaction.attributes, from: current.animal),
            "The aggregate update fixture must materially change editor-owned scalar/relationship state.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            transaction.attributes.status,
            current.animal.status,
            "The representative aggregate update must change status so status-history behavior is exercised.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            transaction.attributes.status,
            .active,
            "The representative aggregate update must end active so destination resident and active Dashboard projections are exercised.",
            file: file,
            line: line
        )
        let updatedStatusReferenceID = try XCTUnwrap(
            transaction.attributes.statusReferenceID,
            "The representative aggregate update must select a custom status reference.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            updatedStatusReferenceID,
            current.animal.statusReferenceID,
            "The representative aggregate update must change the status-reference relationship.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            transaction.attributes.pastureID,
            current.animal.pastureID,
            "The representative aggregate update must change pasture so movement-history behavior is exercised.",
            file: file,
            line: line
        )
        let oldPastureID = try XCTUnwrap(
            current.animal.pastureID,
            "The representative complete update must begin in a concrete Pasture so source projection repair is exercised.",
            file: file,
            line: line
        )
        let newPastureID = try XCTUnwrap(
            transaction.attributes.pastureID,
            "The representative complete update must move to a concrete destination Pasture so destination projection repair is exercised.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(oldPastureID, newPastureID, file: file, line: line)
        let oldDamID = try XCTUnwrap(
            current.animal.damID,
            "The representative complete update must begin with an existing dam so inverse removal is exercised.",
            file: file,
            line: line
        )
        let newDamID = try XCTUnwrap(
            transaction.attributes.damID,
            "The representative complete update must select a new dam so inverse addition is exercised.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            oldDamID,
            newDamID,
            "The representative aggregate update must replace the dam relationship with a different Animal.",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            current.animal.sireID,
            "The representative aggregate update must begin with an existing sire relationship so optional clearing is exercised.",
            file: file,
            line: line
        )
        XCTAssertNil(
            transaction.attributes.sireID,
            "Complete aggregate replacement must exercise clearing an existing sire relationship by supplying nil.",
            file: file,
            line: line
        )

        let desiredTagGroups = Dictionary(grouping: transaction.tags, by: \.id)
        XCTAssertTrue(
            desiredTagGroups.values.allSatisfy { $0.count == 1 },
            "A valid complete desired tag state must not repeat an application UUID.",
            file: file,
            line: line
        )
        let desiredByID = desiredTagGroups.compactMapValues { $0.first }
        XCTAssertTrue(
            beforeTagIDs.isSubset(of: Set(desiredByID.keys)),
            "Complete desired tag state must carry every previously persisted tag UUID forward; persisted tags retire in place rather than disappearing.",
            file: file,
            line: line
        )
        let desiredPrimaryID = transaction.tags.first(where: { $0.isActive && $0.isPrimary })?.id
        XCTAssertNotEqual(
            desiredPrimaryID,
            beforePrimaryID,
            "The representative aggregate update must replace/promote a different primary tag.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            beforeTags.contains { prior in
                prior.isActive && desiredByID[prior.id]?.isActive == false
            },
            "The representative aggregate update must retire at least one previously active tag.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            beforeTags.contains { prior in
                guard prior.isActive, let desired = desiredByID[prior.id], desired.isActive else {
                    return false
                }
                return desired.number != prior.number || desired.colorID != prior.colorID
            },
            "The representative aggregate update must edit number or color payload on at least one existing active tag UUID.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            Set(transaction.tags.map(\.id)).subtracting(beforeTagIDs).isEmpty,
            "The representative aggregate update must create at least one new tag application UUID.",
            file: file,
            line: line
        )

        let updated = try probe.writer.updateAnimal(transaction)
        XCTAssertEqual(updated.animal.id, current.animal.id, file: file, line: line)
        XCTAssertNotEqual(updated.revision, current.revision, file: file, line: line)
        assertAttributes(updated.animal, match: transaction.attributes, file: file, line: line)
        assertTags(
            updated.animal,
            match: transaction.tags,
            preservingHistoryByID: beforeTagsByID,
            file: file,
            line: line
        )
        let updatedStatusReference = try XCTUnwrap(
            probe.makeAnimalRepository()
                .fetchStatusReferenceOptions()
                .first { $0.id == updatedStatusReferenceID },
            "The representative aggregate update must resolve its selected custom status reference.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            updated.animal.statusReferenceName,
            updatedStatusReference.name,
            "Aggregate update must expose the changed status-reference display name through Animal detail projection.",
            file: file,
            line: line
        )

        let reloaded = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded,
            updated,
            "A fresh editor reader must observe the exact complete aggregate state/revision returned by update.",
            file: file,
            line: line
        )
        try await assertFreshAnimalReadProjections(
            detail: reloaded.animal,
            repository: probe.makeAnimalRepository(),
            listQueryReader: probe.makeAnimalListQueryReader(),
            dashboardQueryReader: probe.makeDashboardQueryReader(),
            preservingSummaryOnlyFieldsFrom: summaryBefore,
            preservingDashboardOnlyFieldsFrom: dashboardBefore,
            file: file,
            line: line
        )
        let updatedProjectionRepository = probe.makeAnimalRepository()
        let sireInferenceAfter = try activeDamSireInferenceSnapshots(
            repository: updatedProjectionRepository,
            file: file,
            line: line
        )
        let updatedParentDisplay = try XCTUnwrap(
            updatedProjectionRepository
                .fetchParentOptions(excluding: nil)
                .first { $0.id == probe.animalID },
            file: file,
            line: line
        ).displayName
        let sireInferenceDamIDs = Set(sireInferenceBefore.keys).union(sireInferenceAfter.keys)
        XCTAssertTrue(
            sireInferenceDamIDs.contains { damID in
                let before = sireInferenceBefore[damID]
                let after = sireInferenceAfter[damID]
                guard before != after else { return false }
                if after?.inferredSireID == probe.animalID {
                    return after?.inferredSireDisplayName == updatedParentDisplay
                }
                return before?.inferredSireID == probe.animalID
            },
            "The representative complete update must materially change at least one active dam's inferred-sire projection with the edited Animal as the prior or new inferred sire.",
            file: file,
            line: line
        )

        let afterTimeline = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)
        XCTAssertEqual(
            timelineCount(.status, in: afterTimeline),
            timelineCount(.status, in: beforeTimeline) + 1,
            "A status-changing aggregate update must append exactly one durable status-history event.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            timelineCount(.movement, in: afterTimeline),
            timelineCount(.movement, in: beforeTimeline) + 1,
            "A pasture-changing aggregate update must append exactly one durable movement-history event.",
            file: file,
            line: line
        )
        assertExactlyOneTimelineEventAdded(
            kind: .status,
            before: beforeTimeline,
            after: afterTimeline,
            expectedTitle: "Status Change",
            expectedDetails: "\(current.animal.status.label) → \(transaction.attributes.status.label)",
            message: "The newly appended aggregate status-history event must encode the exact before-to-after status transition.",
            file: file,
            line: line
        )
        assertExactlyOneTimelineEventAdded(
            kind: .movement,
            before: beforeTimeline,
            after: afterTimeline,
            expectedTitle: "Pasture Movement",
            expectedDetails: "\(current.animal.pastureName ?? "—") → \(updated.animal.pastureName ?? "—")",
            message: "The newly appended aggregate movement-history event must encode the exact source and destination Pasture names.",
            file: file,
            line: line
        )

        let reloadedTags = reloaded.animal.activeTags + reloaded.animal.inactiveTags
        var expectedTagTimeline: [TimelineSignature] = []
        for tag in reloadedTags {
            expectedTagTimeline.append(
                TimelineSignature(
                    kind: .tag,
                    date: tag.assignedAt,
                    title: "Tag Assigned",
                    details: tag.normalizedNumber
                )
            )
            if let removedAt = tag.removedAt {
                expectedTagTimeline.append(
                    TimelineSignature(
                        kind: .tag,
                        date: removedAt,
                        title: "Tag Retired",
                        details: tag.normalizedNumber
                    )
                )
            }
        }
        XCTAssertEqual(
            multisetCounts(timelineSignatures(.tag, in: afterTimeline)),
            multisetCounts(expectedTagTimeline),
            "The aggregate tag timeline must exactly match persisted tag assignment/retirement chronology, including duplicate payloads and timestamps.",
            file: file,
            line: line
        )

        let oldDam = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: oldDamID),
            file: file,
            line: line
        )
        XCTAssertFalse(
            oldDam.maternalOffspring.contains { $0.id == probe.animalID },
            "Changing dam through the aggregate transaction must remove the child from the prior dam inverse.",
            file: file,
            line: line
        )
        let newDam = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: newDamID),
            file: file,
            line: line
        )
        XCTAssertTrue(
            newDam.maternalOffspring.contains { $0.id == probe.animalID },
            "Changing dam through the aggregate transaction must add the child to the new dam inverse.",
            file: file,
            line: line
        )

        XCTAssertFalse(
            try probe.makePastureRepository()
                .fetchResidentAnimals(pastureID: oldPastureID)
                .contains { $0.id == probe.animalID },
            "Changing pasture through the aggregate transaction must remove the Animal from the prior resident projection.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            try probe.makePastureRepository()
                .fetchResidentAnimals(pastureID: newPastureID)
                .contains { $0.id == probe.animalID },
            "Changing pasture through the aggregate transaction must add the Animal to the new resident projection when it remains active in herd.",
            file: file,
            line: line
        )
        try await assertPastureCountProjectionsMatchResidents(
            pastureID: oldPastureID,
            dashboardReader: probe.makeDashboardQueryReader(),
            pastureRepository: probe.makePastureRepository(),
            file: file,
            line: line
        )
        try await assertPastureCountProjectionsMatchResidents(
            pastureID: newPastureID,
            dashboardReader: probe.makeDashboardQueryReader(),
            pastureRepository: probe.makePastureRepository(),
            file: file,
            line: line
        )
    }

    static func assertActivePastureMoveRepairsSourceAndDestinationProjections(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeActivePastureMoveProbe()
        let current = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            "The active Pasture-move fixture must prepare an existing Animal.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            current.animal.status,
            .active,
            "The focused Pasture-move fixture must begin active so source and destination stocking counts both change.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            current.animal.isArchived,
            "The focused Pasture-move fixture must begin unarchived.",
            file: file,
            line: line
        )
        let oldPastureID = try XCTUnwrap(
            current.animal.pastureID,
            "The focused Pasture-move fixture must begin in a concrete source Pasture.",
            file: file,
            line: line
        )
        let beforeTimeline = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)
        let sourceResidentsBefore = try probe.makePastureRepository()
            .fetchResidentAnimals(pastureID: oldPastureID)
        XCTAssertTrue(
            sourceResidentsBefore.contains { $0.id == probe.animalID },
            "The active Animal must be present in the source resident projection before the move.",
            file: file,
            line: line
        )

        let transaction = try probe.makeUpdateTransaction(current)
        XCTAssertEqual(transaction.animalID, current.animal.id, file: file, line: line)
        XCTAssertEqual(transaction.expectedRevision, current.revision, file: file, line: line)
        let newPastureID = try XCTUnwrap(
            transaction.attributes.pastureID,
            "The focused Pasture move must target a concrete destination Pasture.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(oldPastureID, newPastureID, file: file, line: line)
        assertOnlyPastureDiffers(
            transaction.attributes,
            from: current.animal,
            file: file,
            line: line
        )
        XCTAssertFalse(
            tagTransactionStateDiffers(transaction.tags, from: current.animal),
            "The focused Pasture move must preserve complete tag state.",
            file: file,
            line: line
        )

        let destinationResidentsBefore = try probe.makePastureRepository()
            .fetchResidentAnimals(pastureID: newPastureID)
        XCTAssertFalse(
            destinationResidentsBefore.contains { $0.id == probe.animalID },
            "The Animal must not already be present in the destination resident projection.",
            file: file,
            line: line
        )
        try await assertPastureCountProjectionsMatchResidents(
            pastureID: oldPastureID,
            dashboardReader: probe.makeDashboardQueryReader(),
            pastureRepository: probe.makePastureRepository(),
            file: file,
            line: line
        )
        try await assertPastureCountProjectionsMatchResidents(
            pastureID: newPastureID,
            dashboardReader: probe.makeDashboardQueryReader(),
            pastureRepository: probe.makePastureRepository(),
            file: file,
            line: line
        )

        let updated = try probe.writer.updateAnimal(transaction)
        XCTAssertEqual(updated.animal.id, current.animal.id, file: file, line: line)
        XCTAssertNotEqual(
            updated.revision,
            current.revision,
            "An active Pasture move is editor-owned state and must rotate the aggregate revision.",
            file: file,
            line: line
        )
        assertAttributes(updated.animal, match: transaction.attributes, file: file, line: line)
        let priorTags = current.animal.activeTags + current.animal.inactiveTags
        let priorTagGroups = Dictionary(grouping: priorTags, by: \.id)
        XCTAssertTrue(
            priorTagGroups.values.allSatisfy { $0.count == 1 },
            "The focused Pasture-move fixture must not contain duplicate tag application UUIDs.",
            file: file,
            line: line
        )
        assertTags(
            updated.animal,
            match: transaction.tags,
            preservingHistoryByID: priorTagGroups.compactMapValues { $0.first },
            file: file,
            line: line
        )

        let reloaded = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded, updated, file: file, line: line)

        let sourceResidentsAfter = try probe.makePastureRepository()
            .fetchResidentAnimals(pastureID: oldPastureID)
        let destinationResidentsAfter = try probe.makePastureRepository()
            .fetchResidentAnimals(pastureID: newPastureID)
        XCTAssertFalse(
            sourceResidentsAfter.contains { $0.id == probe.animalID },
            "The committed active move must remove the Animal from the source resident projection.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            destinationResidentsAfter.contains { $0.id == probe.animalID },
            "The committed active move must add the Animal to the destination resident projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            sourceResidentsAfter.count,
            sourceResidentsBefore.count - 1,
            "The active source Pasture must lose exactly one resident.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            destinationResidentsAfter.count,
            destinationResidentsBefore.count + 1,
            "The active destination Pasture must gain exactly one resident.",
            file: file,
            line: line
        )
        try await assertPastureCountProjectionsMatchResidents(
            pastureID: oldPastureID,
            dashboardReader: probe.makeDashboardQueryReader(),
            pastureRepository: probe.makePastureRepository(),
            file: file,
            line: line
        )
        try await assertPastureCountProjectionsMatchResidents(
            pastureID: newPastureID,
            dashboardReader: probe.makeDashboardQueryReader(),
            pastureRepository: probe.makePastureRepository(),
            file: file,
            line: line
        )

        let afterTimeline = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)
        XCTAssertEqual(
            multisetCounts(timelineSignatures(.status, in: afterTimeline)),
            multisetCounts(timelineSignatures(.status, in: beforeTimeline)),
            "A Pasture-only aggregate move must not add, remove, or rewrite status history.",
            file: file,
            line: line
        )
        assertExactlyOneTimelineEventAdded(
            kind: .movement,
            before: beforeTimeline,
            after: afterTimeline,
            expectedTitle: "Pasture Movement",
            expectedDetails: "\(current.animal.pastureName ?? "—") → \(updated.animal.pastureName ?? "—")",
            message: "The focused active move must append exactly one source-to-destination movement event.",
            file: file,
            line: line
        )
    }

    static func assertDamRetagRefreshesDependentOffspringProjections(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeDamRetagProbe()
        let current = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.damID),
            "The dam-retag fixture must prepare an existing dam aggregate.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            current.animal.sex,
            .female,
            "The focused parent-display probe must mutate a female dam.",
            file: file,
            line: line
        )
        XCTAssertFalse(current.animal.isArchived, file: file, line: line)
        XCTAssertTrue(
            current.animal.maternalOffspring.contains { $0.id == probe.offspringID },
            "The dam-retag fixture must expose the dependent offspring through the dam inverse projection.",
            file: file,
            line: line
        )

        let currentTags = current.animal.activeTags + current.animal.inactiveTags
        let currentTagGroups = Dictionary(grouping: currentTags, by: \.id)
        XCTAssertTrue(
            currentTagGroups.values.allSatisfy { $0.count == 1 },
            "The dam-retag fixture must not contain duplicate tag application UUIDs.",
            file: file,
            line: line
        )
        let currentTagsByID = currentTagGroups.compactMapValues { $0.first }
        XCTAssertEqual(
            current.animal.activeTags.filter { $0.isPrimary }.count,
            1,
            "The dam-retag fixture must begin with exactly one active primary tag.",
            file: file,
            line: line
        )
        let currentPrimary = try XCTUnwrap(
            current.animal.activeTags.first { $0.isPrimary },
            file: file,
            line: line
        )
        XCTAssertFalse(
            current.animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "The focused dam-retag fixture must begin with a visible current tag number.",
            file: file,
            line: line
        )

        let childAggregateBefore = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            "The dependent offspring aggregate must be readable before the dam retag.",
            file: file,
            line: line
        )
        XCTAssertEqual(childAggregateBefore.animal.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(
            childAggregateBefore.animal.dam,
            current.animal.displayTagNumber,
            "Child detail must begin by resolving the dam current tag display.",
            file: file,
            line: line
        )
        let childSummaryBefore = try fetchAnimalSummary(
            id: probe.offspringID,
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            childSummaryBefore.damDisplayTagNumber,
            AnimalDisplayTagFormatter.displayTagNumber(from: current.animal.displayTagNumber),
            file: file,
            line: line
        )
        XCTAssertEqual(
            childSummaryBefore.damDisplayTagColorID,
            current.animal.displayTagColorID,
            file: file,
            line: line
        )
        let childPagedBefore = try await fetchAnimalListQuerySummary(
            id: probe.offspringID,
            reader: probe.makeAnimalListQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(childPagedBefore, childSummaryBefore, file: file, line: line)
        let childDashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.offspringID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            childDashboardBefore.damDisplayTagNumber,
            childSummaryBefore.damDisplayTagNumber,
            file: file,
            line: line
        )
        XCTAssertEqual(
            childDashboardBefore.damDisplayTagColorID,
            childSummaryBefore.damDisplayTagColorID,
            file: file,
            line: line
        )
        let childTimelineBefore = try probe.makeAnimalRepository().fetchTimeline(id: probe.offspringID)
        let primaryBirthBefore = try primaryBirthSignature(
            detail: childAggregateBefore.animal,
            repository: probe.makeAnimalRepository(),
            timeline: childTimelineBefore,
            file: file,
            line: line
        )

        let transaction = try probe.makeUpdateTransaction(current)
        XCTAssertEqual(transaction.animalID, probe.damID, file: file, line: line)
        XCTAssertEqual(transaction.expectedRevision, current.revision, file: file, line: line)
        XCTAssertFalse(
            attributesDiffer(transaction.attributes, from: current.animal),
            "The focused dam-retag transaction must preserve every editor-owned non-tag attribute.",
            file: file,
            line: line
        )
        try assertValidTagState(
            transaction.tags,
            requireAtLeastOneActiveTag: true,
            file: file,
            line: line
        )
        let desiredTagGroups = Dictionary(grouping: transaction.tags, by: \.id)
        XCTAssertTrue(
            desiredTagGroups.values.allSatisfy { $0.count == 1 },
            "The focused dam-retag transaction must not duplicate tag application UUIDs.",
            file: file,
            line: line
        )
        let desiredTagsByID = desiredTagGroups.compactMapValues { $0.first }
        XCTAssertEqual(Set(desiredTagsByID.keys), Set(currentTagsByID.keys), file: file, line: line)

        for (tagID, before) in currentTagsByID {
            let desired = try XCTUnwrap(desiredTagsByID[tagID], file: file, line: line)
            XCTAssertEqual(desired.isActive, before.isActive, file: file, line: line)
            XCTAssertEqual(desired.isPrimary, before.isPrimary, file: file, line: line)
            if tagID != currentPrimary.id {
                XCTAssertEqual(desired.number, before.number, file: file, line: line)
                XCTAssertEqual(desired.colorID, before.colorID, file: file, line: line)
            }
        }

        let desiredPrimary = try XCTUnwrap(
            desiredTagsByID[currentPrimary.id],
            "The focused dam-retag transaction must preserve the primary tag UUID.",
            file: file,
            line: line
        )
        XCTAssertTrue(desiredPrimary.isActive, file: file, line: line)
        XCTAssertTrue(desiredPrimary.isPrimary, file: file, line: line)
        let desiredPrimaryNumber = desiredPrimary.number.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(
            desiredPrimaryNumber.isEmpty,
            "The focused dam-retag transaction must keep a visible current tag number.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            desiredPrimaryNumber,
            current.animal.displayTagNumber,
            "The focused dam-retag transaction must materially change the current tag number so dependent text projections are exercised.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            desiredPrimary.colorID,
            current.animal.displayTagColorID,
            "The focused dam-retag transaction must materially change the current tag color so dependent color projections are exercised.",
            file: file,
            line: line
        )

        let updated = try probe.writer.updateAnimal(transaction)
        XCTAssertEqual(updated.animal.id, probe.damID, file: file, line: line)
        XCTAssertNotEqual(
            updated.revision,
            current.revision,
            "Changing the dam current tag must rotate the dam aggregate revision.",
            file: file,
            line: line
        )
        assertAttributes(updated.animal, match: transaction.attributes, file: file, line: line)
        assertTags(
            updated.animal,
            match: transaction.tags,
            preservingHistoryByID: currentTagsByID,
            file: file,
            line: line
        )

        let reloadedDam = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedDam, updated, file: file, line: line)
        let nestedOffspringAfter = try XCTUnwrap(
            reloadedDam.animal.maternalOffspring.first { $0.id == probe.offspringID },
            "The dam detail must continue exposing the dependent offspring after retagging.",
            file: file,
            line: line
        )

        let childAggregateAfter = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            "The dependent offspring aggregate must remain readable after the dam retag.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            childAggregateAfter.revision,
            childAggregateBefore.revision,
            "A derived parent-display refresh must not rotate the child aggregate revision.",
            file: file,
            line: line
        )
        assertAnimalDetailUnchangedExceptDamDisplay(
            before: childAggregateBefore.animal,
            after: childAggregateAfter.animal,
            file: file,
            line: line
        )
        XCTAssertEqual(childAggregateAfter.animal.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(
            childAggregateAfter.animal.dam,
            reloadedDam.animal.displayTagNumber,
            "Child detail must resolve the dam new current tag display.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            childAggregateAfter.animal.dam,
            childAggregateBefore.animal.dam,
            "The focused dam retag must visibly change the child derived dam display.",
            file: file,
            line: line
        )

        let childSummaryAfter = try fetchAnimalSummary(
            id: probe.offspringID,
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        assertAnimalSummaryUnchangedExceptDamDisplay(
            before: childSummaryBefore,
            after: childSummaryAfter,
            file: file,
            line: line
        )
        XCTAssertEqual(
            childSummaryAfter.damDisplayTagNumber,
            AnimalDisplayTagFormatter.displayTagNumber(from: reloadedDam.animal.displayTagNumber),
            file: file,
            line: line
        )
        XCTAssertEqual(
            childSummaryAfter.damDisplayTagColorID,
            reloadedDam.animal.displayTagColorID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            nestedOffspringAfter,
            childSummaryAfter,
            "The dam detail nested offspring summary must expose the same refreshed parent display as the standalone Animal summary.",
            file: file,
            line: line
        )

        let childPagedAfter = try await fetchAnimalListQuerySummary(
            id: probe.offspringID,
            reader: probe.makeAnimalListQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            childPagedAfter,
            childSummaryAfter,
            "The production paged Animal list must expose the same refreshed dam display as the synchronous summary.",
            file: file,
            line: line
        )

        let childDashboardAfter = try await fetchDashboardAnimalRecord(
            id: probe.offspringID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        assertDashboardAnimalRecordUnchangedExceptDamDisplay(
            before: childDashboardBefore,
            after: childDashboardAfter,
            file: file,
            line: line
        )
        XCTAssertEqual(childDashboardAfter.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(
            childDashboardAfter.damDisplayTagNumber,
            childSummaryAfter.damDisplayTagNumber,
            file: file,
            line: line
        )
        XCTAssertEqual(
            childDashboardAfter.damDisplayTagColorID,
            childSummaryAfter.damDisplayTagColorID,
            file: file,
            line: line
        )

        let childTimelineAfter = try probe.makeAnimalRepository().fetchTimeline(id: probe.offspringID)
        XCTAssertEqual(
            multisetCounts(timelineWithoutPrimaryBirth(childTimelineAfter, birthDate: childAggregateAfter.animal.birthDate)),
            multisetCounts(timelineWithoutPrimaryBirth(childTimelineBefore, birthDate: childAggregateBefore.animal.birthDate)),
            "Retagging the dam must not add, remove, or rewrite any child timeline entry other than the derived primary Birth projection.",
            file: file,
            line: line
        )
        let primaryBirthAfter = try primaryBirthSignature(
            detail: childAggregateAfter.animal,
            repository: probe.makeAnimalRepository(),
            timeline: childTimelineAfter,
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            primaryBirthAfter.details,
            primaryBirthBefore.details,
            "The child derived primary Birth projection must refresh when the dam displayed tag changes.",
            file: file,
            line: line
        )
    }

    static func assertSameStatusMetadataUpdateDoesNotAppendStatusHistory(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeSameStatusMetadataProbe()
        let current = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            "The same-status metadata fixture must prepare an existing Animal.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            current.animal.status,
            .dead,
            "The same-status metadata probe must begin with a deceased Animal.",
            file: file,
            line: line
        )
        XCTAssertNotNil(current.animal.deathDate, file: file, line: line)
        XCTAssertNotNil(current.animal.causeOfDeath, file: file, line: line)
        XCTAssertNotNil(current.animal.statusReferenceID, file: file, line: line)

        let beforeTags = current.animal.activeTags + current.animal.inactiveTags
        let beforeTagGroups = Dictionary(grouping: beforeTags, by: \.id)
        XCTAssertTrue(
            beforeTagGroups.values.allSatisfy { $0.count == 1 },
            "The same-status metadata fixture must not contain duplicate tag application UUIDs.",
            file: file,
            line: line
        )
        let beforeTagsByID = beforeTagGroups.compactMapValues { $0.first }

        let summaryBefore = try fetchAnimalSummary(
            id: probe.animalID,
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        let pagedBefore = try await fetchAnimalListQuerySummary(
            id: probe.animalID,
            reader: probe.makeAnimalListQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(pagedBefore, summaryBefore, file: file, line: line)
        let dashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.animalID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        let timelineBefore = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)

        let transaction = try probe.makeUpdateTransaction(current)
        XCTAssertEqual(transaction.animalID, probe.animalID, file: file, line: line)
        XCTAssertEqual(transaction.expectedRevision, current.revision, file: file, line: line)
        try assertOnlySameStatusMetadataDiffers(
            transaction.attributes,
            from: current.animal,
            file: file,
            line: line
        )
        XCTAssertFalse(
            tagTransactionStateDiffers(transaction.tags, from: current.animal),
            "The same-status metadata probe must preserve complete tag state.",
            file: file,
            line: line
        )
        let newStatusReferenceID = try XCTUnwrap(
            transaction.attributes.statusReferenceID,
            "The same-status metadata probe must select a replacement custom status reference.",
            file: file,
            line: line
        )

        let updated = try probe.writer.updateAnimal(transaction)
        XCTAssertEqual(updated.animal.id, current.animal.id, file: file, line: line)
        XCTAssertNotEqual(
            updated.revision,
            current.revision,
            "Changing editor-owned death/status-reference metadata must rotate the aggregate revision.",
            file: file,
            line: line
        )
        assertAttributes(updated.animal, match: transaction.attributes, file: file, line: line)
        assertTags(
            updated.animal,
            match: transaction.tags,
            preservingHistoryByID: beforeTagsByID,
            file: file,
            line: line
        )

        let reloaded = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded,
            updated,
            "A fresh editor read must expose the same-status metadata replacement and rotated revision.",
            file: file,
            line: line
        )

        let statusReferenceRepository = probe.makeAnimalRepository()
        let replacementReference = try XCTUnwrap(
            statusReferenceRepository
                .fetchStatusReferenceOptions()
                .first { $0.id == newStatusReferenceID },
            "The replacement custom status reference must remain resolvable after the aggregate update.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded.animal.statusReferenceName,
            replacementReference.name,
            "Same-status metadata replacement must refresh the custom status-reference display name.",
            file: file,
            line: line
        )

        let summaryAfter = try fetchAnimalSummary(
            id: probe.animalID,
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            summaryAfter,
            summaryBefore,
            "Death/status-reference metadata not represented by AnimalSummary must not disturb the summary projection.",
            file: file,
            line: line
        )
        let pagedSummaryAfterMetadataUpdate = try await fetchAnimalListQuerySummary(
            id: probe.animalID,
            reader: probe.makeAnimalListQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            pagedSummaryAfterMetadataUpdate,
            summaryAfter,
            "The production paged Animal list must remain coherent after same-status metadata replacement.",
            file: file,
            line: line
        )

        let dashboardAfter = try await fetchDashboardAnimalRecord(
            id: probe.animalID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        assertDashboardAnimalRecordUnchangedExceptDeathDate(
            before: dashboardBefore,
            after: dashboardAfter,
            file: file,
            line: line
        )
        XCTAssertEqual(
            dashboardAfter.deathDate,
            transaction.attributes.deathDate,
            "Dashboard must expose the replacement death date after the aggregate update.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            dashboardAfter.deathDate,
            dashboardBefore.deathDate,
            "The focused same-status metadata fixture must materially change the Dashboard death-date projection.",
            file: file,
            line: line
        )

        let timelineAfter = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)
        XCTAssertEqual(
            multisetCounts(allTimelineSignatures(timelineAfter)),
            multisetCounts(allTimelineSignatures(timelineBefore)),
            "Changing death/status-reference metadata without changing the base status must not append, remove, or rewrite any Animal timeline event.",
            file: file,
            line: line
        )
    }

    static func assertUpdateCanRetireAllActiveTagsWithoutLosingHistory(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeAllTagsRetiredUpdateProbe()
        let current = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            "The all-tags-retired fixture must prepare an existing Animal.",
            file: file,
            line: line
        )
        let beforeTags = current.animal.activeTags + current.animal.inactiveTags
        XCTAssertFalse(
            current.animal.activeTags.isEmpty,
            "The all-tags-retired fixture must begin with at least one active persisted tag.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            current.animal.isArchived,
            "The all-tags-retired fixture must begin with an unarchived Animal so tag clearing is observable through parent-option and Add Offspring projections.",
            file: file,
            line: line
        )
        let summaryBefore = try fetchAnimalSummary(
            id: probe.animalID,
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        let dashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.animalID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        let sireInferenceBefore = try activeDamSireInferenceSnapshots(
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        let beforeTagGroups = Dictionary(grouping: beforeTags, by: \.id)
        XCTAssertTrue(
            beforeTagGroups.values.allSatisfy { $0.count == 1 },
            "The prepared aggregate must not contain duplicate tag application UUIDs.",
            file: file,
            line: line
        )
        let beforeTagsByID = beforeTagGroups.compactMapValues { $0.first }
        let beforeTimeline = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)

        let transaction = try probe.makeUpdateTransaction(current)
        XCTAssertEqual(transaction.animalID, current.animal.id, file: file, line: line)
        XCTAssertEqual(transaction.expectedRevision, current.revision, file: file, line: line)
        XCTAssertFalse(
            attributesDiffer(transaction.attributes, from: current.animal),
            "Retiring the final active tag must not require changing scalar or relationship attributes.",
            file: file,
            line: line
        )

        let desiredGroups = Dictionary(grouping: transaction.tags, by: \.id)
        XCTAssertTrue(
            desiredGroups.values.allSatisfy { $0.count == 1 },
            "The all-tags-retired desired state must not repeat tag application UUIDs.",
            file: file,
            line: line
        )
        let desiredByID = desiredGroups.compactMapValues { $0.first }
        XCTAssertEqual(
            Set(desiredByID.keys),
            Set(beforeTagsByID.keys),
            "Retiring all active tags must preserve the exact persisted tag UUID set.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            transaction.tags.allSatisfy { !$0.isActive && !$0.isPrimary },
            "A currently untagged aggregate with retained history must contain only inactive non-primary tags.",
            file: file,
            line: line
        )
        for (tagID, beforeTag) in beforeTagsByID {
            let desired = try XCTUnwrap(desiredByID[tagID], file: file, line: line)
            XCTAssertEqual(
                desired.number,
                beforeTag.number,
                "The all-tags-retired probe must isolate retirement from tag-number edits.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                desired.colorID,
                beforeTag.colorID,
                "The all-tags-retired probe must isolate retirement from tag-color edits.",
                file: file,
                line: line
            )
        }

        let updated = try probe.writer.updateAnimal(transaction)
        XCTAssertEqual(updated.animal.id, current.animal.id, file: file, line: line)
        XCTAssertNotEqual(
            updated.revision,
            current.revision,
            "Retiring the final active tag is editor-owned tag-state mutation and must rotate the aggregate revision.",
            file: file,
            line: line
        )
        assertAttributes(updated.animal, match: transaction.attributes, file: file, line: line)
        assertTags(
            updated.animal,
            match: transaction.tags,
            preservingHistoryByID: beforeTagsByID,
            file: file,
            line: line
        )
        XCTAssertTrue(updated.animal.activeTags.isEmpty, file: file, line: line)
        XCTAssertEqual(updated.animal.inactiveTags.count, beforeTags.count, file: file, line: line)
        XCTAssertTrue(
            updated.animal.displayTagNumber.isEmpty,
            "An Animal with only retired tag history must expose an empty current display tag.",
            file: file,
            line: line
        )
        XCTAssertNil(
            updated.animal.displayTagColorID,
            "An Animal with only retired tag history must expose no current display tag color.",
            file: file,
            line: line
        )

        let reloaded = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded,
            updated,
            "A fresh editor reader must preserve the inactive-only tag state and rotated revision.",
            file: file,
            line: line
        )
        try await assertFreshAnimalReadProjections(
            detail: reloaded.animal,
            repository: probe.makeAnimalRepository(),
            listQueryReader: probe.makeAnimalListQueryReader(),
            dashboardQueryReader: probe.makeDashboardQueryReader(),
            preservingSummaryOnlyFieldsFrom: summaryBefore,
            preservingDashboardOnlyFieldsFrom: dashboardBefore,
            file: file,
            line: line
        )
        let retiredProjectionRepository = probe.makeAnimalRepository()
        let sireInferenceAfter = try activeDamSireInferenceSnapshots(
            repository: retiredProjectionRepository,
            file: file,
            line: line
        )
        let retiredSireParentDisplay = try XCTUnwrap(
            retiredProjectionRepository
                .fetchParentOptions(excluding: nil)
                .first { $0.id == probe.animalID },
            file: file,
            line: line
        ).displayName
        XCTAssertTrue(
            sireInferenceAfter.contains { damID, after in
                guard let before = sireInferenceBefore[damID] else { return false }
                return before.inferredSireID == probe.animalID
                    && after.inferredSireID == probe.animalID
                    && before.inferredSireDisplayName != after.inferredSireDisplayName
                    && after.inferredSireDisplayName == retiredSireParentDisplay
            },
            "Retiring the final active tag must keep the same inferred-sire identity for at least one active dam while updating that sire's display to the untagged fallback.",
            file: file,
            line: line
        )

        let afterTimeline = try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)
        XCTAssertEqual(
            multisetCounts(timelineSignatures(.status, in: afterTimeline)),
            multisetCounts(timelineSignatures(.status, in: beforeTimeline)),
            "A tag-only retirement update must not add, remove, or rewrite status history.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            multisetCounts(timelineSignatures(.movement, in: afterTimeline)),
            multisetCounts(timelineSignatures(.movement, in: beforeTimeline)),
            "A tag-only retirement update must not add, remove, or rewrite movement history.",
            file: file,
            line: line
        )

        let reloadedTags = reloaded.animal.activeTags + reloaded.animal.inactiveTags
        var expectedTagTimeline: [TimelineSignature] = []
        for tag in reloadedTags {
            expectedTagTimeline.append(
                TimelineSignature(
                    kind: .tag,
                    date: tag.assignedAt,
                    title: "Tag Assigned",
                    details: tag.normalizedNumber
                )
            )
            if let removedAt = tag.removedAt {
                expectedTagTimeline.append(
                    TimelineSignature(
                        kind: .tag,
                        date: removedAt,
                        title: "Tag Retired",
                        details: tag.normalizedNumber
                    )
                )
            }
        }
        XCTAssertEqual(
            multisetCounts(timelineSignatures(.tag, in: afterTimeline)),
            multisetCounts(expectedTagTimeline),
            "Retiring the final active tag must preserve exact assignment history and add durable retirement chronology for every newly inactive tag.",
            file: file,
            line: line
        )
    }

    static func assertUpdatePreservesNonEditorOwnedState(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeNonOwnedStatePreservationProbe()
        let current = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            "The non-owned-state fixture must prepare an existing Animal.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            current.animal.isArchived,
            "The preservation probe must begin with an archived Animal.",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            current.animal.archivedAt,
            "The preservation probe must begin with a durable archive timestamp.",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            current.animal.archiveReason,
            "The preservation probe must begin with a non-nil archive reason so clearing metadata is observable.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            current.animal.location,
            .workingPen,
            "The preservation probe must begin with active Working ownership so an aggregate update cannot silently end it.",
            file: file,
            line: line
        )
        XCTAssertNil(
            current.animal.pastureID,
            "An Animal in the Working pen must not begin the preservation probe assigned to a current Pasture.",
            file: file,
            line: line
        )
        let summaryBefore = try fetchAnimalSummary(
            id: probe.animalID,
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )
        let dashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.animalID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        let sireInferenceBefore = try activeDamSireInferenceSnapshots(
            repository: probe.makeAnimalRepository(),
            file: file,
            line: line
        )

        let activeWorkingSessionIDBefore = try XCTUnwrap(
            probe.makeWorkingOwnershipControl().activeWorkingSessionID(forAnimalID: probe.animalID),
            "The preservation probe must begin with a durable active Working-session relationship.",
            file: file,
            line: line
        )
        let workingSessionBefore = try XCTUnwrap(
            probe.makeWorkingReader().fetchSessionDetail(id: activeWorkingSessionIDBefore),
            "The Animal's active Working session must be readable before the aggregate update.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            workingSessionBefore.id,
            activeWorkingSessionIDBefore,
            "The Working detail projection must preserve the owning session's application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            workingSessionBefore.status,
            .active,
            "The preservation fixture must use an active Working session.",
            file: file,
            line: line
        )
        let workingQueueItemsForAnimalBefore = workingSessionBefore.queueItems.filter {
            $0.animalID == probe.animalID
        }
        XCTAssertEqual(
            workingQueueItemsForAnimalBefore.count,
            1,
            "The active Working session must contain exactly one queue item for the Animal under test.",
            file: file,
            line: line
        )
        let workingQueueItemIDBefore = try XCTUnwrap(
            workingQueueItemsForAnimalBefore.first?.id,
            file: file,
            line: line
        )
        let workingQueueItemIDsBefore = Set(workingSessionBefore.queueItems.map(\.id))

        let beforeTags = current.animal.activeTags + current.animal.inactiveTags
        let beforeTagGroups = Dictionary(grouping: beforeTags, by: \.id)
        XCTAssertTrue(
            beforeTagGroups.values.allSatisfy { $0.count == 1 },
            "The preservation probe must not begin with duplicate tag application UUIDs.",
            file: file,
            line: line
        )
        let beforeTagsByID = beforeTagGroups.compactMapValues { $0.first }
        XCTAssertFalse(
            current.animal.maternalOffspring.isEmpty,
            "The preservation probe must begin with at least one visible maternal offspring relationship.",
            file: file,
            line: line
        )
        let offspringBefore = OffspringProjectionSnapshot(current.animal)
        let archiveBefore = ArchiveStateSnapshot(current.animal)
        let timelineBefore = multisetCounts(
            allTimelineSignatures(
                try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)
            )
        )
        let healthBefore = sortedHealthRecords(
            try probe.makeHealthControl().allHealthRecords()
        )
        let pregnancyBefore = sortedPregnancyChecks(
            try probe.makeHealthControl().allPregnancyChecks()
        )
        XCTAssertTrue(
            healthBefore.contains { $0.animalID == probe.animalID },
            "The preservation probe must begin with persisted health history owned by the Animal but not by the editor transaction.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            pregnancyBefore.contains { $0.animalID == probe.animalID },
            "The preservation probe must begin with persisted pregnancy history owned by the Animal but not by the editor transaction.",
            file: file,
            line: line
        )

        let transaction = try probe.makeUpdateTransaction(current)
        XCTAssertEqual(transaction.animalID, current.animal.id, file: file, line: line)
        XCTAssertEqual(transaction.expectedRevision, current.revision, file: file, line: line)
        try assertValidTagState(
            transaction.tags,
            requireAtLeastOneActiveTag: false,
            file: file,
            line: line
        )
        assertOnlyNameDiffers(
            transaction.attributes,
            from: current.animal,
            file: file,
            line: line
        )
        XCTAssertFalse(
            tagTransactionStateDiffers(transaction.tags, from: current.animal),
            "The preservation probe must keep tag state unchanged so non-owned state preservation is isolated from tag reconciliation.",
            file: file,
            line: line
        )

        let updated = try probe.writer.updateAnimal(transaction)
        XCTAssertEqual(updated.animal.id, current.animal.id, file: file, line: line)
        XCTAssertNotEqual(
            updated.revision,
            current.revision,
            "A successful editor-owned mutation must rotate the aggregate revision while preserving non-owned state.",
            file: file,
            line: line
        )
        assertAttributes(
            updated.animal,
            match: transaction.attributes,
            file: file,
            line: line
        )
        assertTags(
            updated.animal,
            match: transaction.tags,
            preservingHistoryByID: beforeTagsByID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            ArchiveStateSnapshot(updated.animal),
            archiveBefore,
            "Aggregate update must not restore, re-archive, retimestamp, or clear archive metadata it does not own.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            updated.animal.location,
            .workingPen,
            "Aggregate update must not silently end active Working ownership/location.",
            file: file,
            line: line
        )
        XCTAssertNil(updated.animal.pastureID, file: file, line: line)
        XCTAssertEqual(
            OffspringProjectionSnapshot(updated.animal),
            offspringBefore,
            "A name-only aggregate edit must not remove or replace existing maternal offspring relationships.",
            file: file,
            line: line
        )

        let reloaded = try XCTUnwrap(
            probe.makeReader().fetchAnimalAggregateForEditing(id: probe.animalID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded, updated, file: file, line: line)
        XCTAssertEqual(
            ArchiveStateSnapshot(reloaded.animal),
            archiveBefore,
            "Archive metadata must survive a fresh editor reload after aggregate update.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloaded.animal.location,
            .workingPen,
            "Active Working ownership/location must survive a fresh editor reload after aggregate update.",
            file: file,
            line: line
        )
        XCTAssertNil(reloaded.animal.pastureID, file: file, line: line)
        try await assertFreshAnimalReadProjections(
            detail: reloaded.animal,
            repository: probe.makeAnimalRepository(),
            listQueryReader: probe.makeAnimalListQueryReader(),
            dashboardQueryReader: probe.makeDashboardQueryReader(),
            preservingSummaryOnlyFieldsFrom: summaryBefore,
            preservingDashboardOnlyFieldsFrom: dashboardBefore,
            file: file,
            line: line
        )
        assertDashboardAnimalRecordSemanticallyEqual(
            try await fetchDashboardAnimalRecord(
                id: probe.animalID,
                reader: probe.makeDashboardQueryReader(),
                file: file,
                line: line
            ),
            dashboardBefore,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try activeDamSireInferenceSnapshots(
                repository: probe.makeAnimalRepository(),
                file: file,
                line: line
            ),
            sireInferenceBefore,
            "A name-only edit of an archived/ineligible Animal must not alter any active dam's inferred-sire projection.",
            file: file,
            line: line
        )

        let activeWorkingSessionIDAfter = try XCTUnwrap(
            probe.makeWorkingOwnershipControl().activeWorkingSessionID(forAnimalID: probe.animalID),
            "Aggregate update must not clear the Animal's live active Working-session relationship.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            activeWorkingSessionIDAfter,
            activeWorkingSessionIDBefore,
            "Aggregate update must preserve the exact active Working-session application UUID.",
            file: file,
            line: line
        )
        let workingSessionAfter = try XCTUnwrap(
            probe.makeWorkingReader().fetchSessionDetail(id: activeWorkingSessionIDAfter),
            "The original active Working session must remain readable after the aggregate update.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            workingSessionAfter.id,
            activeWorkingSessionIDBefore,
            "The fresh Working projection must resolve the original owning session UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            workingSessionAfter.status,
            .active,
            "A name-only aggregate edit must not finish or otherwise change the owning Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            workingSessionAfter.queueItems.count,
            workingSessionBefore.queueItems.count,
            "Aggregate update must not add or remove Working queue rows from the owning session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(workingSessionAfter.queueItems.map(\.id)),
            workingQueueItemIDsBefore,
            "Aggregate update must preserve the owning Working session's exact queue-item identity set.",
            file: file,
            line: line
        )
        let workingQueueItemsForAnimalAfter = workingSessionAfter.queueItems.filter {
            $0.animalID == probe.animalID
        }
        XCTAssertEqual(
            workingQueueItemsForAnimalAfter.count,
            1,
            "The owning Working session must still contain exactly one queue item for the Animal after aggregate update.",
            file: file,
            line: line
        )
        let workingQueueItemAfter = try XCTUnwrap(
            workingQueueItemsForAnimalAfter.first,
            "The original Working queue item must remain in the owning session after aggregate update.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            workingQueueItemAfter.id,
            workingQueueItemIDBefore,
            "Aggregate update must preserve the exact Working queue-item application UUID for the Animal.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            workingQueueItemAfter.animalID,
            probe.animalID,
            "The original Working queue item must remain associated with the same Animal.",
            file: file,
            line: line
        )

        XCTAssertEqual(
            OffspringProjectionSnapshot(reloaded.animal),
            offspringBefore,
            "Maternal offspring relationships must survive a fresh editor reload after aggregate update.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            multisetCounts(
                allTimelineSignatures(
                    try probe.makeAnimalRepository().fetchTimeline(id: probe.animalID)
                )
            ),
            timelineBefore,
            "A name-only aggregate update must preserve the complete preexisting Animal timeline exactly.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            sortedHealthRecords(
                try probe.makeHealthControl().allHealthRecords()
            ),
            healthBefore,
            "Aggregate editor update must preserve the complete persisted health-record inventory, including identity, payload, ownership, and unrelated rows.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            sortedPregnancyChecks(
                try probe.makeHealthControl().allPregnancyChecks()
            ),
            pregnancyBefore,
            "Aggregate editor update must preserve the complete persisted pregnancy-check inventory, including identity, payload, ownership/sire/session links, and unrelated rows.",
            file: file,
            line: line
        )
    }

    static func assertInvalidCompleteTagStatesAreRejectedWithoutMutation(
        using fixture: AnimalAggregateTransactionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for expected in AnimalAggregateTagValidationFailure.allCases {
            for method in AnimalAggregateInvalidTagMethod.allCases {
                let probe = try fixture.makeInvalidTagProbe(expected, method)
                XCTAssertEqual(
                    probe.operation.method,
                    method,
                    "The invalid-tag fixture must exercise the requested aggregate method.",
                    file: file,
                    line: line
                )
                try assertInvalidTagProbe(
                    probe,
                    expected: expected,
                    file: file,
                    line: line
                )
            }
        }
    }

    private static func assertInvalidTagProbe(
        _ probe: AnimalAggregateInvalidTagContractProbe,
        expected: AnimalAggregateTagValidationFailure,
        file: StaticString,
        line: UInt
    ) throws {
        XCTAssertEqual(
            probe.expectedFailure,
            expected,
            "The invalid-tag fixture returned the wrong validation category.",
            file: file,
            line: line
        )

        let tags: [AnimalTagTransactionState]
        switch probe.operation {
        case .create(let transaction):
            tags = transaction.tags
        case .update(let transaction):
            tags = transaction.tags
        }
        assertTagStateMatchesValidationCase(tags, expected: expected, file: file, line: line)

        let before = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(before, operation: "invalid aggregate tag state", file: file, line: line)

        let performInvalidWrite: () throws -> Void = {
            switch probe.operation {
            case .create(let transaction):
                _ = try probe.writer.createAnimal(transaction)
            case .update(let transaction):
                _ = try probe.writer.updateAnimal(transaction)
            }
        }
        var classifiedFailure: AnimalAggregateTagValidationFailure?
        XCTAssertThrowsError(
            try performInvalidWrite(),
            "The invalid aggregate tag state must be rejected.",
            file: file,
            line: line
        ) { error in
            classifiedFailure = probe.classifyError(error)
        }
        XCTAssertEqual(
            classifiedFailure,
            expected,
            "The aggregate transaction must surface the expected persistence-neutral tag validation category.",
            file: file,
            line: line
        )

        let after = try probe.freshPersistedStateSnapshot()
        assertCompleteStoreSnapshot(after, operation: "invalid aggregate tag state", file: file, line: line)
        XCTAssertEqual(
            after,
            before,
            "Rejecting invalid complete tag state must leave the complete committed store unchanged.",
            file: file,
            line: line
        )
        try assertFailedWriteScopeRecovery(
            probe.recoveryProbe,
            baseline: before,
            freshPersistedStateSnapshot: probe.freshPersistedStateSnapshot,
            file: file,
            line: line
        )
    }

    private static func assertFailedWriteScopeRecovery(
        _ recoveryProbe: PersistenceTransactionRollbackRecoveryProbe,
        baseline: PersistenceTransactionRollbackStateSnapshot,
        freshPersistedStateSnapshot: () throws -> PersistenceTransactionRollbackStateSnapshot,
        file: StaticString,
        line: UInt
    ) throws {
        switch recoveryProbe {
        case .reusableWriteScope(let saveFailedWriteScopeWithoutAdditionalReset):
            try saveFailedWriteScopeWithoutAdditionalReset()
            let afterRecoverySave = try freshPersistedStateSnapshot()
            assertCompleteStoreSnapshot(
                afterRecoverySave,
                operation: "invalid aggregate tag state recovery",
                file: file,
                line: line
            )
            XCTAssertEqual(
                afterRecoverySave,
                baseline,
                "Re-saving the exact failed aggregate tag-validation write scope without an additional test-side reset must not persist rejected staged state.",
                file: file,
                line: line
            )

        case .discardedWriteScope(let verifyFailedWriteScopeWasDisposed):
            XCTAssertTrue(
                verifyFailedWriteScopeWasDisposed(),
                "A one-shot failed aggregate tag-validation write scope must be disposed so rejected staged state cannot be saved later.",
                file: file,
                line: line
            )
        }
    }

    private static func fetchDashboardAnimalRecord(
        id: UUID,
        reader: any DashboardQueryReading,
        file: StaticString,
        line: UInt
    ) async throws -> DashboardAnimalRecord {
        let records = try await reader.fetchDashboardRecords()
        return try XCTUnwrap(
            records.animals.first { $0.id == id },
            "The aggregate Animal must remain visible through the production Dashboard records projection.",
            file: file,
            line: line
        )
    }

    private static func assertDashboardAnimalRecord(
        _ record: DashboardAnimalRecord,
        matches detail: AnimalDetailSnapshot,
        summary: AnimalSummary,
        preservingDashboardOnlyFieldsFrom prior: DashboardAnimalRecord?,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(record.id, detail.id, file: file, line: line)
        XCTAssertEqual(record.displayTagNumber, detail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(record.displayTagColorID, detail.displayTagColorID, file: file, line: line)
        XCTAssertEqual(record.damID, detail.damID, file: file, line: line)
        XCTAssertEqual(record.damDisplayTagNumber, summary.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(record.damDisplayTagColorID, summary.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(record.sex, detail.sex, file: file, line: line)
        XCTAssertEqual(record.animalType, detail.animalType, file: file, line: line)
        XCTAssertEqual(record.status, detail.status, file: file, line: line)
        XCTAssertEqual(record.isArchived, detail.isArchived, file: file, line: line)
        XCTAssertEqual(record.pastureID, detail.pastureID, file: file, line: line)
        XCTAssertEqual(record.pastureName, detail.pastureName, file: file, line: line)
        XCTAssertEqual(record.location, detail.location, file: file, line: line)
        XCTAssertEqual(record.lastPregnancyCheckDate, summary.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(
            record.lastPregnancyStatus,
            dashboardPregnancyStatus(from: summary.lastPregnancyStatus),
            file: file,
            line: line
        )
        XCTAssertEqual(record.expectedCalvingDate, summary.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(record.lastTreatmentDate, summary.lastTreatmentDate, file: file, line: line)
        XCTAssertEqual(record.birthDate, detail.birthDate, file: file, line: line)
        XCTAssertEqual(record.saleDate, detail.saleDate, file: file, line: line)
        XCTAssertEqual(record.deathDate, detail.deathDate, file: file, line: line)
        XCTAssertEqual(
            record.offspringCount,
            detail.maternalOffspringCountIncludingArchived,
            file: file,
            line: line
        )
        if let prior {
            XCTAssertEqual(
                multisetCounts(record.healthRecords),
                multisetCounts(prior.healthRecords),
                "Aggregate editor writes must preserve Dashboard health-history data they do not own without depending on relationship fetch order.",
                file: file,
                line: line
            )
        } else {
            XCTAssertTrue(
                record.healthRecords.isEmpty,
                "A newly created aggregate must not synthesize Dashboard health history.",
                file: file,
                line: line
            )
        }
    }

    private static func assertDashboardAnimalRecordSemanticallyEqual(
        _ actual: DashboardAnimalRecord,
        _ expected: DashboardAnimalRecord,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, expected.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, expected.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.damID, expected.damID, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagNumber, expected.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagColorID, expected.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, expected.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, expected.animalType, file: file, line: line)
        XCTAssertEqual(actual.status, expected.status, file: file, line: line)
        XCTAssertEqual(actual.isArchived, expected.isArchived, file: file, line: line)
        XCTAssertEqual(actual.pastureID, expected.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expected.pastureName, file: file, line: line)
        XCTAssertEqual(actual.location, expected.location, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyCheckDate, expected.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyStatus, expected.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(actual.expectedCalvingDate, expected.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(actual.lastTreatmentDate, expected.lastTreatmentDate, file: file, line: line)
        XCTAssertEqual(actual.birthDate, expected.birthDate, file: file, line: line)
        XCTAssertEqual(actual.saleDate, expected.saleDate, file: file, line: line)
        XCTAssertEqual(actual.deathDate, expected.deathDate, file: file, line: line)
        XCTAssertEqual(actual.offspringCount, expected.offspringCount, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(actual.healthRecords),
            multisetCounts(expected.healthRecords),
            file: file,
            line: line
        )
    }

    private static func dashboardPregnancyStatus(
        from result: PregnancyResult?
    ) -> DashboardPregnancyStatus? {
        switch result {
        case .open:
            return .open
        case .pregnant:
            return .pregnant
        case .unknown:
            return .unknown
        case nil:
            return nil
        }
    }

    private static func assertDashboardAnimalListMembership(
        _ record: DashboardAnimalRecord,
        detail: AnimalDetailSnapshot,
        reader: any DashboardQueryReading,
        file: StaticString,
        line: UInt
    ) async throws {
        let active = try await reader.fetchDashboardAnimalRecords(kind: .active)
        let activeRecord = active.first { $0.id == detail.id }
        if detail.status == .active && !detail.isArchived {
            assertDashboardAnimalRecordSemanticallyEqual(
                try XCTUnwrap(activeRecord, file: file, line: line),
                record,
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(activeRecord, file: file, line: line)
        }

        let workingPen = try await reader.fetchDashboardAnimalRecords(kind: .workingPen)
        let workingRecord = workingPen.first { $0.id == detail.id }
        if detail.status == .active && !detail.isArchived && detail.location == .workingPen {
            assertDashboardAnimalRecordSemanticallyEqual(
                try XCTUnwrap(workingRecord, file: file, line: line),
                record,
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(workingRecord, file: file, line: line)
        }

        let unassigned = try await reader.fetchDashboardAnimalRecords(kind: .unassigned)
        let unassignedRecord = unassigned.first { $0.id == detail.id }
        if detail.status == .active
            && !detail.isArchived
            && detail.location == .pasture
            && detail.pastureID == nil {
            assertDashboardAnimalRecordSemanticallyEqual(
                try XCTUnwrap(unassignedRecord, file: file, line: line),
                record,
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(unassignedRecord, file: file, line: line)
        }
    }

    private static func assertPastureCountProjectionsMatchResidents(
        pastureID: UUID,
        dashboardReader: any DashboardQueryReading,
        pastureRepository: any PastureRepository,
        file: StaticString,
        line: UInt
    ) async throws {
        let expectedResidentCount = try pastureRepository.fetchResidentAnimals(pastureID: pastureID).count

        let detail = try XCTUnwrap(
            pastureRepository.fetchPastureDetail(id: pastureID),
            "The affected Pasture must remain visible through the detail projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            detail.activeAnimalCount,
            expectedResidentCount,
            "Pasture detail active-head count must match the fresh resident projection after aggregate mutation.",
            file: file,
            line: line
        )

        let summary = try XCTUnwrap(
            pastureRepository.fetchPastures().first { $0.id == pastureID },
            "The affected Pasture must remain visible through the list projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            summary.activeAnimalCount,
            expectedResidentCount,
            "Pasture list active-head count must match the fresh resident projection after aggregate mutation.",
            file: file,
            line: line
        )

        if let groupID = detail.groupID {
            let group = try XCTUnwrap(
                pastureRepository.fetchPastureGroupDetail(id: groupID),
                "A grouped affected Pasture must remain visible through its PastureGroup detail projection.",
                file: file,
                line: line
            )
            let groupedPasture = try XCTUnwrap(
                group.pastures.first { $0.id == pastureID },
                "The affected Pasture must remain embedded in its unchanged PastureGroup.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                groupedPasture.activeAnimalCount,
                expectedResidentCount,
                "PastureGroup detail must expose the same active-head count for an affected member Pasture.",
                file: file,
                line: line
            )
        }

        let dashboardRecords = try await dashboardReader.fetchDashboardRecords()
        let dashboardRecordsPasture = try XCTUnwrap(
            dashboardRecords.pastures.first { $0.id == pastureID },
            "The affected Pasture must remain visible through the Dashboard records projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            dashboardRecordsPasture.activeAnimalCount,
            expectedResidentCount,
            "Dashboard records Pasture active-head count must match the fresh resident projection after aggregate mutation.",
            file: file,
            line: line
        )

        let dashboardPastureRecords = try await dashboardReader.fetchDashboardPastureRecords()
        let dashboardPastureListRecord = try XCTUnwrap(
            dashboardPastureRecords.first { $0.id == pastureID },
            "The affected Pasture must remain visible through the dedicated Dashboard Pasture-list projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            dashboardPastureListRecord.activeAnimalCount,
            expectedResidentCount,
            "Dashboard Pasture-list active-head count must match the fresh resident projection after aggregate mutation.",
            file: file,
            line: line
        )
    }

    private struct ActiveDamSireInferenceSnapshot: Equatable {
        let inferredSireID: UUID?
        let inferredSireDisplayName: String?
    }

    private static func activeDamSireInferenceSnapshots(
        repository: any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws -> [UUID: ActiveDamSireInferenceSnapshot] {
        let activeDams = try repository.fetchAnimals().filter {
            $0.sex == .female
                && $0.status == .active
                && !$0.isArchived
                && $0.pastureID != nil
        }

        var snapshots: [UUID: ActiveDamSireInferenceSnapshot] = [:]
        for dam in activeDams {
            let seed = try XCTUnwrap(
                repository.fetchOffspringDraftSeed(forDamID: dam.id),
                "Every active, unarchived dam in a Pasture must be readable through the Add Offspring projection.",
                file: file,
                line: line
            )
            snapshots[dam.id] = ActiveDamSireInferenceSnapshot(
                inferredSireID: seed.inferredSireID,
                inferredSireDisplayName: seed.inferredSireDisplayName
            )
        }
        return snapshots
    }

    private static func fetchAnimalSummary(
        id: UUID,
        repository: any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws -> AnimalSummary {
        try XCTUnwrap(
            repository.fetchAnimals().first { $0.id == id },
            "The Animal must remain visible through the summary read projection.",
            file: file,
            line: line
        )
    }

    private static func fetchAnimalListQuerySummary(
        id: UUID,
        reader: any AnimalListQueryReading,
        file: StaticString,
        line: UInt
    ) async throws -> AnimalSummary {
        var offset = 0
        while true {
            let page = try await reader.fetchAnimalSummaryPage(
                ReadPageRequest(offset: offset, limit: ReadPageRequest.defaultLimit)
            )
            if let summary = page.animals.first(where: { $0.id == id }) {
                return summary
            }
            guard page.hasMore, !page.animals.isEmpty else {
                return try XCTUnwrap(
                    Optional<AnimalSummary>.none,
                    "The aggregate Animal must be returned by the production paged Animal list projection.",
                    file: file,
                    line: line
                )
            }
            offset += page.animals.count
        }
    }

    private static func assertFreshAnimalReadProjections(
        detail: AnimalDetailSnapshot,
        repository: any AnimalRepository,
        listQueryReader: any AnimalListQueryReading,
        dashboardQueryReader: any DashboardQueryReading,
        preservingSummaryOnlyFieldsFrom priorSummary: AnimalSummary?,
        preservingDashboardOnlyFieldsFrom priorDashboard: DashboardAnimalRecord?,
        file: StaticString,
        line: UInt
    ) async throws {
        let summary = try fetchAnimalSummary(
            id: detail.id,
            repository: repository,
            file: file,
            line: line
        )
        XCTAssertEqual(summary.id, detail.id, file: file, line: line)
        XCTAssertEqual(summary.name, detail.name, file: file, line: line)
        XCTAssertEqual(summary.displayTagNumber, detail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(summary.displayTagColorID, detail.displayTagColorID, file: file, line: line)
        XCTAssertEqual(summary.sex, detail.sex, file: file, line: line)
        XCTAssertEqual(summary.animalType, detail.animalType, file: file, line: line)
        XCTAssertEqual(
            summary.firstDistinguishingFeature,
            detail.distinguishingFeatures.firstOrderedDistinguishingFeatureDescription,
            file: file,
            line: line
        )
        XCTAssertEqual(summary.birthDate, detail.birthDate, file: file, line: line)
        XCTAssertEqual(summary.status, detail.status, file: file, line: line)
        XCTAssertEqual(summary.isArchived, detail.isArchived, file: file, line: line)
        XCTAssertEqual(summary.pastureID, detail.pastureID, file: file, line: line)
        XCTAssertEqual(summary.pastureName, detail.pastureName, file: file, line: line)
        XCTAssertEqual(summary.location, detail.location, file: file, line: line)

        let pagedSummary = try await fetchAnimalListQuerySummary(
            id: detail.id,
            reader: listQueryReader,
            file: file,
            line: line
        )
        XCTAssertEqual(
            pagedSummary,
            summary,
            "The production-preferred paged Animal list projection must exactly match the synchronous Animal summary projection after aggregate mutation.",
            file: file,
            line: line
        )

        let dashboard = try await fetchDashboardAnimalRecord(
            id: detail.id,
            reader: dashboardQueryReader,
            file: file,
            line: line
        )
        assertDashboardAnimalRecord(
            dashboard,
            matches: detail,
            summary: summary,
            preservingDashboardOnlyFieldsFrom: priorDashboard,
            file: file,
            line: line
        )
        try await assertDashboardAnimalListMembership(
            dashboard,
            detail: detail,
            reader: dashboardQueryReader,
            file: file,
            line: line
        )

        if let damID = detail.damID {
            let dam = try XCTUnwrap(
                repository.fetchAnimalDetail(id: damID),
                "The Animal summary's dam projection must resolve the current dam relationship.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                summary.damDisplayTagNumber,
                AnimalDisplayTagFormatter.displayTagNumber(from: dam.displayTagNumber),
                file: file,
                line: line
            )
            XCTAssertEqual(summary.damDisplayTagColorID, dam.displayTagColorID, file: file, line: line)
        } else {
            XCTAssertNil(summary.damDisplayTagNumber, file: file, line: line)
            XCTAssertNil(summary.damDisplayTagColorID, file: file, line: line)
        }

        if let priorSummary {
            XCTAssertEqual(
                summary.lastPregnancyCheckDate,
                priorSummary.lastPregnancyCheckDate,
                "Aggregate editor writes must preserve pregnancy summary state they do not own.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                summary.lastPregnancyStatus,
                priorSummary.lastPregnancyStatus,
                "Aggregate editor writes must preserve pregnancy summary status they do not own.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                summary.expectedCalvingDate,
                priorSummary.expectedCalvingDate,
                "Aggregate editor writes must preserve expected-calving summary state they do not own.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                summary.lastTreatmentDate,
                priorSummary.lastTreatmentDate,
                "Aggregate editor writes must preserve treatment summary state they do not own.",
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(summary.lastPregnancyCheckDate, file: file, line: line)
            XCTAssertNil(summary.lastPregnancyStatus, file: file, line: line)
            XCTAssertNil(summary.expectedCalvingDate, file: file, line: line)
            XCTAssertNil(summary.lastTreatmentDate, file: file, line: line)
        }

        let parentOptions = try repository.fetchParentOptions(excluding: nil)
        if detail.isArchived {
            XCTAssertFalse(
                parentOptions.contains { $0.id == detail.id },
                "Archived Animals must remain excluded from the parent-option projection after aggregate update.",
                file: file,
                line: line
            )
            XCTAssertNil(
                try repository.fetchOffspringDraftSeed(forDamID: detail.id),
                "Archived Animals must remain excluded from the Add Offspring seed projection after aggregate update.",
                file: file,
                line: line
            )
            return
        }

        let parentOption = try XCTUnwrap(
            parentOptions.first { $0.id == detail.id },
            "An unarchived aggregate must be visible through the parent-option read projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(parentOption.name, detail.name, file: file, line: line)
        XCTAssertEqual(parentOption.displayTagNumber, detail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(parentOption.displayTagColorID, detail.displayTagColorID, file: file, line: line)
        XCTAssertEqual(parentOption.sex, detail.sex, file: file, line: line)
        XCTAssertFalse(parentOption.isArchived, file: file, line: line)

        let offspringSeed = try XCTUnwrap(
            repository.fetchOffspringDraftSeed(forDamID: detail.id),
            "An unarchived aggregate must remain readable through the Add Offspring seed projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(offspringSeed.damID, detail.id, file: file, line: line)
        XCTAssertEqual(offspringSeed.damDisplayName, parentOption.displayName, file: file, line: line)
        XCTAssertEqual(offspringSeed.pastureID, detail.pastureID, file: file, line: line)
        XCTAssertEqual(offspringSeed.pastureName, detail.pastureName, file: file, line: line)
    }

    private static func assertNewAggregateDefaults(
        detail: AnimalDetailSnapshot,
        workingOwnershipControl: any AnimalAggregateWorkingOwnershipContractTestControl,
        file: StaticString,
        line: UInt
    ) throws {
        XCTAssertFalse(
            detail.isArchived,
            "A newly created Animal must begin unarchived because archive state is not authored by the create transaction.",
            file: file,
            line: line
        )
        XCTAssertNil(
            detail.archivedAt,
            "A newly created Animal must not synthesize an archive timestamp.",
            file: file,
            line: line
        )
        XCTAssertNil(
            detail.archiveReason,
            "A newly created Animal must not synthesize an archive reason.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            detail.location,
            .pasture,
            "A newly created Animal must initialize in the Pasture location so Working collection eligibility starts from coherent state.",
            file: file,
            line: line
        )
        let activeWorkingSessionID = try workingOwnershipControl
            .activeWorkingSessionID(forAnimalID: detail.id)
        XCTAssertNil(
            activeWorkingSessionID,
            "A newly created Animal must not begin owned by a Working session.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            detail.maternalOffspringCountIncludingArchived,
            0,
            "A newly created Animal must not begin with preexisting maternal-offspring relationships.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            detail.maternalOffspring.isEmpty,
            "A newly created Animal must expose an empty visible maternal-offspring projection.",
            file: file,
            line: line
        )
    }

    private static func assertAttributes(
        _ detail: AnimalDetailSnapshot,
        match attributes: AnimalAggregateAttributes,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(detail.name, attributes.name, file: file, line: line)
        XCTAssertEqual(detail.sex, attributes.sex, file: file, line: line)
        XCTAssertEqual(detail.birthDate, attributes.birthDate, file: file, line: line)
        XCTAssertEqual(detail.status, attributes.status, file: file, line: line)
        XCTAssertEqual(detail.pastureID, attributes.pastureID, file: file, line: line)
        XCTAssertEqual(detail.sireID, attributes.sireID, file: file, line: line)
        XCTAssertEqual(detail.damID, attributes.damID, file: file, line: line)
        XCTAssertEqual(detail.distinguishingFeatures, attributes.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(detail.saleDate, attributes.saleDate, file: file, line: line)
        XCTAssertEqual(detail.salePrice, attributes.salePrice, file: file, line: line)
        XCTAssertEqual(detail.reasonSold, attributes.reasonSold, file: file, line: line)
        XCTAssertEqual(detail.deathDate, attributes.deathDate, file: file, line: line)
        XCTAssertEqual(detail.causeOfDeath, attributes.causeOfDeath, file: file, line: line)
        XCTAssertEqual(detail.statusReferenceID, attributes.statusReferenceID, file: file, line: line)
    }

    private static func assertTags(
        _ detail: AnimalDetailSnapshot,
        match expected: [AnimalTagTransactionState],
        preservingHistoryByID: [UUID: AnimalTagSnapshot],
        file: StaticString,
        line: UInt
    ) {
        let actual = detail.activeTags + detail.inactiveTags
        let actualGroups = Dictionary(grouping: actual, by: \.id)
        XCTAssertTrue(
            actualGroups.values.allSatisfy { $0.count == 1 },
            "The persisted aggregate must expose at most one tag row per application UUID.",
            file: file,
            line: line
        )
        let expectedGroups = Dictionary(grouping: expected, by: \.id)
        XCTAssertTrue(
            expectedGroups.values.allSatisfy { $0.count == 1 },
            "The valid transaction fixture must not repeat tag application UUIDs.",
            file: file,
            line: line
        )
        XCTAssertEqual(Set(actualGroups.keys), Set(expectedGroups.keys), file: file, line: line)

        for state in expected {
            guard let tag = actualGroups[state.id]?.first else { continue }
            XCTAssertEqual(tag.number, state.number, file: file, line: line)
            XCTAssertEqual(tag.colorID, state.colorID, file: file, line: line)
            XCTAssertEqual(tag.isPrimary, state.isPrimary, file: file, line: line)
            XCTAssertEqual(tag.isActive, state.isActive, file: file, line: line)
            if let prior = preservingHistoryByID[state.id] {
                XCTAssertEqual(
                    tag.assignedAt,
                    prior.assignedAt,
                    "Reconciling an existing tag UUID must preserve its original assignment timestamp.",
                    file: file,
                    line: line
                )
                if !prior.isActive && !state.isActive {
                    XCTAssertEqual(
                        tag.removedAt,
                        prior.removedAt,
                        "Carrying an already-retired tag forward as retired must preserve its original retirement timestamp.",
                        file: file,
                        line: line
                    )
                }
            }
            if state.isActive {
                XCTAssertNil(tag.removedAt, "Active tags must not retain a retirement timestamp.", file: file, line: line)
            } else {
                XCTAssertNotNil(tag.removedAt, "Inactive tags must remain durable retired history.", file: file, line: line)
            }
        }

        let active = expected.filter(\.isActive)
        let primary = expected.first { $0.isActive && $0.isPrimary }
        if active.isEmpty {
            XCTAssertTrue(detail.displayTagNumber.isEmpty, file: file, line: line)
            XCTAssertNil(detail.displayTagColorID, file: file, line: line)
        } else if let primary {
            XCTAssertEqual(
                detail.displayTagNumber,
                primary.number.trimmingCharacters(in: .whitespacesAndNewlines),
                file: file,
                line: line
            )
            XCTAssertEqual(detail.displayTagColorID, primary.colorID, file: file, line: line)
        }
    }

    private static func assertValidTagState(
        _ tags: [AnimalTagTransactionState],
        requireAtLeastOneActiveTag: Bool,
        file: StaticString,
        line: UInt
    ) throws {
        let active = tags.filter(\.isActive)
        if requireAtLeastOneActiveTag {
            XCTAssertFalse(active.isEmpty, "The tagged fixture must contain at least one active tag.", file: file, line: line)
        }
        XCTAssertEqual(
            active.filter(\.isPrimary).count,
            active.isEmpty ? 0 : 1,
            "A valid complete tag state must contain exactly one active primary tag when active tags exist.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            tags.contains { !$0.isActive && $0.isPrimary },
            "Inactive tags cannot remain primary.",
            file: file,
            line: line
        )
    }

    private static func assertTagStateMatchesValidationCase(
        _ tags: [AnimalTagTransactionState],
        expected: AnimalAggregateTagValidationFailure,
        file: StaticString,
        line: UInt
    ) {
        let active = tags.filter(\.isActive)
        switch expected {
        case .activeTagsRequirePrimary:
            XCTAssertFalse(active.isEmpty, file: file, line: line)
            XCTAssertEqual(active.filter(\.isPrimary).count, 0, file: file, line: line)
            XCTAssertFalse(tags.contains { !$0.isActive && $0.isPrimary }, file: file, line: line)

        case .multipleActivePrimaryTags:
            XCTAssertGreaterThan(active.filter(\.isPrimary).count, 1, file: file, line: line)
            XCTAssertFalse(tags.contains { !$0.isActive && $0.isPrimary }, file: file, line: line)

        case .inactiveTagCannotBePrimary:
            XCTAssertTrue(tags.contains { !$0.isActive && $0.isPrimary }, file: file, line: line)

        case .duplicateTagApplicationIDs:
            XCTAssertLessThan(
                Set(tags.map(\.id)).count,
                tags.count,
                "The duplicate-ID validation probe must repeat at least one tag application UUID.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                active.filter(\.isPrimary).count,
                active.isEmpty ? 0 : 1,
                "Duplicate tag UUID must be the intended invalid condition, not primary-tag cardinality.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                tags.contains { !$0.isActive && $0.isPrimary },
                "Duplicate tag UUID must be the intended invalid condition, not an inactive primary tag.",
                file: file,
                line: line
            )
        }
    }

    private struct OffspringProjectionSnapshot: Equatable {
        let totalIncludingArchived: Int
        let visibleIDs: Set<UUID>

        init(_ detail: AnimalDetailSnapshot) {
            totalIncludingArchived = detail.maternalOffspringCountIncludingArchived
            visibleIDs = Set(detail.maternalOffspring.map(\.id))
        }
    }

    private static func assertAnimalDetailUnchangedExceptDamDisplay(
        before: AnimalDetailSnapshot,
        after: AnimalDetailSnapshot,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(after.id, before.id, file: file, line: line)
        XCTAssertEqual(after.name, before.name, file: file, line: line)
        XCTAssertEqual(after.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(after.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(after.sex, before.sex, file: file, line: line)
        XCTAssertEqual(after.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(after.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(after.status, before.status, file: file, line: line)
        XCTAssertEqual(after.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(after.pastureName, before.pastureName, file: file, line: line)
        XCTAssertEqual(after.sireID, before.sireID, file: file, line: line)
        XCTAssertEqual(after.sire, before.sire, file: file, line: line)
        XCTAssertEqual(after.damID, before.damID, file: file, line: line)
        XCTAssertEqual(after.distinguishingFeatures, before.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(after.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(after.salePrice, before.salePrice, file: file, line: line)
        XCTAssertEqual(after.reasonSold, before.reasonSold, file: file, line: line)
        XCTAssertEqual(after.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(after.causeOfDeath, before.causeOfDeath, file: file, line: line)
        XCTAssertEqual(after.statusReferenceID, before.statusReferenceID, file: file, line: line)
        XCTAssertEqual(after.statusReferenceName, before.statusReferenceName, file: file, line: line)
        XCTAssertEqual(after.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(after.archivedAt, before.archivedAt, file: file, line: line)
        XCTAssertEqual(after.archiveReason, before.archiveReason, file: file, line: line)
        XCTAssertEqual(multisetCounts(after.activeTags), multisetCounts(before.activeTags), file: file, line: line)
        XCTAssertEqual(multisetCounts(after.inactiveTags), multisetCounts(before.inactiveTags), file: file, line: line)
        XCTAssertEqual(after.location, before.location, file: file, line: line)
        XCTAssertEqual(
            after.maternalOffspringCountIncludingArchived,
            before.maternalOffspringCountIncludingArchived,
            file: file,
            line: line
        )
        XCTAssertEqual(
            multisetCounts(after.maternalOffspring),
            multisetCounts(before.maternalOffspring),
            file: file,
            line: line
        )
    }

    private static func assertAnimalSummaryUnchangedExceptDamDisplay(
        before: AnimalSummary,
        after: AnimalSummary,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(after.id, before.id, file: file, line: line)
        XCTAssertEqual(after.name, before.name, file: file, line: line)
        XCTAssertEqual(after.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(after.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(after.sex, before.sex, file: file, line: line)
        XCTAssertEqual(after.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(after.firstDistinguishingFeature, before.firstDistinguishingFeature, file: file, line: line)
        XCTAssertEqual(after.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(after.status, before.status, file: file, line: line)
        XCTAssertEqual(after.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(after.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(after.pastureName, before.pastureName, file: file, line: line)
        XCTAssertEqual(after.location, before.location, file: file, line: line)
        XCTAssertEqual(after.lastPregnancyCheckDate, before.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(after.lastPregnancyStatus, before.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(after.expectedCalvingDate, before.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(after.lastTreatmentDate, before.lastTreatmentDate, file: file, line: line)
    }

    private static func assertDashboardAnimalRecordUnchangedExceptDamDisplay(
        before: DashboardAnimalRecord,
        after: DashboardAnimalRecord,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(after.id, before.id, file: file, line: line)
        XCTAssertEqual(after.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(after.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(after.damID, before.damID, file: file, line: line)
        XCTAssertEqual(after.sex, before.sex, file: file, line: line)
        XCTAssertEqual(after.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(after.status, before.status, file: file, line: line)
        XCTAssertEqual(after.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(after.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(after.pastureName, before.pastureName, file: file, line: line)
        XCTAssertEqual(after.location, before.location, file: file, line: line)
        XCTAssertEqual(after.lastPregnancyCheckDate, before.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(after.lastPregnancyStatus, before.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(after.expectedCalvingDate, before.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(after.lastTreatmentDate, before.lastTreatmentDate, file: file, line: line)
        XCTAssertEqual(after.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(after.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(after.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(multisetCounts(after.healthRecords), multisetCounts(before.healthRecords), file: file, line: line)
        XCTAssertEqual(after.offspringCount, before.offspringCount, file: file, line: line)
    }

    private static func timelineWithoutPrimaryBirth(
        _ events: [AnimalTimelineEvent],
        birthDate: Date
    ) -> [TimelineSignature] {
        allTimelineSignatures(events).filter {
            !($0.kind == .birth && $0.title == "Birth" && $0.date == birthDate)
        }
    }

    private static func primaryBirthSignature(
        detail: AnimalDetailSnapshot,
        repository: any AnimalRepository,
        timeline: [AnimalTimelineEvent],
        file: StaticString,
        line: UInt
    ) throws -> TimelineSignature {
        let primaryBirths = timelineSignatures(.birth, in: timeline).filter {
            $0.title == "Birth" && $0.date == detail.birthDate
        }
        XCTAssertEqual(
            primaryBirths.count,
            1,
            "An Animal timeline must expose exactly one primary Birth projection at the Animal birth date.",
            file: file,
            line: line
        )
        let actual = try XCTUnwrap(primaryBirths.first, file: file, line: line)

        let damDisplay = try detail.damID.flatMap { damID in
            try repository.fetchAnimalDetail(id: damID)?
                .displayTagNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let sireDisplay = try detail.sireID.flatMap { sireID in
            try repository.fetchAnimalDetail(id: sireID)?
                .displayTagNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var details: [String] = []
        if let damDisplay, !damDisplay.isEmpty {
            details.append("Dam: \(damDisplay)")
        }
        if let sireDisplay, !sireDisplay.isEmpty {
            details.append("Sire: \(sireDisplay)")
        }
        if let pastureName = detail.pastureName, !pastureName.isEmpty {
            details.append("Pasture: \(pastureName)")
        }
        let expected = TimelineSignature(
            kind: .birth,
            date: detail.birthDate,
            title: "Birth",
            details: details.isEmpty ? nil : details.joined(separator: " • ")
        )
        XCTAssertEqual(
            actual,
            expected,
            "The primary Birth projection must derive from current parent displays and Pasture.",
            file: file,
            line: line
        )
        return actual
    }

    private static func assertOnlySameStatusMetadataDiffers(
        _ attributes: AnimalAggregateAttributes,
        from detail: AnimalDetailSnapshot,
        file: StaticString,
        line: UInt
    ) throws {
        XCTAssertEqual(attributes.status, .dead, file: file, line: line)
        XCTAssertEqual(attributes.status, detail.status, file: file, line: line)

        let deathDate = try XCTUnwrap(
            attributes.deathDate,
            "The same-status metadata update must retain a non-nil death date.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            deathDate,
            detail.deathDate,
            "The same-status metadata update must materially change the death date.",
            file: file,
            line: line
        )

        let causeOfDeath = try XCTUnwrap(
            attributes.causeOfDeath,
            "The same-status metadata update must retain a non-nil cause of death.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            causeOfDeath,
            detail.causeOfDeath,
            "The same-status metadata update must materially change the cause of death.",
            file: file,
            line: line
        )

        let statusReferenceID = try XCTUnwrap(
            attributes.statusReferenceID,
            "The same-status metadata update must retain a non-nil custom status reference.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            statusReferenceID,
            detail.statusReferenceID,
            "The same-status metadata update must select a different custom status reference.",
            file: file,
            line: line
        )

        XCTAssertEqual(attributes.name, detail.name, file: file, line: line)
        XCTAssertEqual(attributes.sex, detail.sex, file: file, line: line)
        XCTAssertEqual(attributes.birthDate, detail.birthDate, file: file, line: line)
        XCTAssertEqual(attributes.pastureID, detail.pastureID, file: file, line: line)
        XCTAssertEqual(attributes.sireID, detail.sireID, file: file, line: line)
        XCTAssertEqual(attributes.damID, detail.damID, file: file, line: line)
        XCTAssertEqual(attributes.distinguishingFeatures, detail.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(attributes.saleDate, detail.saleDate, file: file, line: line)
        XCTAssertEqual(attributes.salePrice, detail.salePrice, file: file, line: line)
        XCTAssertEqual(attributes.reasonSold, detail.reasonSold, file: file, line: line)
    }

    private static func assertDashboardAnimalRecordUnchangedExceptDeathDate(
        before: DashboardAnimalRecord,
        after: DashboardAnimalRecord,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(after.id, before.id, file: file, line: line)
        XCTAssertEqual(after.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(after.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(after.damID, before.damID, file: file, line: line)
        XCTAssertEqual(after.damDisplayTagNumber, before.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(after.damDisplayTagColorID, before.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(after.sex, before.sex, file: file, line: line)
        XCTAssertEqual(after.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(after.status, before.status, file: file, line: line)
        XCTAssertEqual(after.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(after.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(after.pastureName, before.pastureName, file: file, line: line)
        XCTAssertEqual(after.location, before.location, file: file, line: line)
        XCTAssertEqual(after.lastPregnancyCheckDate, before.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(after.lastPregnancyStatus, before.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(after.expectedCalvingDate, before.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(after.lastTreatmentDate, before.lastTreatmentDate, file: file, line: line)
        XCTAssertEqual(after.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(after.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(after.healthRecords),
            multisetCounts(before.healthRecords),
            file: file,
            line: line
        )
        XCTAssertEqual(after.offspringCount, before.offspringCount, file: file, line: line)
    }

    private static func assertOnlyPastureDiffers(
        _ attributes: AnimalAggregateAttributes,
        from detail: AnimalDetailSnapshot,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertNotEqual(
            attributes.pastureID,
            detail.pastureID,
            "The focused Pasture move must materially change only the Pasture relationship.",
            file: file,
            line: line
        )
        XCTAssertEqual(attributes.name, detail.name, file: file, line: line)
        XCTAssertEqual(attributes.sex, detail.sex, file: file, line: line)
        XCTAssertEqual(attributes.birthDate, detail.birthDate, file: file, line: line)
        XCTAssertEqual(attributes.status, detail.status, file: file, line: line)
        XCTAssertEqual(attributes.sireID, detail.sireID, file: file, line: line)
        XCTAssertEqual(attributes.damID, detail.damID, file: file, line: line)
        XCTAssertEqual(attributes.distinguishingFeatures, detail.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(attributes.saleDate, detail.saleDate, file: file, line: line)
        XCTAssertEqual(attributes.salePrice, detail.salePrice, file: file, line: line)
        XCTAssertEqual(attributes.reasonSold, detail.reasonSold, file: file, line: line)
        XCTAssertEqual(attributes.deathDate, detail.deathDate, file: file, line: line)
        XCTAssertEqual(attributes.causeOfDeath, detail.causeOfDeath, file: file, line: line)
        XCTAssertEqual(attributes.statusReferenceID, detail.statusReferenceID, file: file, line: line)
    }

    private static func assertOnlyNameDiffers(
        _ attributes: AnimalAggregateAttributes,
        from detail: AnimalDetailSnapshot,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertNotEqual(
            attributes.name,
            detail.name,
            "The non-owned-state preservation probe must perform a material name edit.",
            file: file,
            line: line
        )
        XCTAssertEqual(attributes.sex, detail.sex, file: file, line: line)
        XCTAssertEqual(attributes.birthDate, detail.birthDate, file: file, line: line)
        XCTAssertEqual(attributes.status, detail.status, file: file, line: line)
        XCTAssertEqual(attributes.pastureID, detail.pastureID, file: file, line: line)
        XCTAssertEqual(attributes.sireID, detail.sireID, file: file, line: line)
        XCTAssertEqual(attributes.damID, detail.damID, file: file, line: line)
        XCTAssertEqual(
            attributes.distinguishingFeatures,
            detail.distinguishingFeatures,
            file: file,
            line: line
        )
        XCTAssertEqual(attributes.saleDate, detail.saleDate, file: file, line: line)
        XCTAssertEqual(attributes.salePrice, detail.salePrice, file: file, line: line)
        XCTAssertEqual(attributes.reasonSold, detail.reasonSold, file: file, line: line)
        XCTAssertEqual(attributes.deathDate, detail.deathDate, file: file, line: line)
        XCTAssertEqual(attributes.causeOfDeath, detail.causeOfDeath, file: file, line: line)
        XCTAssertEqual(attributes.statusReferenceID, detail.statusReferenceID, file: file, line: line)
    }

    private struct ArchiveStateSnapshot: Equatable {
        let isArchived: Bool
        let archivedAt: Date?
        let archiveReason: String?

        init(_ detail: AnimalDetailSnapshot) {
            isArchived = detail.isArchived
            archivedAt = detail.archivedAt
            archiveReason = detail.archiveReason
        }
    }

    private static func sortedHealthRecords(
        _ records: [HealthRecordContractSnapshot]
    ) -> [HealthRecordContractSnapshot] {
        records.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func sortedPregnancyChecks(
        _ checks: [PregnancyCheckContractSnapshot]
    ) -> [PregnancyCheckContractSnapshot] {
        checks.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func tagTransactionStateDiffers(
        _ desired: [AnimalTagTransactionState],
        from detail: AnimalDetailSnapshot
    ) -> Bool {
        let current = (detail.activeTags + detail.inactiveTags).map {
            AnimalTagTransactionState(
                id: $0.id,
                number: $0.number,
                colorID: $0.colorID,
                isPrimary: $0.isPrimary,
                isActive: $0.isActive
            )
        }
        return Set(desired) != Set(current)
    }

    private static func attributesDiffer(
        _ attributes: AnimalAggregateAttributes,
        from detail: AnimalDetailSnapshot
    ) -> Bool {
        attributes.name != detail.name
            || attributes.sex != detail.sex
            || attributes.birthDate != detail.birthDate
            || attributes.status != detail.status
            || attributes.pastureID != detail.pastureID
            || attributes.sireID != detail.sireID
            || attributes.damID != detail.damID
            || attributes.distinguishingFeatures != detail.distinguishingFeatures
            || attributes.saleDate != detail.saleDate
            || attributes.salePrice != detail.salePrice
            || attributes.reasonSold != detail.reasonSold
            || attributes.deathDate != detail.deathDate
            || attributes.causeOfDeath != detail.causeOfDeath
            || attributes.statusReferenceID != detail.statusReferenceID
    }

    private enum TimelineKind: Hashable {
        case birth
        case health
        case pregnancy
        case movement
        case status
        case tag
    }

    private struct TimelineSignature: Hashable {
        let kind: TimelineKind
        let date: Date
        let title: String
        let details: String?
    }

    private static func timelineCount(
        _ kind: TimelineKind,
        in events: [AnimalTimelineEvent]
    ) -> Int {
        timelineSignatures(kind, in: events).count
    }

    private static func allTimelineSignatures(
        _ events: [AnimalTimelineEvent]
    ) -> [TimelineSignature] {
        events.map {
            TimelineSignature(
                kind: timelineKind(for: $0.type),
                date: $0.date,
                title: $0.title,
                details: $0.details
            )
        }
    }

    private static func timelineSignatures(
        _ kind: TimelineKind,
        in events: [AnimalTimelineEvent]
    ) -> [TimelineSignature] {
        events.compactMap { event in
            guard timelineKind(for: event.type) == kind else { return nil }
            return TimelineSignature(
                kind: kind,
                date: event.date,
                title: event.title,
                details: event.details
            )
        }
    }

    private static func timelineKind(for type: AnimalTimelineEventType) -> TimelineKind {
        switch type {
        case .birth: return .birth
        case .health: return .health
        case .pregnancy: return .pregnancy
        case .movement: return .movement
        case .status: return .status
        case .tag: return .tag
        }
    }

    private static func assertCreateTimelineProjection(
        detail: AnimalDetailSnapshot,
        repository: any AnimalRepository,
        expectedTags: [AnimalTagSnapshot],
        file: StaticString,
        line: UInt
    ) throws {
        let timeline = try repository.fetchTimeline(id: detail.id)

        let damDisplay = try detail.damID.flatMap { damID in
            try repository.fetchAnimalDetail(id: damID)?
                .displayTagNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let sireDisplay = try detail.sireID.flatMap { sireID in
            try repository.fetchAnimalDetail(id: sireID)?
                .displayTagNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var birthDetails: [String] = []
        if let damDisplay, !damDisplay.isEmpty {
            birthDetails.append("Dam: \(damDisplay)")
        }
        if let sireDisplay, !sireDisplay.isEmpty {
            birthDetails.append("Sire: \(sireDisplay)")
        }
        if let pastureName = detail.pastureName, !pastureName.isEmpty {
            birthDetails.append("Pasture: \(pastureName)")
        }

        var expected: [TimelineSignature] = [
            TimelineSignature(
                kind: .birth,
                date: detail.birthDate,
                title: "Birth",
                details: birthDetails.isEmpty ? nil : birthDetails.joined(separator: " • ")
            )
        ]
        for tag in expectedTags {
            expected.append(
                TimelineSignature(
                    kind: .tag,
                    date: tag.assignedAt,
                    title: "Tag Assigned",
                    details: tag.normalizedNumber
                )
            )
            if let removedAt = tag.removedAt {
                expected.append(
                    TimelineSignature(
                        kind: .tag,
                        date: removedAt,
                        title: "Tag Retired",
                        details: tag.normalizedNumber
                    )
                )
            }
        }

        XCTAssertEqual(
            multisetCounts(allTimelineSignatures(timeline)),
            multisetCounts(expected),
            "Aggregate create must expose exactly the birth projection plus persisted tag assignment/retirement history, without synthetic status or movement transitions.",
            file: file,
            line: line
        )
    }

    private static func multisetCounts<T: Hashable>(_ values: [T]) -> [T: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private static func assertExactlyOneTimelineEventAdded(
        kind: TimelineKind,
        before: [AnimalTimelineEvent],
        after: [AnimalTimelineEvent],
        expectedTitle: String,
        expectedDetails: String?,
        message: String,
        file: StaticString,
        line: UInt
    ) {
        let beforeCounts = multisetCounts(timelineSignatures(kind, in: before))
        let afterCounts = multisetCounts(timelineSignatures(kind, in: after))
        var added: [TimelineSignature] = []
        var removedCount = 0

        for signature in Set(beforeCounts.keys).union(afterCounts.keys) {
            let delta = afterCounts[signature, default: 0] - beforeCounts[signature, default: 0]
            if delta > 0 {
                added.append(contentsOf: repeatElement(signature, count: delta))
            } else if delta < 0 {
                removedCount += -delta
            }
        }

        XCTAssertEqual(
            removedCount,
            0,
            "Appending timeline history must not remove or rewrite existing events.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            added.count,
            1,
            "The operation must append exactly one new timeline event of the expected kind.",
            file: file,
            line: line
        )
        guard let appended = added.first else { return }
        XCTAssertEqual(appended.title, expectedTitle, message, file: file, line: line)
        XCTAssertEqual(appended.details, expectedDetails, message, file: file, line: line)
    }

    private static func assertCompleteStoreSnapshot(
        _ snapshot: PersistenceTransactionRollbackStateSnapshot,
        operation: String,
        file: StaticString,
        line: UInt
    ) {
        let expectedKinds = Set(IdentityContractEntityKind.allCases)
        XCTAssertEqual(Set(snapshot.applicationIDsByKind.keys), expectedKinds, file: file, line: line)
        XCTAssertEqual(Set(snapshot.persistedRowCountsByKind.keys), expectedKinds, file: file, line: line)
        XCTAssertTrue(
            snapshot.persistedRowCountsByKind.values.allSatisfy { $0 >= 0 },
            "Persisted row counts for \(operation) must never be negative.",
            file: file,
            line: line
        )
    }
}
