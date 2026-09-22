For the core data refactor and gutting SwiftData, this is the detailed implementation plan and milestone sequence. The approach remains test-first: establish persistence-neutral behavior contracts before changing the physical data model.

# Core Data / SwiftData Replacement Execution Plan

## Target state

The finished persistence stack is local-only:

```text
SwiftUI / Presentation
        ↓
Domain repository + transaction contracts
        ↓
Core Data repositories
        ↓
NSPersistentContainer
        ↓
Local Core Data persistent store
```

There is no iCloud/CloudKit synchronization, shared store, cross-user herd collaboration, mirror graph, or synchronization bridge in the target architecture.

## Milestone 0 — Freeze the behavioral contract with reusable tests

This is the first implementation milestone.

The goal is not to test SwiftData. The goal is to define what yaHerd persistence is required to do regardless of storage technology.

Create a reusable persistence contract-test structure under something like:

```text
yaHerdTests/
  RepositoryContracts/
    AnimalRepositoryContract.swift
    PastureRepositoryContract.swift
    FieldCheckRepositoryContract.swift
    WorkingRepositoryContract.swift
    HerdRepositoryContract.swift
    TagColorRepositoryContract.swift
    HealthRepositoryContract.swift
    IdentityContract.swift
    MutationBoundaryContract.swift
```

The reusable tests operate through Domain repository and transaction protocols. They should not import SwiftData, use `ModelContext`, inspect SwiftData models, or depend on fetch implementation.

Do **not** add or restore a SwiftData contract harness. SwiftData is the outgoing implementation and repository-wide instructions prohibit investing in new SwiftData verification infrastructure. Persistence-neutral contracts may remain without an executable persistence runner during Milestone 0 when the only available runner would be SwiftData-specific. As the corresponding Core Data repositories are implemented, a Core Data harness runs the permanent contract suites and supplies target-only rollback/historical inspection hooks.

Coverage must include at least:

- **Identity:** UUID survives create/read/update/reload; relationships resolve by application UUID within the applicable repository/Herd scope; IDs never change during edits; duplicate application IDs inside the same identity scope fail rather than silently producing a second logical entity; cross-Herd reuse remains feature-contract-owned rather than assumed globally valid or invalid.
- **Animal aggregate:** create tagged and untagged animals; update scalar fields; sire/dam relationships; pasture assignment; active/retired tags; exactly-one-primary-tag rules; tag retirement history; stale aggregate revision rejection; failed aggregate update leaves the original aggregate unchanged.
- **Animal state/history:** active/sold/deceased/archive behavior; status changes create appropriate history; movement changes current pasture and records movement history; historical data remains readable after related live records disappear where that is product behavior.
- **Pastures:** create/update/order/group behavior; resident queries; movement into/out of pasture; pasture deletion moves residents according to the Domain plan; field-check history retains pasture snapshots after deletion; target Core Data contracts cover full rollback of the delete workflow.
- **Field Check:** create session; expected-head-count snapshot; tracked animals; counted/missing state; findings; finding-to-animal/session associations; completed session behavior; archived-pasture behavior.
- **Working:** create session; collect animals; move animals into working-pen state; queue-item lifecycle; treatment records; pregnancy checks; generated health records; edit completed work; complete session and return animals; destination assignment validation; delete active session and restore animals; rollback when a multi-record operation fails.
- **Reference/support data:** tag colors, animal status references, treatment templates, Herd scoping, sorting and visibility behavior used by Presentation.
- **Mutation semantics:** failed persistence operations do not publish successful mutation events; successful logical operations publish only after commit.

**Gate to leave Milestone 0:** important current workflows are represented by reusable contracts and we can point to a contract for every high-risk behavior Core Data must preserve. Contracts that require Core Data-only historical storage or fault injection may remain unexecuted until their Core Data runner exists. Do not add new target-only production behavior, adapters, or verification infrastructure to SwiftData solely to make a future Core Data contract pass.

## Milestone 1 — Finalize the Core Data model blueprint

Reconcile `Info/CORE_DATA_MODEL_BLUEPRINT.md` against anything the behavior contracts reveal.

The blueprint is based on the finished product rather than cloning SwiftData. Current core decisions should remain unless tests expose a real product requirement:

