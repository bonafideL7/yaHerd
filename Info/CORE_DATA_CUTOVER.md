# Core Data Cutover Playbook

> Temporary implementation instructions for replacing the current SwiftData/bridge persistence stack with the production Core Data architecture. Delete this document when the cutover is complete and `ARCHITECTURE.md` describes the implemented system rather than the target.

`ARCHITECTURE.md` remains the authoritative clean-architecture guide throughout this work. This playbook changes persistence technology; it does not suspend or replace feature ownership, dependency direction, use-case rules, dependency-injection boundaries, mapping rules, navigation ownership, presentation responsibilities, or other persistence-independent architecture guidance.

## Non-negotiable direction

This is a **replacement, not a migration**.

The app is not shipping on the current SwiftData synchronization architecture, so development SwiftData stores and bridge state do not need to survive the cutover. Optimize every change for the finished product.

Do not create or preserve any of the following solely to ease transition:

- SwiftData-to-Core Data data migration;
- dual writes;
- temporary repository adapters that write both systems;
- SwiftData/Core Data snapshot import/export;
- compatibility mirrors;
- migration journals for development data;
- fallback to SwiftData after Core Data is introduced;
- tests whose only purpose is proving the temporary SwiftData implementation behaves the same as Core Data.

If replacing a component cleanly requires deleting a large amount of existing persistence/sharing code, delete it.

## Finished product

The target persistence stack is:

```text
Presentation
   ↓
Domain repository / transaction contracts
   ↓
Core Data repositories
   ↓
NSPersistentCloudKitContainer
   ├── local/private store
   └── shared store
          ↓
       CloudKit
```

There is one application data graph. Core Data owns local persistence and CloudKit synchronization. Cross-user collaboration uses the same Core Data graph and Core Data/CloudKit sharing APIs.

## Identity rules to preserve throughout the cutover

`ApplicationEntityID` / `UUID` is the canonical application identity.

When introducing every Core Data entity:

1. Add a dedicated UUID application-ID attribute. Identity is required by the application even when the CloudKit-compatible physical Core Data attribute is optional because no safe static UUID default exists.
2. Generate the UUID before or when the application creates the entity and before its first save.
3. Never change an established entity UUID during ordinary updates or synchronization.
4. Resolve repository requests by application UUID, not `NSManagedObjectID`.
5. Map the same UUID back into Domain snapshots; missing application identity is invalid/incomplete persisted state, not permission to invent a replacement UUID.
6. Keep `NSManagedObjectID`, object URI strings, `CKRecord.ID`, record names, zones, and store identifiers inside Data/App implementation code.
7. Treat duplicate UUIDs as an integrity failure; do not silently mint a new identity for an established record.
8. Use UUIDs for relationship references that cross architectural or serialization boundaries. Use native Core Data relationships inside the managed graph.
9. Do not stringify UUIDs in Domain merely for convenience. Convert to/from strings only at true serialization boundaries.

Existing Domain types that already use `UUID` are compliant even if they have not been mechanically changed to the `ApplicationEntityID` alias.

## Store design

Use one Core Data model for all operating modes.

### Local-only

Use a normal local persistent store without CloudKit options. Keep the same repositories and Domain contracts.

### iCloud

Use `NSPersistentCloudKitContainer` with the final private/shared topology required by Core Data sharing:

- private store for records owned by the current user;
- shared store for records accepted from other owners;
- remote-change notifications and persistent history where useful for invalidation/merge processing;
- Core Data CloudKit sharing APIs for creating, accepting, stopping, and managing shares.

Do not add a second Core Data model or mirror just for sharing.

A user may have multiple accessible Herd roots across the attached private/shared stores, but ordinary feature repositories operate against one explicitly selected Herd workspace. Do not combine all attached stores into one implicit herd data set.

In iCloud mode, an empty local private-store fetch during startup is **not** proof that the user has no existing Herd. A reinstall/new device may be waiting for CloudKit import. New owned-Herd creation must occur through an explicit onboarding/workspace-creation boundary after cloud store readiness/initial import resolution, with accessible Herds rechecked immediately before insert. Never create a default Herd merely because an early fetch returned zero rows.

## Implementation order

The cutover is **test-first at the persistence boundary**. Tests are divided deliberately between current-behavior characterization and end-state behavior that SwiftData does not implement.

### Phase 0 — permanent behavior contracts before the physical Core Data model

Before creating `yaHerdModel.xcdatamodeld`, add persistence-neutral characterization contracts for behavior the current application already implements.

The contracts must exercise Domain repository/transaction behavior rather than SwiftData types. A thin SwiftData test harness may instantiate the current repositories so these contracts characterize intended behavior before the persistence implementation changes. The contract definitions survive the cutover; only the SwiftData runner is temporary.

Characterize current behavior such as:

