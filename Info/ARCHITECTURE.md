# yaHerd Architecture

> This document describes the **target production architecture**. During the Core Data cutover, existing SwiftData and bridge code may temporarily violate these rules. `CORE_DATA_CUTOVER.md` governs that temporary work. The target architecture is authoritative when the two disagree.

## End-state architecture

```text
SwiftUI / Presentation
        ↓
Domain models, policies, use cases, repository + transaction contracts
        ↓
Data / Core Data repositories
        ↓
NSPersistentCloudKitContainer
        ↓
Local Core Data stores + CloudKit private/shared databases
```

Core Data is the sole production persistence implementation. `NSPersistentCloudKitContainer` is the sole production CloudKit synchronization mechanism. SwiftData, a SwiftData/Core Data mirror, dual-write persistence, and custom snapshot synchronization are not part of the final architecture.

## Top-level layers

- `App/`
  - app bootstrap, dependency assembly, navigation, app-scoped coordination, mutation/invalidation routing, preferences, diagnostics, and recovery entry points
- `Domain/`
  - business entities, stable application identity, repository contracts, transaction contracts, use cases, policies, validation, and services
- `Data/`
  - Core Data model, persistent-container setup, Core Data repository implementations, mappers, CloudKit sharing integration, and persistence diagnostics
- `Presentation/`
  - SwiftUI views, view models, UI support types, and presentation state

Dependency direction is strict:

- Presentation depends on Domain.
- Data depends on Domain.
- Domain does not import SwiftUI, Core Data, CloudKit, SwiftData, or App wiring.
- App composes Data implementations behind Domain-facing contracts.
- Presentation never receives a managed object or managed-object context.

## Application identity

`ApplicationEntityID` is the semantic name for the application's stable UUID identity. It is intentionally a typealias of `UUID`, not a persistence wrapper.

For every durable application entity:

- identity is a UUID owned by yaHerd, not by the persistence framework;
- the UUID is generated once before or as the entity is created and is immutable afterward;
- repository and transaction APIs address entities with UUIDs;
- Domain snapshots expose the same UUID across reloads, sync, sharing, navigation, and relationships;
- Core Data stores that UUID as a required UUID attribute on the managed object;
- `NSManagedObjectID`, object URI representations, `CKRecord.ID`, record names, store identifiers, and CloudKit zone identifiers are Data-layer implementation details and never become Domain identity;
- stringifying a UUID is allowed only at serialization boundaries such as URLs, logs, diagnostics, or provider APIs; Domain models should retain the UUID type;
- a duplicate application UUID is a persistence integrity error. Production code must reject or deterministically resolve it before exposing ambiguous Domain state; it must not silently mint a replacement for an already-established entity identity.

Derived UI/chart identifiers may use strings, dates, enums, or composite keys when they do not represent a durable entity. They must not be passed to repository APIs as entity identity.

## Persistence and store topology

The production persistence root is `NSPersistentCloudKitContainer` using one Core Data model.

### Local-only mode

Local-only mode uses the same Core Data model and repositories with a normal local persistent store and no CloudKit container options. Business behavior must not fork merely because CloudKit is disabled.

### iCloud mode

iCloud mode uses Core Data stores configured for CloudKit:

- a private store for the user's owned data;
- a shared store for data accepted from other owners;
- persistent-history tracking and remote-change observation where needed for application invalidation;
- Core Data/CloudKit sharing APIs for `CKShare` creation, acceptance, participant management, and shared-store routing.

The Data layer may use `NSManagedObjectID` when required by Core Data sharing APIs, but it must resolve application UUIDs to managed objects internally and return only Domain values upward.

There is no second persistence graph to mirror. There is no SwiftData-to-Core Data exporter/importer, no bridge reconciliation pass, and no dual-write path.

## Core Data model rules

The model is designed for CloudKit from the beginning rather than converted from the current SwiftData schema.

- Every durable entity has a required application UUID attribute.
- Relationships have explicit inverses and delete behavior is chosen intentionally.
- CloudKit-compatible optionality/default requirements are handled in the model rather than patched in Presentation.
- Domain enums are stored through stable raw values or explicit mapping owned by Data.
- Historical records that must survive parent status changes or archival are modeled accordingly.
- Repository mappers are the only normal path from managed objects to Domain snapshots.
- Core Data generated/accessor types do not escape Data.

Do not copy the current SwiftData schema merely to reduce cutover work. Model the finished product.

## Repository boundary

Domain repository contracts describe application behavior, not Core Data operations. Use the narrowest capability needed by a use case or feature.

A concrete Core Data repository may satisfy several capability protocols for dependency assembly, but callers should not depend on a broad repository when a smaller contract exists.

Repositories are responsible for:

- fetching and mapping persistent data;
- applying persistence changes required by a Domain command;
- enforcing persistence integrity, including stable UUID lookup;
- executing storage transactions;
- saving or rolling back the appropriate context;
- translating persistence errors into meaningful Domain/application errors where appropriate.

Repositories do not own reusable business decisions that belong in Domain services or policies.

## Transaction boundary

Multi-record business operations must have one explicit persistence transaction boundary. A successful command means the entire logical operation committed. A thrown error means no partial logical result is left committed.

Important examples include:

- animal aggregate create/update, including tags and generated history;
- pasture deletion, resident-animal movement/history, and field-check historical preservation;
- working-session collection, queue-item work-data replacement, session completion, and session deletion;
- field-check commands that update the session plus roster/finding/animal state;
- multi-animal pasture movement.