- UUID application identity on every durable entity;
- `AnimalTag` as the authoritative persisted tag state;
- derived animal location;
- explicit historical snapshots;
- Herd as the local ownership/scope root;
- no collaboration revision records, sharing metadata, mirror entities, or bridge repair state;
- no migration support for development SwiftData stores;
- no CloudKit-derived schema compromises.

Produce a clear mapping from each Domain contract to the Core Data entities it depends on.

**Gate:** every persisted field and relationship has an application purpose, delete behavior and history semantics are decided, and no field exists merely because SwiftData, CloudKit, or the old sharing bridge once used it.

## Milestone 2 — Add the production Core Data model, but do not cut the app over

Create `yaHerdModel.xcdatamodeld` from the approved blueprint. SwiftData remains the running implementation during this milestone.

Define managed-object classes, application UUID attributes, inverse relationships, delete rules, indexes, optionality, and local Core Data constraints based on product requirements rather than CloudKit compatibility rules.

Add schema tests that inspect `NSManagedObjectModel` directly. These are separate from repository contracts and verify expected entities, UUID attributes, relationship inverses, delete rules, intended uniqueness constraints, and absence of accidental SwiftData/sync compatibility entities.

**Gate:** the Core Data model loads independently and its structural tests pass when verification is explicitly requested.

## Milestone 3 — Build the final Core Data persistence foundation

Introduce the infrastructure that survives production:

```text
Data/Persistence/CoreData/
  CoreDataPersistenceAssembly
  CoreDataPersistentContainer
  CoreDataTransactionExecutor
  CoreDataContextFactory
  CoreDataLookup
  CoreDataPersistenceError
```

Use `NSPersistentContainer` with one local persistent store. Establish context policy, private write contexts where appropriate, merge policy for local contexts, transaction boundaries, rollback behavior, deterministic Herd scoping, store-load error handling, and recovery-mode integration.

No SwiftData/Core Data bridge is created.

**Gate:** the Core Data harness can create a local store, insert managed objects, save/reload them, and prove UUID/Herd-scope behavior independently of the app.

## Milestone 4 — Implement low-dependency Core Data repositories

Start with graph roots and simpler repositories because everything else depends on them:

- Herd;
- pasture groups;
- pastures;
- tag colors;
- animal status references;
- treatment templates.

For each repository, point the same contract suite created in Milestone 0 at a Core Data runner.

SwiftData and Core Data temporarily coexist in source, but the app still uses SwiftData. This is not dual-writing; each implementation is isolated and Core Data is exercised only by its harness until the decisive runtime cutover.

**Gate:** Core Data satisfies the relevant permanent contracts without weakening them to accommodate implementation details.

## Milestone 5 — Implement the Animal aggregate and transaction boundary

Implement Animal, AnimalTag, parent relationships, status records, movements, health records, pregnancy checks, archive state, and editor aggregate revision handling.

`AnimalAggregateTransactionWriting` becomes a real Core Data transaction rather than several repository saves.

Create and update execute within one transaction context. Tag reconciliation, history generation, pasture/parent relationships, stale-revision checking, and aggregate revision rotation happen before the final save. Any failure rolls back the entire logical edit.

This milestone also removes the current duplicated tag-number/color persistence in favor of the production `AnimalTag` model.

**Gate:** animal/identity/history/transaction contracts cover success, deliberately injected failures, and stale-edit conflicts against Core Data.

## Milestone 6 — Implement Pasture deletion and movement transactions

Replace the current sequential pasture-deletion behavior with the transaction boundary already defined in Domain.

The transaction revalidates expected pasture/resident state, moves affected animals, creates movement history, preserves Field Check snapshots/history, and deletes pasture records in one atomic operation.

Animal movement should have a clean reusable Core Data implementation because Working and pasture workflows both depend on it.

**Gate:** the Core Data contract cannot observe the half-completed state possible in the current multi-save SwiftData sequence.

## Milestone 7 — Implement Field Check persistence

Port Field Check sessions, tracked-animal checks, findings, quick counts, snapshots, completion/archive behavior, and repository operations.

