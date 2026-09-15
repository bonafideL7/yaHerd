For the core data refactor and gutting swift data, layout a detailed plan with milestones that you can follow and understand. you'll be doing all the work. I agree with the approach of first establishing tests before changing the data model.

Yes. With that change, the safest sequence is **characterize and lock behavior first, then replace persistence underneath it**. The existing SwiftData implementation becomes the behavioral reference, but the tests themselves should be written so they survive the cutover and run unchanged against Core Data.

The existing **Core Data model blueprint PR #75 is still valid** because it is documentation only; it does not modify the persistence model. I would not add the `.xcdatamodeld` or Core Data runtime implementation until the test milestone below is complete.

# Core Data / SwiftData Replacement Execution Plan

## Milestone 0 — Freeze the behavioral contract with reusable tests

This is now the first implementation milestone.

The goal is not to test SwiftData. The goal is to define what yaHerd persistence is required to do regardless of storage technology.

I will create a reusable persistence contract-test structure under something like:

```text
yaHerdTests/
  PersistenceContracts/
    PersistenceContractHarness.swift
    AnimalRepositoryContractTests.swift
    AnimalAggregateTransactionContractTests.swift
    PastureRepositoryContractTests.swift
    PastureDeletionTransactionContractTests.swift
    FieldCheckRepositoryContractTests.swift
    WorkingRepositoryContractTests.swift
    HerdRepositoryContractTests.swift
    TagColorRepositoryContractTests.swift
    HealthRepositoryContractTests.swift
    IdentityContractTests.swift
    MutationBoundaryContractTests.swift

  SwiftDataPersistenceContracts/
    SwiftDataContractHarness.swift
```

The reusable tests will operate through Domain repository and transaction protocols. They should not import SwiftData, use `ModelContext`, inspect SwiftData models, or depend on fetch implementation.

The SwiftData harness will exist only to instantiate the current implementation and prove the contracts describe actual intended behavior. Later we add a Core Data harness to the same tests. Once Core Data passes them and SwiftData is removed, only the small SwiftData harness disappears; the contract tests remain permanently.

The behavioral coverage needs to include at least these areas:

- **Identity:** UUID survives create/read/update/reload; relationships resolve by application UUID; IDs never change during edits; duplicate application IDs fail rather than silently producing a second logical entity.
- **Animal aggregate:** create tagged and untagged animals; update scalar fields; sire/dam relationships; pasture assignment; active/retired tags; exactly-one-primary-tag rules; tag retirement history; stale aggregate revision rejection; failed aggregate update leaves the original aggregate unchanged.
- **Animal state/history:** active/sold/deceased/archive behavior; status changes create appropriate history; movement changes current pasture and records movement history; historical data remains readable after related live records disappear where that is part of product behavior.
- **Pastures:** create/update/order/group behavior; resident queries; movement into/out of pasture; pasture deletion moves residents according to the Domain plan; field-check history retains pasture snapshots after deletion; the whole delete workflow rolls back on failure.
- **Field Check:** create session; expected-head-count snapshot; tracked animals; counted/missing state; findings; finding-to-animal/session associations; completed session behavior; archived-pasture behavior.
- **Working:** create session; collect animals; move animals into working-pen state; queue-item lifecycle; treatment records; pregnancy checks; observations/castration generated records; edit completed work; complete session and return animals; destination assignment validation; delete active session and restore animals; rollback when a multi-record operation fails.
- **Reference/support data:** tag colors, animal status references, treatment templates, herd ownership/scoping, sorting and visibility behavior used by Presentation.
- **Mutation semantics:** failed persistence operations do not publish successful mutation events; successful logical operations publish only after commit.

**Gate to leave Milestone 0:** the important current workflows are represented by reusable contracts, the current SwiftData implementation passes them, and we can point to a test for every high-risk behavior we intend Core Data to preserve.

This milestone replaces the earlier abandoned PR #71 approach. The difference is important: these are no longer temporary SwiftData-specific tests. They become the permanent specification for both implementations.

## Milestone 1 — Finalize the Core Data model blueprint

After the behavior suite exists, I will reconcile PR #75 against anything the tests reveal.

This is where we settle the final entity/relationship design before creating the actual model.

The blueprint remains based on the finished product rather than cloning SwiftData. The current decisions should remain unless tests expose a real product requirement: UUID application identity on every durable entity, `AnimalTag` as the only persisted tag state, derived animal location, explicit historical snapshots, Herd as the ownership/share root, no bridge revision records, no duplicate SwiftData compatibility fields, and no migration support for development SwiftData stores.

