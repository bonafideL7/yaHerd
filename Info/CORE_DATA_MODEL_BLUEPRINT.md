# Core Data Model Blueprint

> Phase 1 implementation blueprint for the production local Core Data model. This document turns the persistence rules in `ARCHITECTURE.md`, `TRANSACTION_BOUNDARIES.md`, and `CORE_DATA_CUTOVER.md` into a concrete schema design before any Core Data repositories are written.

This blueprint is intentionally **not** a SwiftData migration map. Development SwiftData stores, old collaboration records, repair metadata, and migration compatibility do not constrain this model.

When the real `.xcdatamodeld` and managed-object implementation are established, keep this document synchronized with the model until the Core Data cutover is complete. If the implementation intentionally diverges, update this document in the same PR rather than allowing two competing persistence designs.

## Goals

The first production Core Data model must:

- support the existing Domain behavior without exposing Core Data upward;
- use `ApplicationEntityID` / `UUID` as application identity;
- use one local Core Data graph and persistent store;
- keep `Herd` as the logical ownership/scope root;
- preserve historical records when their referenced pasture, animal, or display data can disappear;
- support the atomic transaction boundaries already defined in Domain;
- support optimistic animal-editor conflict detection;
- avoid schema choices that exist only because SwiftData or CloudKit required them;
- use native Core Data integrity features where they improve the local model without weakening Domain invariants.

## Non-goals

Do not use this work to add:

- SwiftData-to-Core Data migration;
- dual-write support;
- bridge snapshots or mirror entities;
- public-ID bridge repair infrastructure;
- compatibility fields for deprecated SwiftData behavior;
- collaboration revision records;
- CloudKit/iCloud synchronization or sharing metadata;
- managed-object IDs as application identity;
- app preferences/settings to Core Data.

## Milestone 1 reconciliation against Milestone 0

Milestone 0 is now the behavioral source of truth for this blueprint. The permanent repository, read-model, identity, mutation-boundary, transaction-precondition, and rollback contracts were reconciled against the physical design before creating the Core Data model.

### Reconciliation result

The **18-entity inventory remains sufficient**. Milestone 0 did not expose a product behavior that requires another managed entity. The reconciliation instead tightens relationship semantics, historical snapshot ownership, reference-data lifecycle, and transaction/concurrency rules.

Key changes confirmed by the contracts:

- current-Herd selection remains local application state outside the Core Data business graph; repository reads/writes never bootstrap a Herd as a side effect of nil or stale selection;
- Tag Color removal is not equivalent to physical deletion when historical references still need the definition; hidden referenced definitions remain resolvable by application UUID;
- normalized Tag Color identity collisions are graph-wide reconciliation transactions because color UUIDs exist in both live relationships and historical snapshot attributes;
- Animal `editorRevision` rotates for **every** successful public mutation that changes editor-owned scalar, relationship, or tag state, regardless of which feature initiated the write;
- health/pregnancy child insertion alone does **not** rotate `editorRevision`, because those children are outside the Animal editor aggregate;
- deleting a parent Animal nullifies surviving offspring parent relationships and rotates the surviving offspring aggregate revisions;
- deleting a Pregnancy Check's referenced sire nullifies only the live sire relationship; it does not delete or rewrite the pregnancy row's historical payload;
- Pasture deletion moves active residents transactionally, but sold/dead/archived Animals that still reference the deleted Pasture are also affected by relationship nullification and revision rotation;
- deleting the final Pasture in a PastureGroup does not implicitly delete the now-empty group;
- Field Check findings source animal/pasture display identity from the session's captured roster/session snapshots, including on later finding edits or reassignment after live records change;
- Working and Field Check historical rows remain readable after related live Animal/Pasture deletion according to their snapshot contracts;
- failed Core Data transaction scopes must be rolled back/reset before reuse or explicitly discarded; no staged state may leak through a later save;
- successful application mutation publication occurs only after durable commit, and throwing writes publish no success event.

### Domain contract -> Core Data entity mapping

This mapping is the Milestone 1 handoff to physical model implementation. It identifies the managed entities each permanent contract depends on; it does not move contract ownership into persistence.

| Permanent contract / behavior slice | Core Data entities and physical concerns |
| --- | --- |
| `IdentityContract` | All 18 entities; required application UUID, Herd ownership scope, scoped duplicate rejection, no persistence-native identity leakage |
| `HerdRepositoryContract` | `Herd` plus representative owned graph; selected-Herd lookup by UUID, rename metadata preservation, rollback, no read-side bootstrap |
| `TagColorRepositoryContract` | `TagColorDefinition`, `AnimalTag`, Field Check color snapshot attributes, Working queue color snapshot attributes; hidden-definition lookup and collision remapping |
| `AnimalRepositoryContract` / `AnimalRepositoryReadModelContract` | `Animal`, `AnimalTag`, `MovementRecord`, `StatusRecord`, `HealthRecord`, `PregnancyCheck`, status/pasture/parent relationships and list/detail/timeline projections |
| `AnimalAggregateTransactionContract` | `Animal`, `AnimalTag`, `MovementRecord`, `StatusRecord`; one aggregate write transaction with revision validation/rotation |
| `AnimalAggregateCrossFeatureRevisionContract` | `Animal.editorRevision` plus every relationship/tag mutation path that can alter editor-owned state, including parent/pasture nullification and Tag Color remap |
| `PastureRepositoryContract` / edge-case contracts | `Pasture`, `PastureGroup`, Animal current-pasture relationships, Working live pasture links, Field Check live pasture links |
| `PastureDeletionTransactionContract` / workflow contract | `Pasture`, `Animal`, `MovementRecord`, `FieldCheckSession`, PastureGroup membership, Working live pasture links; stale-state validation and atomic delete plan |
| `FieldCheckRepositoryContract` family | `FieldCheckSession`, `FieldCheckAnimalCheck`, `FieldCheckFinding`; roster/session snapshots, finding reassignment/orphan edits, missing/attention synchronization, completed-session locking |
| `HealthRepositoryContract` | `HealthRecord`, `PregnancyCheck`, Animal ownership, optional Working-session linkage, Pregnancy sire nullification, archive preservation, hard-delete cascade |
| `WorkingRepositoryContract` family | `WorkingSession`, `WorkingQueueItem`, `WorkingTreatmentRecord`, session-generated `HealthRecord` / `PregnancyCheck`, Animal/Pasture live links and historical snapshots |
| Dashboard/Home read-model contracts | Existing Animal/Pasture/Working/Field Check entities only; no dashboard/home persistence entities |
| `PersistenceTransactionPreconditionContract` | `Animal.editorRevision`; Pasture existence and resident-set revalidation immediately before mutation |
| `PersistenceTransactionRollbackContract` | Complete 18-entity graph observability for fault-injected Animal aggregate and Pasture-delete rollback; write-scope recovery/disposal |
| `MutationBoundaryContract` | No additional entity; all throwing write entry points must publish only after their final Core Data commit |