- application UUID preservation and current duplicate-ID integrity behavior;
- animal create/update/tag/history behavior;
- movement/history behavior;
- pasture deletion behavior observable through the current workflow;
- Field Check behavior and existing historical snapshots;
- Working session/queue behavior and existing historical snapshots;
- mutation publication on success/failure where the current boundary exposes it.

Do **not** modify production SwiftData solely to make it pass new end-state behavior. Requirements that do not exist in the current implementation become target-only contracts whose first runner is Core Data. Examples include:

- selected-Herd isolation across simultaneous private/shared Herd roots;
- deterministic workspace selection/switch/revocation behavior;
- private/shared Core Data store routing and cross-store relationship rejection;
- expanded historical snapshot fields introduced by the final model;
- atomic rollback for workflows known to be multi-save in SwiftData, including pasture deletion.

Phase 0 is complete when the important existing persistence behavior is captured in reusable contracts and the model blueprint has been reconciled with anything those tests reveal.

### Phase 1 — physical Core Data model and structure tests

Create the final managed-object model only after Phase 0 characterization is established.

The model is designed from Domain requirements, transaction boundaries, CloudKit requirements, delete/history behavior, and `CORE_DATA_MODEL_BLUEPRINT.md`. Do **not** clone the SwiftData schema because it is easier.

At this phase establish:

- model location and Manual/None managed-object strategy;
- application UUID on every durable entity, following the documented application-required/physical-optionality distinction;
- explicit relationships, inverses, delete rules, defaults, optionality, and indexes;
- one `CloudData` configuration suitable for local/private/shared stores;
- model-structure tests for CloudKit compatibility and required application invariants.

Do not wire temporary SwiftData migration into the model or container startup.

### Phase 2 — production Core Data persistence foundation

Add the final Core Data container/infrastructure that will survive launch:

- local store mode;
- `NSPersistentCloudKitContainer` private/shared store descriptions;
- persistent-history / remote-change configuration;
- context creation and queue-confinement policy;
- mapper location and conventions;
- deterministic selected-Herd/store routing;
- explicit onboarding/workspace creation that cannot mistake a transiently empty cloud store for a new account;
- a Core Data contract harness.

Run the applicable permanent characterization contracts against Core Data as soon as the required repository surface exists. Add target-only Core Data contracts as their production capability is introduced.

### Phase 3 — Core Data repositories, transactions, and read models

Implement production repositories feature by feature behind existing Domain contracts. Suggested order:

1. selected-Herd scope, Herd and reference data needed to establish ownership/root graph;
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

One logical success corresponds to one successful transaction commit. Failures must not expose partial state. Perform the complete mutation on one appropriate context, save only after validation/mutation succeeds, and roll back/reset on failure as appropriate. Application mutation publication and sync scheduling happen only after commit.

The permanent contract suite grows alongside this work. Do not defer Core Data repository/transaction testing to the end of the cutover.

### Phase 4 — direct CloudKit sync and sharing

Wire same-user sync and cross-user sharing directly through `NSPersistentCloudKitContainer`.

Keep or rebuild only provider-neutral collaboration concepts that still make sense. The final sharing path resolves application UUIDs to Core Data objects internally and uses Core Data sharing APIs from there.

Do not port the old bridge architecture.

Delete rather than rewrite bridge concepts whose only reason to exist was SwiftData's lack of first-class sharing support, including as applicable:

- `Shared*Record` mirror entities;
- SwiftData-to-Core Data exporters/importers;
- bridge snapshots;
- import/export reconciliation;
- bridge journals;
- bridge ownership repair;
- duplicate-public-ID repair written specifically to reconcile two persistence graphs;
- deferred bridge repositories;
- dual-stack sharing coordinators.

Do not assume every file under the current `Data/Sharing/CoreData` directory belongs in the final Core Data design. Much of it is bridge code, not the target persistence implementation.

### Phase 5 — cut AppDependencies over once

When enough Core Data repositories exist to run the application coherently, change dependency assembly to construct the Core Data stack directly.

Prefer a decisive cutover over a long period where individual screens randomly use different persistence systems.

The App layer may own a persistence assembly/lifetime object, but it exposes only Domain-facing repositories/services to Presentation.

After this point, SwiftData is no longer the runtime persistence implementation. There is no fallback and no dual-write path.

### Phase 6 — delete SwiftData and bridge infrastructure

Remove obsolete production code aggressively.

Expected deletion candidates include:

- production `import SwiftData` usage;
- `ModelContainer` / `ModelContext` app bootstrap;
- SwiftData model schemas and migration plans;
- `ModelContainerFactory`;
- `SwiftData*Repository` implementations;
- SwiftData read-model actors;
- SwiftData persistence assembly;
- SwiftData remote-store observers;
- SwiftData-specific sample-data persistence code that cannot be reused cleanly;
- SwiftData/Core Data bridge models and synchronization code;
- public-ID bridge repair/recovery machinery that has no final-product requirement;
- bridge-specific diagnostics and reliability documentation;
- SwiftData migration documentation and fixture stores;
- the temporary SwiftData contract runner.