Historical semantics matter more here than live relationships. The Core Data model must preserve snapshots the UI expects even when an animal or pasture later changes or disappears.

Multi-record commands remain transactionally atomic.

**Gate:** the Field Check contract suite covers the Core Data implementation, including pasture deletion/history behavior.

## Milestone 8 — Implement Working persistence

Port working sessions, queue items, treatment records, pregnancy checks linked to working sessions, generated health records, and treatment templates.

Preserve useful current behavior while dropping deprecated storage concepts such as queue indices/order and old persistence terminology.

Atomic operations remain atomic: collect animals, complete queue item, save queue-item edits, complete session, and delete session.

**Gate:** Working contracts cover animal-location restoration, treatment replacement, destination assignment validation, and rollback behavior against Core Data.

## Milestone 9 — Port read models and performance-sensitive queries

Once authoritative write-side repositories exist, implement Dashboard, Home, animal lists, search/filtering, metrics, and other read-heavy paths directly against Core Data.

Avoid recreating the current "fetch everything and filter on the main actor" behavior. Perform filtering, sorting, counts, grouping, and projections in Core Data where practical.

Persistence work should not automatically remain `@MainActor` merely because SwiftData previously required it.

**Gate:** feature snapshots preserve contract-defined behavior while query boundaries are appropriate for real herd sizes.

## Milestone 10 — Cut AppDependencies over to Core Data

This is the decisive runtime switch.

`CoreDataPersistenceAssembly` becomes the application persistence assembly. All feature dependency containers receive Core Data-backed implementations of the existing Domain contracts.

SwiftUI does not receive `NSManagedObjectContext`, `NSPersistentContainer`, or managed objects.

The app either runs entirely on Core Data or fails visibly during development. There is no fallback to SwiftData and no screen-by-screen hybrid runtime.

**Gate:** every production dependency path resolves to Core Data and no runtime read/write path uses SwiftData.

## Milestone 11 — Gut SwiftData and obsolete persistence infrastructure

Once the cutover is proven, delete rather than adapt.

Remove:

- SwiftData models and schemas;
- SwiftData repositories and read actors;
- SwiftData persistence assembly;
- `ModelContainer` / `ModelContext` startup;
- SwiftData schema/migration infrastructure;
- SwiftData-specific public-ID repair machinery that has no local Core Data requirement;
- obsolete migration/repair diagnostics;

Sync/share/CloudKit bridge infrastructure is already outside the target architecture and must not be recreated during the Core Data cutover.

Domain tests and reusable persistence contracts remain.

**Gate:** production-code search finds no SwiftData runtime dependency and no sync/share bridge architecture.

## Milestone 12 — Harden the final architecture

Add architecture checks that prevent regression.

Production Domain and Presentation must not import Core Data. Only Data/App persistence implementation may know managed-object/context/store types.

Architecture verification should explicitly reject SwiftData imports and sync/share/CloudKit persistence infrastructure.

Add final Core Data integration contracts for delete rules, transaction rollback, UUID integrity, Herd scoping, local store recovery, and mapping.

Update `Info/ARCHITECTURE.md` to describe the implemented system rather than the transition. Delete `Info/CORE_DATA_CUTOVER.md` when the transition is complete.

**Final completion gate:** Core Data is the sole local persistence system; the permanent behavior suite covers it; SwiftData is gone; no iCloud/CloudKit/shared-store path exists; UUIDs are authoritative application identity; important multi-record workflows are transactional; and architecture checks prevent reintroducing persistence coupling or synchronization infrastructure.

## How to use this plan

Treat each milestone as a merge gate. Do not start the next persistence layer simply because code exists; the contracts and design requirements for the current milestone should be satisfied first.

PRs should stay focused enough to review. Animal and Working may require multiple PRs, but do not introduce transitional persistence architectures just to make the PR sequence easier.

The ordering is:

```text
Permanent behavioral contracts
        ↓
Core Data schema
        ↓
Local Core Data infrastructure
        ↓
Repositories + real transactions
        ↓
Read models
        ↓
One-time app cutover
        ↓
Delete SwiftData
        ↓
Architecture enforcement
```

The next implementation work should follow the first incomplete milestone rather than reintroducing removed sync/share concerns.