## Physical model decisions

### Model file and generated classes

Create one versioned model:

```text
yaHerd/Data/Persistence/CoreData/yaHerdModel.xcdatamodeld
```

Use one initial model version. A named entity configuration is optional; use one only if it provides a concrete local-store benefit. Do not retain the old `CloudData` name merely as historical baggage.

Managed-object classes should be explicit, Data-layer-only types with a `CD` prefix, for example:

- `CDHerd`
- `CDAnimal`
- `CDAnimalTag`
- `CDPasture`

Use **Manual/None** code generation. Keep the subclasses under:

```text
yaHerd/Data/Persistence/CoreData/ManagedObjects/
```

Managed-object subclasses contain persisted properties and Core Data accessors only. Business rules, normalization, validation, transaction planning, and presentation helpers do not belong on managed objects.

### One local store

The production topology is intentionally simple:

```text
NSPersistentContainer
└── yaHerd.sqlite
```

All business entities live in the same local persistent store. There is no private/shared split, no CloudKit container option, and no store routing based on collaboration ownership.

### Herd is the logical ownership root

`Herd` is the root of one complete application graph.

Every herd-owned business entity except `Herd` has a direct Core Data relationship to its owning `Herd`, even when ownership can also be inferred through another parent. That direct relationship provides:

- a single scope for repository queries;
- same-herd relationship validation;
- straightforward integrity diagnostics;
- a clean future boundary if multi-herd local workflows are expanded later.

Application code treats `herd` as required for persisted herd-owned records. In the physical Core Data model, required relationships should be modeled as nonoptional when creation order and transaction semantics safely guarantee them. Use optionality only where the application genuinely permits absence or where a specific Core Data lifecycle requirement demands it; do not make relationships optional solely because CloudKit once required that.

Deleting a Herd is a destructive operation over its owned graph and should not be exposed casually in product UI. The relationship graph and delete rules must make the effect explicit and testable.

### Selected/current Herd and repository scope

The application operates against one current Herd workspace at a time unless a future feature explicitly introduces cross-Herd behavior.

- the current Herd is identified by its application UUID;
- selection is local application state, not duplicated business data;
- feature repository and transaction instances are scoped to that Herd where practical;
- every herd-owned read is constrained to the current Herd scope;
- every herd-owned write assigns the current Herd relationship;
- a repository must never choose a Herd by arbitrary fetch order.

`HerdRepository.fetchCurrentHerd()` therefore means **fetch the current application Herd**, not "fetch the first Herd returned by Core Data."

If the product remains single-Herd, startup/bootstrap may deterministically create the first Herd only through the explicit local bootstrap/onboarding boundary. Repository query methods should not create data as a side effect of an empty fetch.

### Application identity

Every independently persisted entity listed in this document has:

```text
id: UUID
```

Rules:

- `id` is the persisted `ApplicationEntityID`.
- The application assigns it before the first save.
- It never changes during ordinary updates or store reloads.
- `Herd` identity is store-global.
- Herd-owned entity identity is resolved inside the owning/current Herd scope. Repositories must query by Herd plus `id`, not search the whole store by `id` alone.
- Add a local fetch index for `id` on every entity and structure Herd-scoped queries so the owning-Herd predicate is always part of lookup.
- Duplicate UUIDs inside the same entity type and identity scope are persistence integrity failures.
- The same UUID in different Herd scopes is not automatically corruption. Permanent feature contracts own any intentional cross-Herd reuse; stable built-in Tag Color IDs are the current required case.
- A global Core Data unique constraint on `id` is appropriate only when the entity's identity is actually store-global. Do not add a global `id` constraint to a herd-owned entity when it would reject valid feature behavior. Repository/transaction code must enforce the applicable identity scope and translate any physical constraint failures into meaningful application errors rather than relying on silent merge behavior.

Embedded value objects may also contain UUIDs without becoming managed entities. Their IDs are scoped to the value object contract and are not independently repository-addressable entities.

### Physical optionality and defaults

Physical Core Data optionality should reflect real application/storage semantics rather than former CloudKit restrictions.

Use these rules:

- application identity UUIDs such as `id` are required and assigned before first save;
- `Animal.editorRevision` is required and assigned on create;
- dates and scalar values that are required by a valid entity should be physically required unless an actual creation workflow needs a temporary incomplete state;
- optional Domain values remain physically optional;
- encoded `Data` payloads must contain a valid Data-layer representation; do not use arbitrary empty bytes as a fake payload;
- enum raw strings, display strings, booleans, counts, and numeric values should have defaults only when that default is a legitimate creation-state value;
- managed-object factories and transaction writers assign every application-required value before save;
- mappers treat missing required persisted values as integrity failures; they do not invent UUIDs, dates, enum states, or payloads to hide invalid data.