I will also produce a clear mapping from each Domain contract to the Core Data entities it depends on. That gives us a traceable reason for every field and relationship in the model.

**Gate:** every persisted field and relationship has an application purpose, delete behavior is decided, history semantics are decided, and there are no fields whose justification is merely “SwiftData used to have this.”

## Milestone 2 — Add the production Core Data model, but do not cut the app over

Create the real `yaHerdModel.xcdatamodeld` from the approved blueprint.

This PR establishes the physical schema only. SwiftData remains the running implementation.

I will define the managed-object classes, application UUID attributes, inverse relationships, delete rules, indexes, optionality, Core Data configurations, and CloudKit-compatible model characteristics.

This milestone also introduces **schema tests** that inspect `NSManagedObjectModel` directly. These are separate from repository contracts. They verify things such as required UUIDs, expected entities, relationship inverses, delete rules, configuration membership, forbidden unique constraints if they conflict with CloudKit requirements, and absence of accidental SwiftData compatibility entities.

No repository behavior changes yet.

**Gate:** the Core Data model can be loaded independently and its structural tests pass.

## Milestone 3 — Build the final Core Data persistence foundation

Introduce the infrastructure that will survive production:

```text
Data/Persistence/CoreData/
  CoreDataPersistenceAssembly
  CoreDataPersistentContainer
  CoreDataStoreRouter
  CoreDataTransactionExecutor
  CoreDataContextFactory
  CoreDataLookup
  CoreDataPersistenceError
```

Local-only mode uses a normal Core Data store.

iCloud mode uses one `NSPersistentCloudKitContainer` with the intended private/shared topology. Persistent history and remote-change support are configured here, not in Presentation.

Context policy is established here as well: view/read contexts, private write contexts where appropriate, merge policy, transaction boundaries, rollback behavior, and store assignment rules.

No SwiftData/Core Data bridge is created.

**Gate:** we can create local/private/shared test stores, insert managed objects, save/reload them, and prove UUID/store-routing behavior independently of the app.

## Milestone 4 — Implement low-dependency Core Data repositories

Start with the graph roots and simpler repositories because everything else depends on them.

This should cover Herd, pasture groups, pastures, tag colors, animal status references, and treatment templates.

For each repository, the exact same contract suite created in Milestone 0 will get a Core Data runner.

SwiftData and Core Data will temporarily coexist in source, but the app still uses SwiftData. This is not dual-writing; each implementation is isolated and Core Data is exercised only by tests.

**Gate:** Core Data passes the relevant permanent contract tests without weakening the tests to accommodate it.

## Milestone 5 — Implement the Animal aggregate and transaction boundary

This is the first major persistence replacement.

Implement Animal, AnimalTag, parent relationships, status records, movements, health records, pregnancy checks, archive state, and editor aggregate revision handling.

`AnimalAggregateTransactionWriting` becomes a real Core Data transaction rather than several repository saves.

Create and update must execute within one transaction context. Tag reconciliation, history generation, pasture/parent relationships, stale-revision checking, and aggregate revision rotation happen before the final save.

Any failure rolls back the entire logical edit.

This milestone also replaces the current duplicated tag-number/color state with the production `AnimalTag` model.

**Gate:** all reusable animal/identity/history/transaction contracts pass against Core Data, including deliberately injected failures and stale-edit conflicts.

## Milestone 6 — Implement Pasture deletion and movement transactions

Replace the current sequential pasture-deletion behavior with the transaction boundary already defined in Domain.

The transaction will revalidate the expected pasture/resident state, move affected animals, create movement history, preserve Field Check snapshots/history, and delete the pasture records in one atomic operation.

Animal movement itself should also have a clean reusable Core Data implementation because Working and pasture workflows both depend on it.

**Gate:** no test can observe the half-completed state that is possible with the current multi-save SwiftData sequence.

## Milestone 7 — Implement Field Check persistence

Port Field Check sessions, tracked-animal checks, findings, quick counts, snapshots, completion/archive behavior, and their repository operations.

Historical semantics matter more here than live relationships. The Core Data model must preserve the snapshots the UI expects even when an animal or pasture later changes or disappears.

Multi-record commands remain transactionally atomic.

**Gate:** the entire Field Check contract suite passes against Core Data, including pasture deletion/history cases.

## Milestone 8 — Implement Working persistence

Port working sessions, queue items, treatment records, pregnancy checks linked to working sessions, generated health records, and treatment templates.

This milestone preserves the useful behavior already present in the SwiftData implementation while dropping deprecated storage concepts such as queue indices/order and old persistence terminology.

The important existing atomic operations remain atomic: collect animals, complete queue item, save queue-item edits, complete session, and delete session.

