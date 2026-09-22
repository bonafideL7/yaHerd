# Core Data Cutover Playbook

> Temporary implementation instructions for replacing the current SwiftData persistence stack with the production local Core Data architecture. Delete this document when the cutover is complete and `ARCHITECTURE.md` describes the implemented system rather than the target.

`ARCHITECTURE.md` remains the authoritative clean-architecture guide throughout this work. This playbook changes persistence technology; it does not suspend or replace feature ownership, dependency direction, use-case rules, dependency-injection boundaries, mapping rules, navigation ownership, presentation responsibilities, or other persistence-independent architecture guidance.

## Non-negotiable direction

This is a **replacement, not a migration**.

The app is not shipping on the current SwiftData persistence implementation, so development SwiftData stores do not need to survive the cutover. Optimize every change for the finished product.

Do not create or preserve any of the following solely to ease transition:

- SwiftData-to-Core Data data migration;
- dual writes;
- temporary repository adapters that write both systems;
- SwiftData/Core Data snapshot import/export;
- compatibility mirrors;
- migration journals for development data;
- fallback to SwiftData after Core Data is introduced;
- tests whose only purpose is proving the temporary SwiftData implementation behaves the same as Core Data.

If replacing a component cleanly requires deleting a large amount of obsolete persistence code, delete it.

## Finished product

The target persistence stack is:

```text
Presentation
   ↓
Domain repository / transaction contracts
   ↓
Core Data repositories
   ↓
NSPersistentContainer
   ↓
Local Core Data persistent store
```

There is one application data graph. Core Data owns local persistence. There is no iCloud synchronization, CloudKit transport, shared store, cross-user herd sharing, mirror graph, or synchronization bridge in the target architecture.

## Identity rules to preserve throughout the cutover

`ApplicationEntityID` / `UUID` is the canonical application identity.

When introducing every Core Data entity:

1. Add a dedicated UUID application-ID attribute.
2. Generate the UUID before or when the application creates the entity and before its first save.
3. Never change an established entity UUID during ordinary updates.
4. Resolve repository requests by application UUID within the repository's identity scope, not by `NSManagedObjectID`. Herd-owned repositories must constrain lookup to the owning/current Herd rather than searching the store by UUID alone.
5. Map the same UUID back into Domain snapshots; missing application identity is invalid persisted state, not permission to invent a replacement UUID.
6. Keep `NSManagedObjectID`, object URI strings, and persistent-store identifiers inside Data/App implementation code.
7. Treat duplicate UUIDs inside the same entity type and identity scope as an integrity failure; do not silently mint a new identity for an established record. `Herd` identity is store-global. Herd-owned identity is scoped by Herd unless a permanent feature contract explicitly defines broader semantics.
8. Do not assume a global Core Data unique constraint on a herd-owned `id` is valid. Physical constraints must compose with permanent feature behavior, including stable built-in Tag Color IDs that can exist independently in different Herd scopes.
9. Use UUIDs for relationship references that cross architectural or serialization boundaries. Use native Core Data relationships inside the managed graph. A herd-owned UUID reference is interpreted under the enclosing/selected Herd unless a true cross-Herd boundary explicitly carries Herd identity as well.
10. Do not stringify UUIDs in Domain merely for convenience. Convert to/from strings only at true serialization boundaries.

Existing Domain types that already use `UUID` are compliant even if they have not been mechanically changed to the `ApplicationEntityID` alias.

## Store design

Use one Core Data model and one local persistent store for production business data.

```text
NSPersistentContainer
└── yaHerd.sqlite
```

Herd remains a logical ownership/scope root for application data. Feature repositories should operate within the selected/current Herd scope where the Domain contract requires it, but there is no private/shared-store routing and no collaboration ownership state.

A repository must not rely on fetch order to choose a Herd. `HerdRepository.fetchCurrentHerd()` means the application-selected/current Herd according to local application state and repository scope, not "the first object returned by Core Data."

## Implementation order

The cutover is **test-first at the persistence boundary**. Tests are divided deliberately between current-behavior characterization and end-state behavior that SwiftData does not implement.

### Phase 0 — permanent behavior contracts before the physical Core Data model

Before creating `yaHerdModel.xcdatamodeld`, add persistence-neutral characterization contracts for behavior the current application already implements.

The contracts must exercise Domain repository/transaction behavior rather than SwiftData types. A thin SwiftData test harness may instantiate the current repositories so these contracts characterize intended behavior before the persistence implementation changes. The contract definitions survive the cutover; only the SwiftData runner is temporary.