### Relationship and integrity rules

- Every relationship has an inverse unless there is a documented Core Data reason not to.
- Choose delete rules from product semantics, not framework convenience.
- `Deny` may be used when it directly expresses a real local integrity invariant and the Domain workflow handles the resulting failure; it is no longer globally forbidden by CloudKit compatibility. Prefer explicit Domain validation when it gives clearer product behavior.
- Ordered Core Data relationships are optional; use explicit `sortOrder` fields or encoded ordered value payloads when ordering is part of the Domain contract.
- Domain enums persist as stable raw strings through Data mapping rather than framework-dependent transformables.
- Small Domain value collections persist as explicit `Data` payloads with a stable Data-layer codec when they are not independently managed entities.

## Final entity inventory

The initial production model contains **18 managed entities**:

1. `Herd`
2. `TagColorDefinition`
3. `AnimalStatusReference`
4. `PastureGroup`
5. `Pasture`
6. `Animal`
7. `AnimalTag`
8. `MovementRecord`
9. `StatusRecord`
10. `HealthRecord`
11. `PregnancyCheck`
12. `FieldCheckSession`
13. `FieldCheckAnimalCheck`
14. `FieldCheckFinding`
15. `WorkingTreatmentTemplate`
16. `WorkingSession`
17. `WorkingQueueItem`
18. `WorkingTreatmentRecord`

`WorkingTreatmentPlanItem` and `DistinguishingFeature` remain embedded Domain value objects, not managed entities. They are not independently queried or edited outside their owning aggregate.

Old `CollaborationRevisionRecord`, sharing-bridge `Shared*Record` types, bridge conflict snapshots, repair journals, sync metadata, and similar synchronization artifacts are explicitly **not** part of the production model.

## Entity definitions

The attribute lists below describe persisted state. Domain naming remains authoritative at repository boundaries; managed-property names may differ slightly when required by Core Data code generation, but semantic duplication should not be introduced.

### Herd

Attributes:

- `id: UUID`
- `name: String`
- `createdAt: Date`
- `updatedAt: Date`

Relationships:

- to-many ownership relationships to every herd-owned entity, all with inverses;
- parent-side delete rule: normally `Cascade` for the herd-owned graph.

Notes:

- `Herd` is a local application scope root, not a share root.
- Do not persist the SwiftData `schemaVersion` field. Core Data model versions own persistence schema versioning.
- Do not add synchronization, participant, owner-device, or collaboration metadata.

### TagColorDefinition

Attributes:

- `id: UUID`
- `name: String`
- `prefix: String`
- `red: Double`
- `green: Double`
- `blue: Double`
- `alpha: Double`
- `sortOrder: Int64`
- `isHidden: Bool`
- `isDefault: Bool`
- `createdAt: Date`
- `updatedAt: Date`

Relationships:

- `herd -> Herd`
- inverse `tags <- AnimalTag.color`; color deletion nullifies tag color relationships.

Rules:

- application built-ins are stable application constants and may be visible even when no physical override row exists; materializing a built-in in one Herd must not force materialization in another Herd;
- default/visible-color uniqueness is a Domain/repository invariant; add a database constraint only if it precisely represents the intended rule;
- `deleteColors(ids:)` is a visible-library removal operation, not unconditional physical deletion. A referenced custom definition must remain persisted as hidden and resolvable by UUID so retired tags, Field Check history, and Working history retain the original prefix/RGBA definition;
- deleting a materialized built-in removes/resets the Herd-specific override and exposes the canonical application definition again; it must not erase the built-in application identity;
- normalized-name collision reconciliation preserves the canonical application UUID and must atomically remap every affected color reference in the Herd: live/retired `AnimalTag.color`, Field Check roster and dam-color snapshots, Field Check finding color snapshots, and Working queue animal/dam-color snapshots;
- if collision reconciliation changes any AnimalTag color UUID, rotate each affected Animal's `editorRevision` in that same logical transaction;
- ordinary hide/remove operations do not rewrite historical snapshot UUIDs merely because the definition is no longer visible.

### AnimalStatusReference

Attributes:

- `id: UUID`
- `name: String`
- `baseStatusRawValue: String`
- `createdAt: Date`

Relationships:

- `herd -> Herd`
- inverse `animals <- Animal.statusReference`; delete rule from reference to animals is `Nullify` unless the final Domain deletion policy requires stricter protection.

### PastureGroup

Attributes:

- `id: UUID`
- `name: String`
- `grazeDays: Int64`
- `restDays: Int64`

Relationships:

- `herd -> Herd`
- `pastures <- Pasture.group`; deleting a group nullifies group membership and does not delete pastures.

### Pasture

Attributes:

- `id: UUID`
- `name: String`
- `sortOrder: Int64`
- `acreage: Double?`
- `usableAcreage: Double?`
- `targetAcresPerHead: Double?`
- `lastGrazedDate: Date?`

Relationships:

- `herd -> Herd`
- `group -> PastureGroup`
- inverse `animals <- Animal.currentPasture`
- inverse working-session/queue references
- inverse field-check-session references

Delete behavior:

- deleting a pasture nullifies non-owning relationships;
- the Domain-authored pasture deletion transaction must move the Domain-selected active, unarchived resident set and write movement history before the pasture is deleted;
- sold, dead, or archived Animals may still retain a live `currentPasture` relationship before deletion even though they are outside that active resident move set. Deleting the Pasture nullifies those relationships and rotates every affected surviving Animal's `editorRevision`;
- deleting a Pasture never implicitly deletes its `PastureGroup`; an empty group remains a valid persisted group;
- field-check sessions are archived/snapshotted before deletion and survive pasture deletion;
- Working source/collected-from/destination live Pasture relationships nullify as applicable while their historical UUID/name snapshots remain unchanged. An active Working session remains readable, but any future collection/destination mutation must revalidate historical UUIDs against live Pasture reference data.