Core Data implementations should perform these writes on one appropriate context and save only after the complete mutation succeeds. On failure, roll back/reset the transaction context as appropriate. Mutation publication and sync scheduling happen **after** a successful commit, never before.

## Synchronization and UI invalidation

Persistence synchronization and UI invalidation are separate concerns.

- Core Data/CloudKit owns transport and merge behavior.
- Data observes relevant persistent-store/remote-change events.
- Data/App translates those events into persistence-neutral application mutation/invalidation events.
- Presentation reloads through Domain repository/read-model contracts.
- Views and view models do not subscribe to Core Data notifications directly.

A local successful transaction should publish one logical application mutation after commit. Remote imports should publish invalidation without pretending they are local writes.

## CloudKit sharing boundary

Cross-user herd sharing is implemented directly on the production Core Data graph through `NSPersistentCloudKitContainer` and `CKShare`.

CloudKit types remain inside Data/App integration boundaries. Domain collaboration types may contain application UUIDs, permissions/capabilities, URLs, and opaque provider tokens when necessary, but not `CKShare`, `CKRecord`, `CKShare.Metadata`, `NSManagedObject`, `NSManagedObjectID`, or `NSManagedObjectContext`.

The final sharing path must not contain a second Core Data mirror of application data. Existing bridge-specific models, import/export snapshots, reconciliation journals, and public-ID bridge repair logic are cutover artifacts to be deleted unless a requirement is independently demonstrated in the final Core Data design.

## Concurrency

SwiftUI observable state and navigation remain main-actor isolated. Core Data work follows Core Data queue confinement rather than forcing all persistence onto the main actor.

- UI state mutations happen on `@MainActor`.
- Background/private contexts perform work with their own queue/executor using Core Data's concurrency APIs.
- Managed objects never cross their context boundary into Domain or Presentation.
- Sendable Domain snapshots cross concurrency boundaries instead.
- Long reads, imports, and maintenance work should not block the main actor.
- Do not use `@unchecked Sendable` to make managed objects or contexts cross isolation boundaries.

Repository protocol isolation may evolve as the Core Data implementation is introduced; it should reflect actual caller and context safety rather than historical SwiftData `mainContext` constraints.

## Feature boundaries

Feature dependency containers remain the Presentation injection boundary:

- `HomeFeatureDependencies`
- `AnimalFeatureDependencies`
- `PastureFeatureDependencies`
- `FieldCheckFeatureDependencies`
- `WorkingSessionFeatureDependencies`
- collaboration/app-scoped dependencies where appropriate

Cross-feature operations belong in focused Domain use cases or transaction contracts. Reference data remains owned by the feature that owns the data. Do not add persistence-framework dependencies to feature containers.

The current feature ownership remains:

- Animal: animal identity, tags, status, archive/restore, health, pregnancy, parent/offspring links, animal movement.
- Pasture: pasture/group data, stocking/rotation policy, pasture reference data.
- Field Check: check sessions, roster/check state, findings, historical snapshots.
- Working: working sessions, queue items, treatment plans/records, destinations, working-session lifecycle.
- Dashboard/Home: derived read models only; they do not own persistence identity for source entities.
- Herd/Collaboration: herd-level identity and sharing policy.

## Recovery and diagnostics

Recovery behavior should be designed around the production Core Data stores, not ported mechanically from SwiftData.

A store-open failure must produce a controlled state that cannot accidentally write to an unintended replacement store. Diagnostics may expose store URLs, modes, history/sync state, and exportable diagnostic information, but persistence objects remain internal.

Only carry forward existing recovery/public-ID tooling when the final Core Data architecture has the same requirement. Delete tooling whose sole purpose was repairing or coordinating the old dual-stack design.

## Testing expectations

Production persistence tests should target the Core Data implementation directly.

Required coverage includes:

- repository behavior for important reads and writes;
- application UUID preservation across create/update/reload;
- duplicate UUID integrity behavior;
- transaction rollback/all-or-nothing behavior;
- relationship/delete-rule behavior;
- private/shared store routing;
- CloudKit sharing preparation/acceptance boundaries where they can be tested deterministically;
- remote-change invalidation;
- mapping between Core Data records and Domain snapshots.

Do not add new tests whose only purpose is preserving the temporary SwiftData implementation. Shared Domain tests should exist only where they remain valuable after SwiftData deletion.

## Rules for future growth

1. Design for the finished Core Data architecture, not compatibility with the old SwiftData store.
2. Keep application UUIDs as the only Domain identity for durable entities.
3. Keep Core Data and CloudKit types out of Domain and Presentation.
4. Keep views declarative and state-light.
5. Put reusable business rules in Domain services/policies.
6. Use narrow repository capability protocols.
7. Use explicit transaction boundaries for multi-record logical writes.
8. Publish application mutations only after a successful commit.
9. Use Core Data relationships internally; use application UUIDs at architectural boundaries.
10. Do not introduce a second persistence graph, dual writes, mirror records, or migration-only adapters.
11. Prefer deleting obsolete SwiftData/bridge code over porting it.
12. Add tests for the production Core Data implementation as it is built.

## Cutover status

SwiftData and the existing SwiftData/Core Data sharing bridge are temporary implementation code. They are not architectural precedent. Follow `CORE_DATA_CUTOVER.md` until the replacement is complete; after cutover, remove that document and any remaining transition-only code.
