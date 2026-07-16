# SwiftData/Core Data Sharing Bridge Reliability

The sharing bridge is the highest-risk persistence subsystem in yaHerd. SwiftData is the application store. A separate `NSPersistentCloudKitContainer` exists only to support CloudKit sharing. Neither store may be treated as independently authoritative during synchronization.

## Required synchronization order

1. Resolve whether the herd is in the owner private bridge store or an accepted shared bridge store.
2. Import the selected bridge state into SwiftData.
3. Commit the SwiftData import as one save.
4. Reload the SwiftData snapshot.
5. Export the merged snapshot into the writable bridge store.
6. Commit all bridge entity changes and deletion tombstones as one Core Data save.
7. Reconcile application-managed public IDs and counts.
8. Update the existing CloudKit share when required.

Read-only participants stop after import and reconciliation.

## Operation serialization

`HerdSharingBridgeOperationGate` serializes every repository-level bridge mutation, including share creation, invitation acceptance, import, sync, delete acceptance, and conflict restoration. The gate remains held across `await` suspension points so a second operation cannot capture or commit a snapshot while the first operation is partially complete. This intentionally favors correctness over parallel bridge throughput.

## Transaction journal and checkpoints

`HerdSharingBridgeJournal` is a local sidecar journal stored beside the bridge SQLite stores. It records:

- herd public ID;
- import or export direction;
- owner-private or accepted-shared source/target;
- operation ID and retry count;
- every completed entity step;
- failure details;
- the pre-import conflict snapshot required for local-field restoration after an interrupted commit;
- the last successful record counts and reconciliation summary.

An unfinished operation is reused on retry, but all entity steps run again. Steps are not skipped because the process may have terminated after the journal write but before the persistent-store commit. Import and export operations are designed to be idempotent.

## Atomicity rules

- Export entity mirror methods defer their normal saves while an export transaction is active. The Core Data bridge context is saved once after every entity and tombstone has been applied.
- SwiftData imports save once after all upserts and deletion reconciliation have completed.
- A failure before the final save rolls back the affected context.
- A failure after the final save is retried from the beginning. Reapplying the same public-ID-based upserts is required to be safe.
- The conflict report is journaled before the SwiftData commit. A retry keeps recovered conflicts for records that no longer produce a fresh diff because the interrupted attempt already committed, while a fresh comparison replaces recovered evidence for the same record.
- Existing unsaved context changes are committed before starting a bridge transaction so rollback cannot discard unrelated work.

## Duplicate public IDs

CloudKit-backed SwiftData does not provide a reliable uniqueness constraint for this design. Public IDs are application-managed.

- SwiftData duplicates block export. The user must not propagate an ambiguous local snapshot.
- Writable Core Data bridge duplicates are reduced to the most recently mirrored record during export. Duplicate removal does not create deletion tombstones because a tombstone would delete the canonical record with the same public ID.
- Read-only imports select the most recently mirrored duplicate deterministically and retain the duplicate in the bridge store for owner-side repair.
- Every completed import/export includes a reconciliation report with local-only IDs, bridge-only IDs, and duplicate counts by entity type.

## Failure-injection gate

`HerdSharingBridgeFailureInjector` can fail after every entity step, deletion reconciliation, persistent-store commit, reconciliation, or CloudKit share update. Tests must cover every entity step whenever an entity is added or reordered.

A new shared entity is incomplete until all of the following are updated:

1. Core Data bridge model and relationships.
2. Export mirror step.
3. Import upsert step.
4. Deletion priority and tombstone handling.
5. Conflict snapshot and local restoration support where applicable.
6. Reconciliation public-ID mapping.
7. `HerdSharingBridgeStep.entitySteps`.
8. Failure-injection and retry tests.

## Required two-device release test

This cannot be replaced by simulator-only or unit testing. Before release, test on two physical devices signed into separate Apple IDs:

1. Owner creates and shares a herd with read/write permission.
2. Participant accepts the share and imports all entities.
3. Both devices edit different fields while online; verify merge and reconciliation are clean.
4. Both devices edit the same fields; verify conflict review uses the pre-import local snapshot.
5. Participant deletes records while owner is offline; verify owner imports tombstones before export and deleted records are not recreated.
6. Terminate each app after every failure-injection-equivalent entity boundary; relaunch and verify retry converges.
7. Repeat edits while one device is offline, then reconnect in both orders.
8. Verify owner imports participant changes from the private bridge store.
9. Verify read-only participants never export.
10. Verify no duplicate public IDs remain and no unresolved reconciliation differences are reported.

Record the device models, OS versions, Apple IDs used, operation sequence, journal output, reconciliation output, and final record counts in the release evidence.

## Long-term direction

The bridge remains transitional architecture. When SwiftData supports the required CloudKit sharing behavior with acceptable migration and conflict semantics, remove the duplicate Core Data model and move collaboration onto the primary persistence technology. Until then, changes to this subsystem require persistence-focused review and the tests above.