### Animal

Attributes:

- `id: UUID`
- `editorRevision: UUID`
- `name: String`
- `sexRawValue: String`
- `birthDate: Date`
- `statusRawValue: String`
- `saleDate: Date?`
- `salePrice: Double?`
- `reasonSold: String?`
- `deathDate: Date?`
- `causeOfDeath: String?`
- `isArchived: Bool`
- `archivedAt: Date?`
- `archiveReason: String?`
- `distinguishingFeaturesData: Data`

Relationships:

- `herd -> Herd`
- `statusReference -> AnimalStatusReference`
- `currentPasture -> Pasture`
- `sire -> Animal`
- `dam -> Animal`
- `activeWorkingSession -> WorkingSession`
- `tags <- AnimalTag.animal`
- `healthRecords <- HealthRecord.animal`
- `pregnancyChecks <- PregnancyCheck.animal`
- `movementRecords <- MovementRecord.animal`
- `statusRecords <- StatusRecord.animal`
- inverse offspring relationships for sire/dam
- non-owning references from Working and Field Check history.

Delete behavior:

- hard deleting an animal cascades its animal-owned tags, health records, pregnancy checks, movement records, and status records;
- sire/dam links on offspring nullify;
- Working/Field Check historical links to the animal nullify and rely on their snapshots where history must remain readable.

Important differences from SwiftData:

- **Do not persist `tagNumber` or `tagColorID` on Animal.** `AnimalTag` is the only source of primary/secondary/retired tag state.
- **Do not persist `statusReferenceID` separately from the `statusReference` relationship.** Map the relationship to/from the UUID-based Domain contract.
- **Do not persist `locationRawValue`.** Location is derived: an animal with `activeWorkingSession` is in the working pen; otherwise it is in pasture context, with `currentPasture == nil` representing pasture-unassigned.
- Archive state uses the final names `isArchived`, `archivedAt`, and `archiveReason`; do not carry the SwiftData `isSoftDeleted` naming forward.

`editorRevision` implements `AnimalAggregateRevision`. Generate it on create and rotate it whenever editor-owned animal scalar state, editor-owned relationships, or tag state changes **through any public mutation path**, not only through `AnimalAggregateTransactionWriting`. This includes direct Animal update/move/tag APIs, Working operations that change pasture/working ownership or replace the primary tag, Field Check operations that materially change editor-owned Animal state, Tag Color collision reconciliation that remaps an AnimalTag color UUID, parent deletion that nullifies sire/dam relationships on surviving offspring, and Pasture deletion that moves or nullifies `currentPasture`. A multi-Animal operation rotates every affected surviving aggregate. Adding standalone health or pregnancy child rows does not rotate the revision because those child collections are outside the editor-owned aggregate state.

An update transaction compares the expected UUID before **any** staged mutation so a stale editor cannot overwrite newer local persisted state. If the Animal was hard-deleted after the editor loaded it, the update fails as a missing aggregate rather than recreating it or converting the failure into a generic stale-revision success path.

`distinguishingFeaturesData` contains the encoded `[DistinguishingFeature]` value collection. The Data layer owns the codec; Domain and Presentation continue to use `[DistinguishingFeature]`.

### AnimalTag

Attributes:

- `id: UUID`
- `number: String`
- `isPrimary: Bool`
- `isActive: Bool`
- `assignedAt: Date`
- `removedAt: Date?`

Relationships:

- `herd -> Herd`
- `animal -> Animal`
- `color -> TagColorDefinition`

Rules:

- active tagged animals have exactly one active primary tag;
- untagged animals may have no active tags;
- retired tags remain persisted with `isActive == false` and `removedAt` rather than being deleted during an ordinary tag change;
- tag number/color uniqueness rules are checked by Domain/repository logic and may be reinforced with local Core Data constraints only when those constraints match the full intended rule;
- changing tag state also rotates the owning animal's `editorRevision` in the same transaction.

### MovementRecord

Attributes:

- `id: UUID`
- `date: Date`
- `fromPastureIDSnapshot: UUID?`
- `fromPastureNameSnapshot: String?`
- `toPastureIDSnapshot: UUID?`
- `toPastureNameSnapshot: String?`

Relationships:

- `herd -> Herd`
- `animal -> Animal`

Do not create live relationships from movement history to pastures. Movement history must survive pasture deletion and must describe what occurred even after pasture names change.

For Working completion, when the Animal is still in the working pen, `fromPastureIDSnapshot` / `fromPastureNameSnapshot` come from that queue item's captured collected-from snapshots. The `toPastureIDSnapshot` / `toPastureNameSnapshot` values come from the live destination resolved for the final completion assignment. If the Animal was already released from Working ownership and is currently in a pasture, the movement origin comes from that current live pasture instead.

### StatusRecord

Attributes:

- `id: UUID`
- `date: Date`
- `oldStatusRawValue: String`
- `newStatusRawValue: String`
- `oldStatusReferenceIDSnapshot: UUID?`
- `newStatusReferenceIDSnapshot: UUID?`

Relationships:

- `herd -> Herd`
- `animal -> Animal`

Status history belongs to the animal and cascades only on explicit animal hard deletion.

### HealthRecord

Attributes:

- `id: UUID`
- `date: Date`
- `treatment: String`
- `notes: String?`

Relationships:

- `herd -> Herd`
- `animal -> Animal`
- `workingSession -> WorkingSession?`

