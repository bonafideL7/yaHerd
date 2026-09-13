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

`AnimalAggregateTransactionWriting` owns editor writes that affect an animal plus its tag set and any history records caused by the edit. The create/update requests carry stable application UUIDs and complete desired tag state.

The transaction includes, as applicable:

- animal creation or scalar updates
- sire/dam relationship changes
- pasture assignment and movement history
- status transition history
- primary-tag replacement
- tag creation/update/retirement

A failed tag or relationship mutation must not leave the animal edit committed, and a failed animal edit must not leave tag/history mutations committed.

### Pasture deletion

`PastureDeletionTransactionWriting` owns the destructive cross-feature write currently represented by the pasture-delete workflow. In one transaction it must:

1. verify every requested pasture UUID still exists and the request has no duplicate IDs
2. move resident animals out of deleted pastures and preserve movement history
3. preserve/archive field-check pasture snapshots needed for historical sessions
4. delete the pasture records and repair affected relationships

If any step fails, none of the moves, archive markers, relationship changes, or deletions may be committed.

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

The current SwiftData stack is not a production migration target. Do not add compatibility transaction adapters, dual-write layers, or temporary SwiftData implementations solely to satisfy these new ports. When the Core Data persistence layer is introduced, the animal editor and pasture-delete workflows should be wired directly to the Core Data implementations of these contracts and the old multi-save SwiftData paths can be removed.

The same rule applies to identity: application UUIDs are authoritative and must survive persistence replacement. Core Data object IDs are implementation details and must not cross the Data boundary.

## Use-case responsibility

Domain use cases still own validation, workflow policy, and the meaning/order of cross-feature operations. Persistence owns atomic commit/rollback. A use case may build a normalized transaction request, but it must not recreate the transaction by making several independent persistence calls.

This keeps the final architecture split cleanly:

`Presentation -> Domain use case/transaction port -> Core Data transaction implementation -> NSPersistentCloudKitContainer`
