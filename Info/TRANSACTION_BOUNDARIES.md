# Persistence Transaction Boundaries

This document defines the transaction model for the production persistence layer. The target implementation is Core Data with `NSPersistentCloudKitContainer`. These boundaries are application contracts; they do not expose SwiftData, Core Data, `ModelContext`, `NSManagedObjectContext`, persistent object IDs, or CloudKit record IDs.

## Commit rule

A method documented as a transaction boundary has only two externally visible outcomes:

- success: every mutation in the logical operation is durably committed
- failure: none of the logical operation is durably committed

Repository reads and validation may occur before a transaction begins, but any validation that can become stale before the write must be repeated inside the persistence transaction. Mutation notifications, UI invalidation, CloudKit/share synchronization requests, and other post-write side effects are published only after the commit succeeds.

Do not implement transaction boundaries by chaining independently-saving repositories. The production Core Data implementation must use one write context/transaction and one final save for the logical operation.

## New explicit cross-aggregate contracts

`Domain/Transactions/PersistenceTransactionContracts.swift` defines the transaction ports that are missing from the current repository surface.

### Animal aggregate create/update

`AnimalAggregateTransactionWriting` owns editor writes that affect an animal plus its tag set and any status/movement history caused by the edit.

The final Core Data aggregate has one source of tag truth. `AnimalAggregateAttributes` deliberately excludes `tagNumber` and `tagColorID`; the transaction's complete `tags` collection owns primary, secondary, and retired tag state. Do not reproduce the current SwiftData pattern where primary-tag fields are also stored independently on the animal. An untagged animal may have no active tags. Otherwise the complete desired state must contain exactly one active primary tag, and inactive tags cannot remain primary.

The transaction includes, as applicable:

- animal creation or scalar updates
- sire/dam relationship changes
- pasture assignment and movement history
- status transition history
- primary-tag replacement
- tag creation/update/retirement

A failed tag or relationship mutation must not leave the animal edit committed, and a failed animal edit must not leave tag/history mutations committed.

#### Stale-editor conflict protection

Animal editor reads use `AnimalAggregateEditReading` and receive an `AnimalAggregateRevision` together with the `AnimalDetailSnapshot`. The revision is an optimistic-concurrency token, not entity identity.

The production Core Data model must store this revision with the animal aggregate. Any successful mutation of fields or tag state owned by the animal editor rotates the revision, including equivalent changes arriving from CloudKit. `UpdateAnimalAggregateTransaction` carries the revision observed when the editor loaded the record.

Before changing any object, the Core Data transaction implementation must re-fetch the current aggregate and compare the stored revision to `expectedRevision`. A mismatch means the editor is stale and the write must fail without committing any part of the request. The caller can then reload or present conflict handling instead of silently replacing another collaborator's imported changes.

This guards stale local editors after remote imports. It does not replace Core Data/CloudKit merge policy for truly concurrent offline commits; the production synchronization layer must still handle those persistent-store conflicts deliberately.

### Pasture deletion

Pasture deletion remains a Domain-owned workflow. The persistence layer does not discover residents or decide which cross-feature operations should occur.

`DeletePasturesUseCase` (or its final equivalent) should:

1. validate the requested pasture IDs
2. load the current resident animals for each target pasture
3. build `PastureDeletionExpectedState` values from that observed state
4. build an ordered `DeletePasturesTransactionPlan` describing the moves, field-check archival, and final deletions
5. submit that plan once to `PastureDeletionTransactionWriting`

The normal operation order is:

1. move the use-case-selected resident animals out of deleted pastures and preserve movement history
2. preserve/archive field-check pasture snapshots needed for historical sessions
3. delete the selected pasture records and repair affected relationships

Persistence owns one atomic execution boundary, not the workflow decision. At the start of the transaction it must revalidate that every expected pasture still exists and that each pasture's resident set exactly matches `expectedStates`. If that state changed after the use case prepared the plan, the transaction fails as stale instead of silently selecting a different set of animals. It then executes the supplied operations in order on one context and performs one final save.

If any validation or operation fails, none of the moves, archive markers, relationship changes, or deletions may be committed.

## Existing repository methods that are already transaction contracts

Several existing repository methods already describe a complete logical mutation in one call. Their production Core Data implementations must preserve that atomic meaning rather than splitting them into independently-saving repositories. Important examples include:

- `WorkingAnimalCollecting.collectAnimals`
- `WorkingQueueItemCompleting.complete`
- `WorkingQueueItemEditSaving.saveEdits`
- `WorkingSessionCompleting.completeSession`
- `WorkingSessionDeleting.deleteSession`
- `FieldCheckSessionStarting.createSession`
- `FieldCheckTrackedAnimalWriting.addTrackedAnimalToSession`
- finding writes that also update missing/count state
- `AnimalPastureMoving.move`

The fact that one protocol method is called does not by itself make an implementation transactional; the persistence adapter is responsible for one commit/rollback boundary.

## Core Data cutover rule

The current SwiftData stack is not a production migration target. Do not add compatibility transaction adapters, dual-write layers, or temporary SwiftData implementations solely to satisfy these new ports. When the Core Data persistence layer is introduced, the animal editor and pasture-delete workflows should be wired directly to these production transaction contracts and the old multi-save SwiftData paths removed.

The same rule applies to identity: application UUIDs are authoritative. Core Data object IDs are implementation details and must not cross the Data boundary. Aggregate revision tokens are concurrency state and must never be substituted for application UUID identity.

## Use-case responsibility

Domain use cases own validation, workflow policy, the meaning/order of cross-feature operations, and construction of normalized transaction plans. Persistence owns atomic commit/rollback and stale-state validation immediately before mutation.

A use case must not recreate a transaction by making several independently-saving persistence calls. Conversely, a persistence transaction implementation must not absorb cross-feature business orchestration merely because it owns the commit boundary.

This keeps the final architecture split cleanly:

`Presentation -> Domain use case/transaction plan -> Core Data transaction implementation -> NSPersistentCloudKitContainer`
