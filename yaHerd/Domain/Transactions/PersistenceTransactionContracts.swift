import Foundation

/// Optimistic-concurrency token for the editor-owned animal aggregate.
///
/// This is not entity identity. The production persistence layer rotates the token whenever
/// editor-owned animal fields or tag state change, including changes imported from CloudKit.
struct AnimalAggregateRevision: Hashable, Sendable {
    let value: UUID
}

/// Persisted animal fields owned by the animal editor, excluding tag state.
///
/// Tag number/color do not appear here intentionally. `tags` in the aggregate transaction is the
/// single source of truth for primary and secondary tag state in the production Core Data model.
struct AnimalAggregateAttributes: Hashable {
    let name: String
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let pastureID: UUID?
    let sireID: UUID?
    let damID: UUID?
    let distinguishingFeatures: [DistinguishingFeature]
    let saleDate: Date?
    let salePrice: Double?
    let reasonSold: String?
    let deathDate: Date?
    let causeOfDeath: String?
    let statusReferenceID: UUID?
}

/// Complete desired state for one animal tag inside an aggregate transaction.
///
/// `id` is application identity. Persistence implementations must preserve it exactly;
/// storage-native object identifiers are not part of this contract.
struct AnimalTagTransactionState: Hashable {
    let id: UUID
    let number: String
    let colorID: UUID?
    let isPrimary: Bool
    let isActive: Bool
}

/// Editor read result that carries the aggregate revision used for optimistic conflict detection.
struct AnimalAggregateEditSnapshot: Hashable {
    let animal: AnimalDetailSnapshot
    let revision: AnimalAggregateRevision
}

/// Persistence-neutral read required before editing an existing animal aggregate.
@MainActor
protocol AnimalAggregateEditReading {
    func fetchAnimalAggregateForEditing(id: UUID) throws -> AnimalAggregateEditSnapshot?
}

/// Atomic create of an animal aggregate.
///
/// The supplied animal and tag UUIDs are authoritative application identities. `tags` is the only
/// source of primary-tag state. Untagged animals may have no active tags; otherwise the request must
/// contain exactly one active primary tag. A thrown error leaves none of the aggregate committed.
struct CreateAnimalAggregateTransaction: Hashable {
    let animalID: UUID
    let attributes: AnimalAggregateAttributes
    let tags: [AnimalTagTransactionState]
}

/// Atomic replacement of the state owned by the animal editor.
///
/// `expectedRevision` is the revision from the editor read. The persistence implementation must
/// compare it with the current stored revision before applying any changes and fail the transaction
/// when they differ. `tags` is the complete desired tag state: existing tags are matched by UUID,
/// new UUIDs create tags, and inactive tags remain as retired history.
struct UpdateAnimalAggregateTransaction: Hashable {
    let animalID: UUID
    let expectedRevision: AnimalAggregateRevision
    let attributes: AnimalAggregateAttributes
    let tags: [AnimalTagTransactionState]
}

/// Persistence-neutral atomic boundary for animal editor writes.
///
/// Implementations commit only after the complete aggregate mutation succeeds and return the new
/// revision. Any mutation of editor-owned animal fields or tag state must rotate the revision so a
/// stale editor cannot silently overwrite a remote/imported change. Mutation publication and sync
/// scheduling occur only after commit.
@MainActor
protocol AnimalAggregateTransactionWriting {
    @discardableResult
    func createAnimal(
        _ transaction: CreateAnimalAggregateTransaction
    ) throws -> AnimalAggregateEditSnapshot

    @discardableResult
    func updateAnimal(
        _ transaction: UpdateAnimalAggregateTransaction
    ) throws -> AnimalAggregateEditSnapshot
}

/// State observed by the Domain use case while preparing a pasture-deletion transaction.
///
/// The transaction implementation revalidates this exact resident set before applying operations.
/// If the pasture disappeared or its resident set changed, the transaction fails as stale rather
/// than discovering a new workflow on behalf of Domain.
struct PastureDeletionExpectedState: Hashable {
    let pastureID: UUID
    let residentAnimalIDs: Set<UUID>
}

/// Ordered operation selected by the Domain pasture-delete workflow.
enum PastureDeletionOperation: Hashable {
    case moveAnimals(
        animalIDs: [UUID],
        fromPastureID: UUID,
        toPastureID: UUID?
    )
    case archiveFieldChecks(
        pastureIDs: [UUID],
        archivedAt: Date
    )
    case deletePastures(ids: [UUID])
}

/// Normalized plan produced by the Domain use case for one atomic pasture deletion.
///
/// Domain owns which operations occur and their order. Persistence owns stale-state validation,
/// executing the supplied operations on one transaction context, and commit/rollback.
struct DeletePasturesTransactionPlan: Hashable {
    let expectedStates: [PastureDeletionExpectedState]
    let operations: [PastureDeletionOperation]
}

/// Persistence-neutral atomic boundary for destructive pasture changes that span aggregates.
@MainActor
protocol PastureDeletionTransactionWriting {
    func deletePastures(_ plan: DeletePasturesTransactionPlan) throws
}