**Gate:** all Working contract tests pass against Core Data, including animal-location restoration, treatment replacement, destination assignment validation, and rollback cases.

## Milestone 9 — Port read models and performance-sensitive queries

Once the authoritative write-side repositories exist, implement the Dashboard, Home, animal lists, search/filtering, metrics, and other read-heavy paths directly against Core Data.

This is where we avoid recreating the current “fetch everything and filter on the main actor” behavior.

Queries should perform filtering, sorting, counts, grouping, and projections in Core Data where practical.

Persistence work should not automatically remain `@MainActor` merely because SwiftData previously required it.

**Gate:** feature snapshots match the test-defined behavior while the new implementation has sane query boundaries for real herd sizes.

## Milestone 10 — Direct Core Data + CloudKit synchronization and sharing

Only after the local graph is stable do we implement final synchronization.

Same-user sync comes from the same `NSPersistentCloudKitContainer`.

Cross-user Herd sharing uses Core Data/CloudKit sharing APIs directly against that graph. There is no `Shared*Record` mirror graph, SwiftData exporter, SwiftData importer, reconciliation journal, or second synchronization lifecycle.

Remote Core Data/CloudKit changes feed the existing persistence-neutral application mutation/invalidation mechanism.

Tests here focus on deterministic boundaries we control: store routing, ownership/root assumptions, share-preparation logic, share acceptance routing, remote-change invalidation, and application UUID preservation.

**Gate:** there is exactly one production data graph and one synchronization system.

## Milestone 11 — Cut AppDependencies over to Core Data

This is the decisive runtime switch.

`CoreDataPersistenceAssembly` becomes the application persistence assembly. All feature dependency containers receive Core Data-backed implementations of the existing Domain contracts.

SwiftUI does not receive `NSManagedObjectContext`, `NSPersistentContainer`, or managed objects.

The app either runs entirely on Core Data or fails visibly during development. There is no fallback to SwiftData and no screen-by-screen hybrid runtime.

**Gate:** all production dependency paths resolve to Core Data, the app has no runtime reads or writes to SwiftData, and the behavioral contract suite passes against the implementation actually used by the app.

## Milestone 12 — Gut SwiftData and the old sharing bridge

Once the cutover is proven, delete rather than adapt.

This removes the SwiftData models, SwiftData repositories, SwiftData read actors, SwiftData persistence assembly, `ModelContainer`/`ModelContext` startup, SwiftData schema/migration infrastructure, SwiftData remote-store observer, SwiftData-specific repair machinery, SwiftData/Core Data bridge, `Shared*Record` mirrors, bridge snapshots/import/export, bridge journals, reconciliation code, deferred bridge repositories, bridge diagnostics that no longer apply, and the temporary SwiftData contract-test harness.

Domain tests and reusable persistence contracts remain.

**Gate:** a production-code search finds no SwiftData runtime dependency and no old mirror/bridge architecture.

## Milestone 13 — Harden the final architecture

Add architecture checks that prevent regression.

Production Domain and Presentation must not import Core Data. Only the Data/App persistence implementation can know managed-object/context/store types.

Architecture verification should explicitly reject SwiftData imports and old bridge classes.

Add final Core Data integration tests for delete rules, transaction rollback, store routing, UUID integrity, persistent-history handling, and mapping.

Update `ARCHITECTURE.md` to describe the implemented system rather than the transition. Delete `CORE_DATA_CUTOVER.md` because the transition is complete.

**Final completion gate:** Core Data is the sole persistence system; the permanent behavior suite passes against it; CloudKit private/shared storage uses the same graph; SwiftData and the bridge are gone; UUIDs are authoritative application identity; the important multi-record workflows are genuinely transactional; and the architecture checks make it difficult to accidentally reintroduce persistence coupling.

## How I will use this plan

I will treat each milestone as a merge gate. I will not start the next persistence layer simply because code exists; the contracts for the current milestone need to be satisfied first. PRs will stay small enough to review, so some milestones—especially Animal, Working, and CloudKit sharing—may require multiple PRs, but I will not create transitional architectures just to make the PR sequence easier.

The key ordering is now:

```text
Permanent behavioral contracts
        ↓
Core Data schema
        ↓
Core Data infrastructure
        ↓
Repositories + real transactions
        ↓
Read models
        ↓
CloudKit sync/sharing
        ↓
One-time app cutover
        ↓
Delete SwiftData + bridge
        ↓
Architecture enforcement
```

The **next implementation PR should therefore be the persistence contract-test foundation**, not the Core Data model itself. That gives us a measurable definition of “the refactor did not break yaHerd” before we start changing storage.