Characterize current behavior such as:

- application UUID preservation and duplicate-ID integrity behavior;
- animal create/update/tag/history behavior;
- movement/history behavior;
- pasture deletion behavior observable through the current workflow;
- Field Check behavior and historical snapshots;
- Working session/queue behavior and historical snapshots;
- mutation publication on success/failure where the current boundary exposes it.

Do **not** modify production SwiftData solely to make it pass new end-state behavior. Requirements that do not exist in the current implementation become target-only contracts whose first runner is Core Data. Examples include:

- expanded historical snapshot fields introduced by the final model;
- atomic rollback for workflows known to be multi-save in SwiftData, including pasture deletion;
- Core Data-specific model integrity and delete-rule behavior.

Phase 0 is complete when the important existing persistence behavior is captured in reusable contracts and the model blueprint has been reconciled with anything those tests reveal.

### Phase 1 — physical Core Data model and structure tests

Create the final managed-object model only after Phase 0 characterization is established.

The model is designed from Domain requirements, transaction boundaries, delete/history behavior, and `CORE_DATA_MODEL_BLUEPRINT.md`. Do **not** clone the SwiftData schema because it is easier.

At this phase establish:

- model location and Manual/None managed-object strategy;
- application UUID on every durable entity;
- explicit relationships, inverses, delete rules, defaults, optionality, indexes, and uniqueness decisions based on local Core Data requirements;
- one production configuration for local business data, or the default configuration if a named configuration provides no concrete benefit;
- model-structure tests for required application invariants.

Do not wire temporary SwiftData migration into the model or container startup.

### Phase 2 — production Core Data persistence foundation

Add the final Core Data container/infrastructure that will survive launch:

- `NSPersistentContainer` local store setup;
- context creation and queue-confinement policy;
- mapper location and conventions;
- deterministic Herd scoping;
- explicit store-load failure handling and recovery-mode integration;
- a Core Data contract harness.

Run the applicable permanent characterization contracts against Core Data as soon as the required repository surface exists. Add target-only Core Data contracts as their production capability is introduced.

### Phase 3 — Core Data repositories, transactions, and read models

Implement production repositories feature by feature behind existing Domain contracts. Suggested order:

1. Herd and reference data needed to establish the root graph;
2. Pasture and pasture groups, including the atomic pasture-deletion transaction;
3. Animal, tags, status/history, health, pregnancy, parent/offspring relationships and the animal aggregate transaction;
4. Field Check;
5. Working sessions, queue items, treatment records, and templates;
6. Dashboard/Home and other read-heavy projections;
7. remaining app-scoped repositories.

For each repository, map managed objects to existing Domain snapshots. Do not expose managed objects as a shortcut.

Multi-record logical writes are explicit Core Data transactions. Important boundaries include:

- animal aggregate create/update including tags and generated history;
- pasture deletion including resident movements and field-check historical preservation;
- animal movement batches;
- field-check commands that mutate more than one record;
- working-session collection;
- working queue-item work-data replacement;
- working-session completion and destination movements;
- working-session deletion/cleanup.

One logical success corresponds to one successful transaction commit. Failures must not expose partial state. Perform the complete mutation on one appropriate context, save only after validation/mutation succeeds, and roll back/reset on failure as appropriate. Application mutation publication happens only after commit.

The permanent contract suite grows alongside this work. Do not defer Core Data repository/transaction testing to the end of the cutover.

### Phase 4 — cut AppDependencies over once

When enough Core Data repositories exist to run the application coherently, change dependency assembly to construct the Core Data stack directly.

Prefer a decisive cutover over a long period where individual screens randomly use different persistence systems.

The App layer may own a persistence assembly/lifetime object, but it exposes only Domain-facing repositories/services to Presentation.

After this point, SwiftData is no longer the runtime persistence implementation. There is no fallback and no dual-write path.

### Phase 5 — delete SwiftData infrastructure

Remove obsolete production code aggressively.

Expected deletion candidates include:

- production `import SwiftData` usage;
- `ModelContainer` / `ModelContext` app bootstrap;
- SwiftData model schemas and migration plans;
- `ModelContainerFactory`;
- `SwiftData*Repository` implementations;
- SwiftData read-model actors;
- SwiftData persistence assembly;
- SwiftData-specific sample-data persistence code that cannot be reused cleanly;
- SwiftData public-ID repair/recovery machinery that has no final-product requirement;
- SwiftData-specific diagnostics and reliability documentation;
- SwiftData migration documentation and fixture stores;
- the temporary SwiftData contract runner.