Delete behavior:

- animal hard deletion cascades animal-owned health history;
- deleting a working session cascades health records generated as work data for that session, matching the existing `WorkingSessionDeleting` behavior.

### PregnancyCheck

Attributes:

- `id: UUID`
- `date: Date`
- `resultRawValue: String`
- `technician: String?`
- `estimatedDaysPregnant: Int64?`
- `dueDate: Date?`

Relationships:

- `herd -> Herd`
- `animal -> Animal`
- `sire -> Animal?`
- `workingSession -> WorkingSession?`

Delete behavior mirrors HealthRecord for the owning Animal and Working session: animal hard deletion removes the animal-owned check, and deleting the Working session removes checks generated as work data for that session.

The `sire` relationship has independent semantics from the owning `animal` relationship. Hard deleting the referenced sire **nullifies only `PregnancyCheck.sire`**. The pregnancy row, owning Animal relationship, UUID, date/result/technician/days/due-date payload, and Working-session linkage remain unchanged.

### FieldCheckSession

Attributes:

- `id: UUID`
- `startedAt: Date`
- `completedAt: Date?`
- `notes: String`
- `expectedHeadCountSnapshot: Int64`
- `quickCowCount: Int64`
- `quickHeiferCount: Int64`
- `quickCalfCount: Int64`
- `quickBullCount: Int64`
- `quickSteerCount: Int64`
- `pastureIDSnapshot: UUID?`
- `pastureNameSnapshot: String`
- `pastureArchivedAt: Date?`

Relationships:

- `herd -> Herd`
- `pasture -> Pasture?`
- `animalChecks <- FieldCheckAnimalCheck.session`
- `findings <- FieldCheckFinding.session`

Delete behavior:

- deleting a field-check session cascades its checks and findings;
- deleting a pasture nullifies the live pasture relationship but does not delete the session;
- the pasture delete transaction records `pastureArchivedAt` while preserving the pasture UUID/name snapshots.

### FieldCheckAnimalCheck

Attributes:

- `id: UUID`
- `animalIDSnapshot: UUID?`
- `rosterTagNumberSnapshot: String`
- `rosterTagColorIDSnapshot: UUID?`
- `damRosterTagNumberSnapshot: String`
- `damRosterTagColorIDSnapshot: UUID?`
- `animalNameSnapshot: String`
- `animalSexRawValueSnapshot: String`
- `animalTypeRawValueSnapshot: String`
- `wasExpectedAtStart: Bool`
- `countedAt: Date?`
- `missingConfirmedAt: Date?`
- `note: String`

Relationships:

- `herd -> Herd`
- `session -> FieldCheckSession`
- `animal -> Animal?`

The live animal link may disappear. Snapshots are the historical source of display identity for the check.

### FieldCheckFinding

Attributes:

- `id: UUID`
- `recordedAt: Date`
- `typeRawValue: String`
- `severityRawValue: String`
- `statusRawValue: String`
- `note: String`
- `animalIDSnapshot: UUID?`
- `animalDisplayTagNumberSnapshot: String`
- `animalDisplayTagColorIDSnapshot: UUID?`
- `animalNameSnapshot: String`
- `pastureNameSnapshot: String`
- `sessionIDSnapshot: UUID?`

Relationships:

- `herd -> Herd`
- `session -> FieldCheckSession`
- `animal -> Animal?`

A finding belongs to the session but must remain understandable if its linked animal is hard-deleted.

Finding snapshot mutation rules:

- adding a finding for a tracked animal copies display tag/color and pasture display state from the session's captured roster/session snapshots, never from the animal's or pasture's later live values;
- updating a finding without changing its animal preserves the session-time historical identity rather than refreshing from live records;
- reassigning a finding to another tracked animal replaces the finding's animal snapshot fields from that target animal's **session roster snapshot**, even if the live target has since been renamed/retagged;
- editing an orphaned finding after the live Animal has been hard-deleted preserves its stored historical snapshot fields;
- unresolved finding reassignment/deletion must keep the associated roster `needsAttention` / missing projection synchronized through the existing persisted check/finding state; do not introduce a redundant persisted `needsAttention` flag merely for presentation.

### WorkingTreatmentTemplate

This replaces the persistence-layer legacy `WorkingProtocolTemplate` name. Domain/presentation already use treatment-template terminology.

Attributes:

- `id: UUID`
- `name: String`
- `itemsData: Data`

Relationships:

- `herd -> Herd`

`itemsData` encodes the ordered `[WorkingTreatmentPlanItem]` value collection. Item UUIDs remain stable within the template payload.

### WorkingSession

Attributes:

- `id: UUID`
- `date: Date`
- `statusRawValue: String`
- `treatmentTemplateNameSnapshot: String`
- `plannedTreatmentsData: Data`
- `sourcePastureIDSnapshot: UUID?`
- `sourcePastureNameSnapshot: String?`

Relationships:

- `herd -> Herd`
- `sourcePasture -> Pasture?`
- `queueItems <- WorkingQueueItem.session`
- `activeAnimals <- Animal.activeWorkingSession`
- `treatmentRecords <- WorkingTreatmentRecord.session`
- session-linked `healthRecords`
- session-linked `pregnancyChecks`

Delete behavior:

- deleting a session restores/clears any active animal working-session state through the transaction contract before delete;
- session deletion cascades queue items, working treatment records, session-generated health records, and session-generated pregnancy checks;
- `activeAnimals` nullify;
- source pasture deletion only nullifies the live link; snapshots remain.

Projection rule:

- `WorkingSessionDetailSnapshot.sourcePastureID` / `sourcePastureName` come from the captured snapshot attributes, not from the live relationship;
- `WorkingSessionDetailSnapshot.isSourcePastureAvailable` is derived from whether the live `sourcePasture` relationship still resolves. A historical non-nil source UUID must never imply that the deleted pasture is still selectable for collection or finish fallback;
- session summary display uses the captured source-pasture name so later live renames/deletion do not rewrite Working history.