Permanent persistence-neutral contracts remain and now run only against production Core Data.

Do not retain dead compatibility code because it might be useful later.

### Phase 7 — final hardening and cleanup

Complete the production persistence coverage and architecture enforcement. At minimum the final Core Data suite covers:

- UUID identity preservation across reloads and missing/duplicate UUID handling;
- repository create/read/update/delete behavior;
- relationship and delete rules;
- archive/history retention rules;
- transaction rollback behavior;
- selected-Herd isolation;
- private/shared store routing;
- remote-change invalidation;
- sharing preparation/acceptance boundaries where deterministic testing is possible;
- mapper correctness.

Strengthen architecture verification so production code cannot reintroduce SwiftData or persistence-framework leakage into Domain/Presentation. Then remove this cutover document and update `ARCHITECTURE.md` from target wording to implemented wording if needed.

## What not to port automatically

Before recreating any existing persistence-related subsystem, ask whether the finished Core Data architecture still needs it.

Likely **do not port** without a new requirement:

- SwiftData schema migration infrastructure;
- SwiftData public-ID repair intended for historical corrupted development stores;
- Core Data mirror public-ID reconciliation;
- bridge conflict comparison/journaling;
- bridge import/export recovery;
- duplicate graph ownership markers;
- launch logic whose only purpose is deciding whether SwiftData or bridge data is authoritative.

Potentially retain/rework only if still required by product behavior:

- Domain validation/policies;
- feature repository contracts;
- application mutation center/invalidation concepts;
- collaboration permissions and neutral share invitation/presentation concepts;
- diagnostics that are meaningful for the new Core Data stores;
- recovery mode as a product safety feature, redesigned around Core Data.

## Pull-request discipline for this cutover

Keep PRs focused on an end-state component, a permanent behavior-contract slice, or a deletion step. A useful PR should generally do one of three things:

- establish permanent persistence-neutral behavior tests that survive the cutover;
- add a production Core Data component that will survive launch; or
- remove obsolete SwiftData/bridge infrastructure.

Avoid PRs whose main result is an intermediate adapter that will be deleted a few PRs later.

Before starting a new cutover PR, check whether the previous PR has merged and branch from current `main`. Do not stack PRs unless explicitly requested.

Do not run builds, tests, CI, or verification automatically unless explicitly requested for the current task. Static inspection and self-review are expected. If verification is explicitly requested or a reported verification failure must be addressed, inspect and run/retry the relevant verification as needed.

## Self-review questions before finishing each Core Data PR

- Is this code part of the final architecture, or only useful for transition?
- Did I preserve the clean-architecture rules in `ARCHITECTURE.md`, or accidentally move business, presentation, navigation, or feature ownership into persistence while replacing technology?
- Did any Core Data/CloudKit type leak into Domain or Presentation?
- Is every durable entity still addressed by application UUID?
- Did any code use `NSManagedObjectID` as externally visible identity?
- Is application-required identity being confused with physical Core Data optionality/default requirements?
- Could a transiently empty CloudKit-backed store accidentally create a duplicate Herd root?
- Is a multi-record mutation actually atomic?
- Are application mutation events emitted only after commit?
- Did I recreate a bridge/mirror problem that `NSPersistentCloudKitContainer` already solves?
- Could old SwiftData code be deleted now instead of adapted?
- Am I adding new production behavior to SwiftData solely to make a temporary test runner pass?
- Is long-running persistence work still forced onto the main actor unnecessarily?
- Are private/shared stores selected intentionally?
- Does this PR move toward one persistence graph?

## Cutover completion checklist

The cutover is complete only when all of the following are true:

- the permanent characterization contracts for preserved behavior run against Core Data;
- target-only Core Data contracts cover new final-architecture behavior;
- the app boots from the Core Data persistence assembly;
- local-only mode uses Core Data;
- iCloud mode uses `NSPersistentCloudKitContainer`;
- same-user synchronization uses Core Data/CloudKit;
- cross-user sharing uses the same Core Data graph and shared store;
- repository instances are scoped to one selected Herd and do not combine private/shared Herd graphs;
- iCloud startup cannot create a new Herd merely because the private store is temporarily empty;
- repositories map managed objects to Domain values;
- application UUIDs are stable across all repository surfaces;
- important multi-record writes are transactional;
- UI invalidation is persistence-neutral;
- production search finds no `import SwiftData`;
- production search finds no `ModelContainer`, `ModelContext`, or `@Model` from SwiftData;
- no production `SwiftData*Repository` remains;
- no SwiftData/Core Data mirror/import/export/reconciliation path remains;
- obsolete public-ID bridge repair code is gone unless independently justified;
- Core Data persistence tests cover the production behavior;
- `ARCHITECTURE.md` matches the actual implementation and still contains the broader clean-architecture guidance needed to maintain the project;
- this file is deleted.