Permanent persistence-neutral contracts remain and now run only against production Core Data.

Do not retain dead compatibility code because it might be useful later.

### Phase 6 — final hardening and cleanup

Complete production persistence coverage and architecture enforcement. At minimum the final Core Data suite covers:

- UUID identity preservation across reloads and missing/duplicate UUID handling;
- repository create/read/update/delete behavior;
- relationship and delete rules;
- archive/history retention rules;
- transaction rollback behavior;
- Herd scoping;
- mapper correctness;
- store-load/recovery failure behavior where deterministic testing is possible.

Strengthen architecture verification so production code cannot reintroduce SwiftData or persistence-framework leakage into Domain/Presentation. Then remove this cutover document and update `ARCHITECTURE.md` from target wording to implemented wording if needed.

## What not to port automatically

Before recreating any existing persistence-related subsystem, ask whether the finished local Core Data architecture still needs it.

Do **not** port without a new independent requirement:

- SwiftData schema migration infrastructure;
- SwiftData public-ID repair intended for historical corrupted development stores;
- Core Data mirror public-ID reconciliation;
- sharing bridges, mirror entities, conflict journals, invitation flows, or ownership markers;
- sync schedulers, remote-store observers, CloudKit diagnostics, or iCloud account checks;
- launch logic whose only purpose is deciding whether local, cloud, or bridge data is authoritative.

Potentially retain/rework only if still required by local product behavior:

- Domain validation/policies;
- feature repository contracts;
- application mutation center/invalidation concepts;
- diagnostics meaningful for the local Core Data store;
- recovery mode as a product safety feature, redesigned around Core Data.

## Pull-request discipline for this cutover

Keep PRs focused on an end-state component, a permanent behavior-contract slice, or a deletion step. A useful PR should generally do one of three things:

- establish permanent persistence-neutral behavior tests that survive the cutover;
- add a production Core Data component that will survive launch; or
- remove obsolete SwiftData infrastructure.

Avoid PRs whose main result is an intermediate adapter that will be deleted a few PRs later.

Before starting a new cutover PR, check whether the previous PR has merged and branch from current `main`. Do not stack PRs unless explicitly requested.

Do not run builds, tests, CI, or verification automatically unless explicitly requested for the current task. Static inspection and self-review are expected. If verification is explicitly requested or a reported verification failure must be addressed, inspect and run/retry the relevant verification as needed.

## Self-review questions before finishing each Core Data PR

- Is this code part of the final architecture, or only useful for transition?
- Did I preserve the clean-architecture rules in `ARCHITECTURE.md`, or accidentally move business, presentation, navigation, or feature ownership into persistence while replacing technology?
- Did any Core Data type leak into Domain or Presentation?
- Is every durable entity still addressed by application UUID?
- Did any code use `NSManagedObjectID` as externally visible identity?
- Is a multi-record mutation actually atomic?
- Are application mutation events emitted only after commit?
- Could old SwiftData code be deleted now instead of adapted?
- Am I adding new production behavior to SwiftData solely to make a temporary test runner pass?
- Is long-running persistence work still forced onto the main actor unnecessarily?
- Does this PR move toward one local persistence graph?

## Cutover completion checklist

The cutover is complete only when all of the following are true:

- the permanent characterization contracts for preserved behavior run against Core Data;
- target-only Core Data contracts cover new final-architecture behavior;
- the app boots from the Core Data persistence assembly;
- Core Data is local-only and uses no CloudKit/iCloud persistence capability;
- repositories map managed objects to Domain values;
- application UUIDs are stable across all repository surfaces;
- important multi-record writes are transactional;
- UI invalidation is persistence-neutral and driven by successful application mutations;
- production search finds no `import SwiftData`;
- production search finds no `ModelContainer`, `ModelContext`, or SwiftData `@Model`;
- no production `SwiftData*Repository` remains;
- no sync/share bridge, CloudKit, iCloud account, or shared-store runtime path remains;
- obsolete public-ID repair code is gone unless independently justified by local data integrity requirements;
- Core Data persistence tests cover the production behavior;
- `ARCHITECTURE.md` matches the actual implementation and still contains the broader clean-architecture guidance needed to maintain the project;
- this file is deleted.