Important differences from SwiftData:

- do not persist deprecated `currentQueueIndex`;
- do not port legacy SwiftData `notes`; there is no Domain Working-session notes contract or production caller;
- use treatment terminology rather than `protocolName` / `protocolItems` persistence names;
- planned treatment items remain an ordered encoded value snapshot because they are session/template-owned values. `WorkingTreatmentRecord.treatmentItemID` is a stable treatment-entry UUID that may match a planned item or represent a valid one-off treatment; do not enforce current-plan membership;
- preserve all declared `WorkingSessionStatus` raw values, including read-compatible `cancelled`, even though current production flows do not create new cancelled sessions.

### WorkingQueueItem

Attributes:

- `id: UUID`
- `statusRawValue: String`
- `completedAt: Date?`
- `animalIDSnapshot: UUID`
- `animalTagNumberSnapshot: String`
- `animalTagColorIDSnapshot: UUID?`
- `animalNameSnapshot: String`
- `animalSexRawValueSnapshot: String`
- `animalDamDisplayTagNumberSnapshot: String?`
- `animalDamDisplayTagColorIDSnapshot: UUID?`
- `collectedFromPastureIDSnapshot: UUID?`
- `collectedFromPastureNameSnapshot: String?`
- `destinationPastureIDSnapshot: UUID?`
- `destinationPastureNameSnapshot: String?`

Relationships:

- `herd -> Herd`
- `session -> WorkingSession`
- `animal -> Animal?`
- `collectedFromPasture -> Pasture?`
- `destinationPasture -> Pasture?`

Important differences from SwiftData:

- do not persist deprecated `queueOrder`; presentation sorting is based on the product's animal/tag rules;
- do not port legacy SwiftData `workNotes`; Working work notes are represented by the session-linked generated observation record exposed through `WorkingQueueItemEditorSnapshot.observationNotes`;
- the animal identity/display snapshots and collected-from pasture UUID/name snapshots are captured when the queue item is created and remain historical values for that animal's collection event. If the live source pasture is renamed mid-session, animals collected afterward capture the new live name while the session source snapshot and earlier queue rows retain their original names;
- an explicit primary-tag replacement performed through the Working queue is part of that session's work and updates the queue's captured animal tag number/color snapshots in the same logical transaction; unrelated later Animal edits do not rewrite those snapshots;
- preserve animal sex and dam tag number/color in addition to the animal's own tag so completed-session history still satisfies `WorkingQueueItemSnapshot` after the live Animal relationship is nullified;
- snapshots preserve session history if an animal or pasture later disappears or its current display relationships change;
- queue destination/collected-from snapshot UUIDs remain historical values after live pasture deletion. Editor/finish workflows must revalidate those UUIDs against live pasture reference data before allowing a new mutation;
- destination selection may be provisional while a session is active. `completeSession` resolves the final live destination for every queue item and writes the final destination UUID/name snapshots in the same transaction as movement/session completion. A pasture rename before finish is therefore reflected in the committed destination snapshot; later renames do not rewrite finished history;
- preserve all declared `WorkingQueueStatus` raw values, including read-compatible `skipped`. Current production flows do not create new skipped rows, but persisted skipped history remains Not Worked and must continue decoding after cutover.

### WorkingTreatmentRecord

Attributes:

- `id: UUID`
- `date: Date`
- `treatmentItemID: UUID`
- `itemNameSnapshot: String`
- `given: Bool`
- `doseAmount: Double?`
- `doseUnitRawValue: String?`
- `administrationRouteRawValue: String?`
- `animalIDSnapshot: UUID`

Relationships:

- `herd -> Herd`
- `animal -> Animal?`
- `session -> WorkingSession`

`treatmentItemID` is the stable logical identifier captured for the treatment entry. It may match a session planned-treatment item, may refer to an item that was later removed from/replaced in the session plan, or may represent a valid one-off treatment that was never in the plan. Do not enforce membership in `plannedTreatmentsData`, and do not create a relationship to the reusable template. `itemNameSnapshot`, `given`, dose, and route remain historical event values independent of later plan/template edits.

Deleting a session cascades its treatment records. Animal hard deletion nullifies the working-history relationship rather than deleting the session record; the animal UUID snapshot remains available for historical diagnostics.

## Relationship/delete-rule matrix

The parent-side behavior is the important rule.

| Parent relationship | Delete rule | Reason |
| --- | --- | --- |
| Herd -> all herd-owned records | Cascade | Herd is one owned local graph |
| TagColorDefinition -> tags | Nullify | Tag history must not be destroyed with a color definition |
| AnimalStatusReference -> animals | Nullify | Reference-data deletion must not delete animals |
| PastureGroup -> pastures | Nullify | Deleting a group only removes grouping |
| Pasture -> animals | Nullify | Domain transaction moves residents first; this is a safety fallback |
| Pasture -> Working/Field Check references | Nullify | Historical/work records survive pasture deletion |
| Animal -> tags | Cascade | Tags are part of the animal aggregate |
| Animal -> status/movement/health/pregnancy history | Cascade | These records are animal-owned history |
| Animal -> offspring parent links | Nullify | Deleting a parent must not delete offspring; surviving offspring revisions rotate because editor-owned parent state changed |
| Animal (as PregnancyCheck sire) -> PregnancyCheck.sire | Nullify | Deleting a referenced sire preserves the pregnancy row and complete historical payload |
| Animal -> Working/Field Check historical references | Nullify | Session/check history survives animal deletion |
| WorkingSession -> queue items | Cascade | Queue is session-owned |
| WorkingSession -> treatment records | Cascade | Treatment completion is session work data |
| WorkingSession -> linked health/pregnancy records | Cascade | Matches current delete-session semantics |
| WorkingSession -> active animals | Nullify | Transaction restores animal location before deletion |
| FieldCheckSession -> animal checks | Cascade | Roster/check state is session-owned |
| FieldCheckSession -> findings | Cascade | Findings are session-owned |

