import Foundation

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

/// Atomic create of an animal aggregate.
///
/// The supplied animal and tag UUIDs are authoritative application identities. A successful
/// write commits the animal, parent/pasture relationships, primary-tag state, and every tag in
/// `tags` as one transaction. A thrown error must leave none of those changes committed.
struct CreateAnimalAggregateTransaction: Hashable {
    let animalID: UUID
    let input: AnimalInput
    let tags: [AnimalTagTransactionState]
}

/// Atomic replacement of the persisted state owned by the animal editor.
///
/// `tags` is the complete desired tag state after the update. Existing tags are matched by UUID;
/// new UUIDs create tags, and existing tags with `isActive == false` remain as retired history.
/// The transaction must also include any status or pasture-movement history caused by `input`.
struct UpdateAnimalAggregateTransaction: Hashable {
    let animalID: UUID
    let input: AnimalInput
    let tags: [AnimalTagTransactionState]
}

/// Persistence-neutral atomic boundary for animal editor writes.
///
/// Implementations must commit once after the entire aggregate mutation succeeds. They must not
/// expose a partially-created animal, partially-updated tag set, or history record without the
/// corresponding aggregate change. Mutation publication/sync scheduling occurs only after commit.
@MainActor
protocol AnimalAggregateTransactionWriting {
    @discardableResult
    func createAnimal(
        _ transaction: CreateAnimalAggregateTransaction
    ) throws -> AnimalDetailSnapshot

    @discardableResult
    func updateAnimal(
        _ transaction: UpdateAnimalAggregateTransaction
    ) throws -> AnimalDetailSnapshot
}

/// Atomic pasture-delete request.
///
/// Deleting a pasture is one logical transaction even though it affects multiple features:
/// resident animals are removed from the deleted pasture with movement history preserved,
/// field-check sessions retain their historical pasture snapshot/archive marker, and only then
/// are the pasture records deleted. Failure at any point must leave all of those records unchanged.
struct DeletePasturesTransaction: Hashable {
    let pastureIDs: [UUID]
    let archivedAt: Date
}

/// Persistence-neutral atomic boundary for destructive pasture changes that span aggregates.
@MainActor
protocol PastureDeletionTransactionWriting {
    func deletePastures(_ transaction: DeletePasturesTransaction) throws
}
