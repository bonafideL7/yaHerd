# Persistence Concurrency Boundary

## SwiftData

- UI-facing mutation repositories may remain `@MainActor` when they operate on the app's main `ModelContext`.
- Dashboard, home, animal-list, collaboration export, collaboration import, shared-delete acceptance, and conflict restoration use dedicated `ModelActor` instances.
- Values crossing actor boundaries are immutable `Sendable` snapshots. SwiftData model instances and `ModelContext` values do not cross those boundaries.
- Collaboration imports perform conflict comparison, upserts, deletion reconciliation, relationship reconstruction, and the final SwiftData save on the actor-owned context.
- Collaboration exports use herd-scoped predicates and bounded 500-record pages before building the immutable bridge snapshot.

## Core Data sharing bridge

- Core Data bridge import reads and export writes use private queue contexts created by `NSPersistentCloudKitContainer`.
- `NSManagedObject` instances remain inside the context that owns them.
- Queue boundaries return immutable bridge snapshots, permanent object-ID URIs, counts, and reconciliation values.
- Export writes select the target persistent store explicitly and save once per bridge transaction.
- Import reads select the source persistent store explicitly and do not mutate the view context.
- The operation journal owns its file reads and atomic writes on a dedicated actor rather than the main actor.
- Legacy bulk exporters that accepted arrays of live SwiftData models have been removed.

## Operation order

1. Read the selected Core Data bridge store into an immutable snapshot.
2. Apply that snapshot through the SwiftData sharing actor.
3. Reload a merged SwiftData export snapshot through the actor.
4. Write the merged snapshot through a private Core Data context.
5. Reconcile public IDs and complete the actor-isolated operation journal.

## Validation

- Strict Swift 6 and architecture checks run in the pull-request workflow.
- A deterministic 2,500-animal fixture verifies paged collaboration export and exclusion of records belonging to another herd.
- Persistence signposts cover home, dashboard, animal-list derivation, collaboration snapshot creation, import application, deletion acceptance, and conflict restoration.

Do not place existing repository calls inside `Task.detached`. Persistent contexts must remain isolated to their owning actor or Core Data queue.