Use `Deny` only when a final local product invariant is clearer and safer with it than with Domain validation; do not add it mechanically.

## Historical snapshot policy

Live relationships answer "what is this linked to now?" Snapshots answer "what was true when this event occurred?"

Persist snapshots when the historical record must remain understandable after the linked object can be renamed or deleted. Snapshot attributes are historical data, not cached mirrors of live relationships: later ordinary edits to the live Animal/Pasture/Tag must not rewrite them unless the feature contract explicitly defines the current mutation as replacing that historical association (for example, Field Check finding reassignment or Working primary-tag replacement inside the session).

Required snapshot cases:

- movement from/to pasture UUID and name;
- field-check pasture UUID/name;
- field-check animal/tag/name/sex/type;
- field-check finding animal/session/pasture display state;
- working-session source pasture UUID/name;
- working queue animal UUID/name/tag/color/sex/dam-tag identity plus source/destination pasture identity/display;
- working treatment item name/ID and animal UUID.

Do not add snapshot copies to ordinary current-state entities merely to avoid following a relationship.

## Transaction implications

### Animal aggregate create/update

`AnimalAggregateTransactionWriting` owns one Core Data transaction containing:

- Animal create/update;
- current pasture/parent/status-reference relationship changes;
- complete tag reconciliation;
- retired tag preservation;
- generated status/movement history required by the mutation;
- `editorRevision` validation/rotation.

The transaction saves once after all mutations succeed. No repository method inside the transaction independently saves.

### Pasture deletion

`PastureDeletionTransactionWriting` executes the Domain-authored plan on one write context:

1. revalidate the expected resident set;
2. move residents and write MovementRecord snapshots;
3. archive affected FieldCheckSession pasture history;
4. delete pasture objects;
5. save once.

Live Working references to a deleted pasture nullify automatically while their snapshots remain.

### Working and Field Check

Existing one-call Domain ports that represent transaction boundaries remain one Core Data save boundary. In particular, queue completion/edit, session completion/deletion, Field Check session setup, tracked-animal changes, and finding writes must not be decomposed into separately saving repositories.

Working deletion must distinguish session-generated work data from independent Animal history. Deleting a Working session removes only that session's queue/treatment graph and session-generated health/pregnancy rows; unrelated standalone Animal health/pregnancy history survives. Conversely, hard deleting the Animal cascades its generated health/pregnancy rows but leaves Working queue/treatment history readable through its captured Animal snapshots.

Field Check completion/reopen and finding writes may update more than one persisted row (for example completion normalization or finding-driven missing/attention state). Each public call remains atomic.

### Cross-cutting failure recovery and mutation publication

For every Core Data write boundary:

- validation that can become stale is rechecked in the write transaction before mutation;
- a throwing operation commits no partial business state;
- a reusable failed write context is rolled back/reset before the operation returns, or a one-shot transaction context is explicitly discarded;
- saving the same reusable context again after the failure must not leak previously staged objects, relationship changes, or deletes;
- application mutation publication occurs only after the final durable save succeeds;
- a thrown persistence/validation/precondition error publishes no successful mutation event.

## Archive versus delete semantics

### Animal

Archive is application state, not a Core Data deletion:

```text
isArchived
archivedAt
archiveReason
```

Sold/deceased remain status outcomes and may coexist with an unarchived record according to Domain rules. Hard delete is an explicit destructive operation and applies the delete rules above.

### Pasture

Pasture delete is a real delete after the Domain transaction preserves required movement and Field Check history.

### Field Check

Pasture deletion archives the pasture reference inside the session; it does not delete the Field Check session.

### Working session

`active`, `finished`, and `cancelled` are persisted status values. Explicit session deletion is a real delete of the session-owned work graph.

## Embedded value-object encoding

Use a small Data-layer codec for these persisted payloads:

- `[DistinguishingFeature]`
- `[WorkingTreatmentPlanItem]`

Requirements:

- use an explicit version-independent Codable representation;
- do not encode managed objects or persistence-native IDs;
- preserve embedded UUIDs and ordering;
- fail mapping clearly when payloads are corrupt rather than silently inventing replacement IDs;
- keep transitional legacy decoding out of the production Core Data codec unless a real shipped Core Data schema later requires migration.

The existing SwiftData compatibility decoders are not requirements for the new store.

## Initial local indexes and constraints

Start with indexes that match existing query patterns:

- `id` on every managed entity;
- Animal: `statusRawValue`, `birthDate`, `isArchived`;
- AnimalTag: `number`, `isActive`, `isPrimary`;
- Pasture: `sortOrder`;
- WorkingSession: `statusRawValue`, `date`;
- FieldCheckSession: `startedAt`, `completedAt`;
- FieldCheckFinding: `statusRawValue`, `recordedAt`.

For store-global entities such as `Herd`, add a unique constraint on application `id` when model validation confirms it matches the permanent contract. Do not add a global `id` uniqueness constraint to a herd-owned entity. Herd-owned identity must remain compatible with the owning-Herd scope; enforce that scope in repository/transaction validation and use a physical constraint only if the final Core Data model can express the same scoped invariant without rejecting valid cross-Herd feature behavior. Domain/repository validation remains authoritative for business rules such as active tag uniqueness and default-color policy.

Add further indexes only when actual Core Data query behavior justifies them.

## Local store and mapping rules

Repository/transaction code must use the current Herd scope for herd-owned records.

For new records:

1. resolve the current Herd by application UUID;
2. verify every relationship target belongs to that same Herd where the relationship is herd-scoped;
3. assign the Herd relationship before save;
4. reject cross-Herd relationships that violate Domain integrity.

Ordinary feature repositories must scope every herd-owned fetch to the current Herd UUID rather than relying on globally unique IDs alone.

Mapping rules:

- required persisted values map directly to Domain values;
- mappers must not invent Domain entities or required scalar values to fill invalid persisted state;
- `Animal.editorRevision` remains authoritative for stale-editor detection;
- `NSManagedObjectID` and store identifiers never enter Domain snapshots.

## Explicitly rejected SwiftData/sync baggage

The Core Data model must **not** reproduce these current or historical implementation artifacts:

- `Animal.tagNumber` / `Animal.tagColorID` duplicate primary-tag fields;
- `Animal.locationRawValue` when location can be derived from active working-session state;
- `Animal.statusReferenceID` alongside a real status-reference relationship;
- `Herd.schemaVersion`;
- `WorkingSession.currentQueueIndex`;
- `WorkingQueueItem.queueOrder`;
- legacy persistence naming based on "protocol" where the product now uses treatment-template terminology;
- collaboration revision records, participant/device IDs, tombstones, owner markers, or bridge lineage;
- SwiftData public-ID bridge repair metadata/backups;
- mirror entities and `Shared*Record` types;
- duplicated relationship IDs unless the value is explicitly a historical snapshot;
- CloudKit record identifiers, zones, share metadata, or private/shared store routing fields.

## Behavioral contracts before the physical model

Before creating `yaHerdModel.xcdatamodeld`, establish permanent persistence-neutral **characterization contracts for behavior the current application already implements**. These tests define product behavior through Domain repository/transaction protocols rather than SwiftData types.

Existing SwiftData code may be inspected to understand current behavior, but repository policy intentionally does not add or restore a SwiftData contract runner. The contract definitions are permanent and run against Core Data when the corresponding persistence surface exists. A characterization contract must not require adding new production behavior to SwiftData merely so the old implementation can pass a target-architecture requirement.

At minimum the pre-model characterization milestone should lock down current behavior that is observable through today's Domain ports, including:

- application UUID identity preservation and duplicate-ID failure behavior;
- current animal create/update/tag/history behavior;
- movement and historical preservation behavior;
- pasture deletion behavior observable through the current workflow, without pretending its known multi-save implementation is already atomic;
- Field Check behavior and historical snapshots already supported by the current implementation;
- Working queue/session behavior and existing historical snapshots;
- mutation publication behavior on persistence success/failure where the current boundary exposes it.

Some end-state requirements are intentionally **target-only contracts** because SwiftData does not implement them today. Their first executable runner is the Core Data harness. Target-only contracts include:

- new historical snapshot fields that do not exist in the SwiftData schema, such as expanded Working queue sex/dam-tag snapshots;
- atomic rollback/no-partial-commit semantics for workflows known to be multi-save in SwiftData, including pasture deletion;
- Core Data uniqueness/integrity and delete-rule behavior selected by the final model;
- local store load/recovery behavior that belongs to the Core Data implementation.

Do not postpone characterization of existing behavior until after Core Data repositories exist, and do not force target-only behavior into SwiftData to make the two implementations superficially symmetrical. Together, the characterization contracts and target-only Core Data contracts form the executable persistence specification.

## Model validation required when implemented

After the pre-model characterization milestone, the Core Data foundation PR that creates `yaHerdModel.xcdatamodeld` should add focused model-level tests/validation for the production implementation, including:

- the model loads successfully;
- every durable entity has an `id` UUID attribute;
- required relationships and inverses match this blueprint;
- delete rules match product semantics;
- entity application-ID uniqueness constraints are present where the final model intentionally uses them;
- every herd-owned entity has a Herd relationship;
- an animal aggregate create/update preserves UUIDs and rotates `editorRevision` correctly;
- pasture deletion preserves Movement and Field Check history as specified;
- Working queue history retains animal tag/color, sex, and dam tag/color after the live animal relationship disappears;
- invalid cross-Herd relationships are rejected by persistence code;
- required attributes cannot silently map to invented values.

As Core Data repositories are implemented, point the same permanent characterization contracts at the Core Data harness feature by feature and add target-only contracts as their required production capabilities become available. Do not rewrite existing contracts to accommodate persistence-specific behavior.

## Implementation sequence from this blueprint

The Core Data replacement is test-first at the persistence boundary. The model blueprint is established, but physical model/runtime implementation begins only after the permanent characterization contracts for existing behavior are in place.

```text
0. persistence-neutral characterization contracts for current behavior; no new SwiftData runner
1. reconcile this blueprint with behavior exposed by those characterization tests
2. yaHerdModel.xcdatamodeld + CD managed-object classes + model-structure tests
3. CoreDataPersistenceController / NSPersistentContainer local store setup + Core Data contract harness
4. Herd/reference-data repository + deterministic Herd scope
5. Pasture repositories + atomic pasture deletion transaction + target-only rollback contracts
6. Animal repositories + aggregate transaction + tag/history mapping
7. Field Check repositories
8. Working repositories + expanded historical-snapshot contracts
9. Dashboard/Home read models
10. switch PersistenceAssembly to Core Data
11. delete SwiftData models/repositories/bootstrap/obsolete repair code
12. strengthen final architecture verification and delete this cutover documentation when complete
```

Do not add temporary SwiftData production behavior or a SwiftData contract harness just to keep both systems symmetrical during this sequence. Inspect existing SwiftData only to understand current behavior; persistence-neutral contracts may remain unexecuted until their Core Data runner exists.
