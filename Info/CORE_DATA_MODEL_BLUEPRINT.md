# Core Data Model Blueprint

> Phase 1 implementation blueprint for the production Core Data model. This document turns the persistence rules in `ARCHITECTURE.md`, `TRANSACTION_BOUNDARIES.md`, and `CORE_DATA_CUTOVER.md` into a concrete schema design before any Core Data repositories are written.

This blueprint is intentionally **not** a SwiftData migration map. Development SwiftData stores, bridge records, repair metadata, and migration compatibility do not constrain this model.

When the real `.xcdatamodeld` and managed-object implementation are established, keep this document synchronized with the model until the Core Data cutover is complete. If the implementation intentionally diverges, update this document in the same PR rather than allowing two competing persistence designs.

## Goals

The first production Core Data model must:

- support the existing Domain behavior without exposing Core Data upward;
- use `ApplicationEntityID` / `UUID` as application identity;
- support one `NSPersistentCloudKitContainer` with private and shared stores;
- make `Herd` the share/root ownership boundary;
- support direct `CKShare` sharing of the real production graph;
- preserve historical records when their referenced pasture, animal, or display data can disappear;
- support the atomic transaction boundaries already defined in Domain;
- support optimistic animal-editor conflict detection;
- avoid schema choices that exist only because the SwiftData implementation needed them;
- satisfy Core Data + CloudKit model restrictions from the start.

## Non-goals

Do not use this work to add:

- SwiftData-to-Core Data migration;
- dual-write support;
- bridge snapshots or mirror entities;
- public-ID repair infrastructure;
- compatibility fields for deprecated SwiftData behavior;
- generic collaboration-revision records;
- CloudKit record IDs or managed-object IDs as application identity;
- app preferences/settings to Core Data.

## Physical model decisions

### Model file and generated classes

Create one versioned model:

```text
yaHerd/Data/Persistence/CoreData/yaHerdModel.xcdatamodeld
```

Use one initial model version and one entity configuration named `CloudData` containing all production business entities.

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

### One model, three store modes

The same `CloudData` configuration is used in every operating mode.

Local-only mode:

```text
local.sqlite
└── CloudData
```

iCloud mode:

```text
NSPersistentCloudKitContainer
├── private.sqlite  -> CKDatabase.Scope.private
└── shared.sqlite   -> CKDatabase.Scope.shared
```

Do not create separate private/shared entity models. The two iCloud stores use the same model and configuration.

All relationships for a herd must remain inside the same persistent store. Core Data/CloudKit sharing does not support cross-share relationships, and Core Data stores cannot own relationships across different persistent stores.

### Herd is the store/share root

`Herd` is the root of one complete application graph.

Every cloud-synchronized business entity except `Herd` has a direct optional Core Data relationship to its owning `Herd`, even when ownership can also be inferred through another parent. That direct relationship is deliberate because it provides:

- a single scope for repository queries;
- deterministic store assignment;
- same-herd relationship validation;
- one connected graph for Core Data/CloudKit sharing;
- simple integrity diagnostics.

Application code treats `herd` as required for persisted herd-owned records. The physical relationship remains optional because CloudKit-compatible Core Data models require optional relationships and imports may arrive out of relationship order.

An owned herd and all of its records live in the private store. A herd accepted from another owner and all records in that share live in the shared store. New objects are assigned to the same store/share as their owning herd before save.

Sharing starts from the `Herd` managed object. `NSPersistentCloudKitContainer` moves the connected object graph into the share's record zone. No business relationship may connect two different herd/share graphs.

### Selected herd and repository scope

A user may have more than one accessible Herd root at the same time. For example, the private store may contain a herd the user owns while the shared store contains one or more herds accepted from other owners. The app must never treat all accessible herds as one implicit data set.

The application operates on **exactly one selected Herd workspace at a time**:

- the selected Herd is identified by its application UUID;
- selection is local application state and is not a `CloudData` entity or synchronized business field;
- the persistence assembly resolves the selected Herd UUID to one concrete Herd and persistent store before constructing feature repositories;
- feature repository and transaction instances are scoped to that selected Herd for their lifetime;
- every herd-owned read includes the selected Herd scope, even when the Domain method does not carry a `herdID` parameter;
- every herd-owned write assigns the selected Herd relationship and routes the object to that Herd's store/share;
- a repository must never combine private and shared Herd graphs merely because both stores are attached to the same persistent container.

`HerdRepository.fetchCurrentHerd()` therefore means **fetch the selected Herd**, not "fetch the first Herd," "fetch the private Herd," or "fetch any default Herd." Existing feature contracts such as `CreateAnimalAggregateTransaction` do not need a Herd argument because the repository/transaction instance itself owns an immutable Herd scope. If a future feature intentionally needs to operate across multiple herds, it must use an explicit cross-workspace contract rather than weakening ordinary repository scoping.

Selection behavior is deterministic:

1. On first use with no Herd, create the user's owned Herd and select it.
2. On launch, restore the locally remembered selected Herd UUID when that Herd is still accessible.
3. If no remembered selection is valid and exactly one Herd is accessible, select that Herd.
4. If multiple Herds are accessible and there is no valid remembered selection, require an explicit workspace selection rather than guessing based on store order.
5. Successfully accepting another owner's share does **not** replace or delete an owned Herd. The accepted Herd becomes the selected workspace after acceptance so the user enters the graph they just accepted; the prior Herd remains available for later selection.
6. Switching Herds invalidates/rebuilds Herd-scoped feature dependencies, read state, and navigation state so IDs from one workspace cannot be resolved through another workspace's repositories.
7. If access to the selected shared Herd is revoked or removed, invalidate that selection. Select the sole remaining accessible Herd when exactly one remains; otherwise require a new explicit selection.

The selected-Herd preference may be stored using ordinary local app settings. It must not create a relationship between Herd graphs, influence CloudKit record identity, or become a second persistence source for business data.

### Application identity

Every independently persisted entity listed in this document has:

```text
id: UUID
```

Rules:

- `id` is the persisted `ApplicationEntityID`.
- The application assigns it before the first save.
- It never changes during ordinary updates, CloudKit imports, sharing, or store reloads.
- Every repository resolves entities by `id`, not `NSManagedObjectID`.
- No Core Data unique constraint is used; CloudKit does not support unique constraints.
- UUID duplication is detected by repository/transaction integrity checks and treated as an error.
- Add a local fetch index for `id` on every entity.

Embedded value objects may also contain UUIDs without becoming managed entities. Their IDs are scoped to the value object contract and are not independently repository-addressable entities.

### CloudKit model constraints

The production model follows these rules from the beginning:

- no Core Data unique constraints;
- no `Deny` delete rules;
- every relationship is optional in the physical model;
- every relationship has an inverse;
- every nonoptional attribute has an explicit static model default;
- no cross-configuration relationships;
- no ordered Core Data relationships; use explicit `sortOrder` fields or ordered encoded value payloads;
- no `Undefined` or object-ID attributes;
- Domain enums persist as stable raw strings through Data mapping rather than framework-dependent transformables;
- small Domain value collections persist as explicit `Data` payloads with a stable Data-layer codec when they are not independently managed entities.

Required application invariants are enforced by repository/transaction code before save even when CloudKit requires a physically optional relationship or attribute.

### Physical attribute optionality and defaults

The attribute declarations in the entity inventory describe **application semantics**. For example, `id: UUID` means a valid persisted Domain entity must have an application UUID; it does not mean the physical Core Data attribute should be marked nonoptional without a model default.

For every attribute in the `CloudData` configuration, the `.xcdatamodeld` must satisfy the CloudKit rule: the attribute is either physically optional **or** has an explicit static default value.

Use these rules when translating this blueprint into the physical model:

- application identity UUIDs such as `id` are physically optional and have no static default; factories assign them before the first save and repository mapping rejects a missing UUID;
- `Animal.editorRevision` is likewise physically optional with no static default; the animal aggregate transaction generates it on create and rotates it atomically on qualifying updates;
- required dates that do not have a semantically valid static default are physically optional and must be assigned before save;
- required encoded `Data` payloads are physically optional unless the model default is a valid encoded payload for the Data-layer codec; never use arbitrary empty bytes as a fake valid payload;
- enum raw strings, display strings, booleans, counts, and numeric values may be physically nonoptional only when they have an explicit static default that is also a valid creation-state value for that entity;
- optional Domain values remain physically optional unless there is a specific reason to model them otherwise;
- managed-object factories and transaction writers must assign every application-required value before save even when the physical model permits `nil`;
- mappers treat missing application-required attributes as incomplete/invalid imported state and omit or explicitly fail the aggregate according to repository policy; they do not invent UUIDs, dates, enum states, or encoded payloads to make an incomplete CloudKit import appear valid.

This distinction lets CloudKit import records in stages without weakening Domain invariants or introducing dangerous static UUID/revision defaults.

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

The current `CollaborationRevisionRecord`, sharing-bridge `Shared*Record` types, bridge conflict snapshots, repair journals, and similar migration/synchronization artifacts are explicitly **not** part of the production model.

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
- parent-side delete rule: `Cascade` for the herd-owned graph.

Notes:

- This is the only `CKShare` root.
- Do not persist the SwiftData `schemaVersion` field. Core Data model versions own persistence schema versioning.
- CKShare/participant metadata remains Core Data/CloudKit metadata, not Herd business fields.

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

- default/visible-color uniqueness is a Domain/repository invariant, not a Core Data unique constraint;
- normal removal should continue to prefer hiding a color when historical tag display must remain meaningful.

### AnimalStatusReference

Attributes:

- `id: UUID`
- `name: String`
- `baseStatusRawValue: String`
- `createdAt: Date`

Relationships:

- `herd -> Herd`
- inverse `animals <- Animal.statusReference`; delete rule from reference to animals is `Nullify`.

Rules:

- whether an in-use reference may be deleted is application policy; do not use Core Data `Deny`.

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
- the Domain-authored pasture deletion transaction must move residents and write movement history before the pasture is deleted;
- field-check sessions are archived/snapshotted before deletion and survive pasture deletion.

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

`editorRevision` implements `AnimalAggregateRevision`. Generate it on create and rotate it whenever editor-owned animal fields or any tag state changes. An update transaction compares the expected UUID before mutation. A CloudKit import carries the revision written by the remote transaction, so a stale editor observes a mismatch after that revision has imported.

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
- tag number/color uniqueness rules are checked by Domain/repository logic, not Core Data constraints;
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

Delete behavior mirrors HealthRecord: animal hard deletion removes the animal-owned check, and deleting the working session removes checks generated as work data for that session.

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
- `notes: String?`
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

Important differences from SwiftData:

- do not persist deprecated `currentQueueIndex`;
- use treatment terminology rather than `protocolName` / `protocolItems` persistence names;
- planned treatment items remain an ordered encoded value snapshot because they are session/template-owned values, while `WorkingTreatmentRecord.treatmentItemID` references the stable item UUID inside the session snapshot.

### WorkingQueueItem

Attributes:

- `id: UUID`
- `statusRawValue: String`
- `completedAt: Date?`
- `workNotes: String?`
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
- the animal identity/display snapshots are captured when the queue item is created and remain the historical source for the Working session;
- specifically preserve animal sex and dam tag number/color in addition to the animal's own tag so completed-session history still satisfies `WorkingQueueItemSnapshot` after the live Animal relationship is nullified;
- snapshots preserve session history if an animal or pasture later disappears or its current display relationships change.

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

`treatmentItemID` references an item UUID from the session's `plannedTreatmentsData`. Do not create a relationship to the reusable template; the session owns the treatment-plan snapshot used for actual work.

Deleting a session cascades its treatment records. Animal hard deletion nullifies the working-history relationship rather than deleting the session record; the animal UUID snapshot remains available for historical diagnostics.

## Relationship/delete-rule matrix

The parent-side behavior is the important rule. Every relationship still has an inverse and is physically optional for CloudKit compatibility.

| Parent relationship | Delete rule | Reason |
| --- | --- | --- |
| Herd -> all herd-owned records | Cascade | Herd/share is one owned graph |
| TagColorDefinition -> tags | Nullify | Tag history must not be destroyed with a color definition |
| AnimalStatusReference -> animals | Nullify | Reference-data deletion must not delete animals |
| PastureGroup -> pastures | Nullify | Deleting a group only removes grouping |
| Pasture -> animals | Nullify | Domain transaction moves residents first; this is a safety fallback |
| Pasture -> Working/Field Check references | Nullify | Historical/work records survive pasture deletion |
| Animal -> tags | Cascade | Tags are part of the animal aggregate |
| Animal -> status/movement/health/pregnancy history | Cascade | These records are animal-owned history |
| Animal -> offspring parent links | Nullify | Deleting a parent must not delete offspring |
| Animal -> Working/Field Check historical references | Nullify | Session/check history survives animal deletion |
| WorkingSession -> queue items | Cascade | Queue is session-owned |
| WorkingSession -> treatment records | Cascade | Treatment completion is session work data |
| WorkingSession -> linked health/pregnancy records | Cascade | Matches current delete-session semantics |
| WorkingSession -> active animals | Nullify | Transaction restores animal location before deletion |
| FieldCheckSession -> animal checks | Cascade | Roster/check state is session-owned |
| FieldCheckSession -> findings | Cascade | Findings are session-owned |

No relationship uses `Deny`.

## Historical snapshot policy

Live relationships answer "what is this linked to now?" Snapshots answer "what was true when this event occurred?"

Persist snapshots when the historical record must remain understandable after the linked object can be renamed or deleted.

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

## Initial local indexes

Start with conservative local indexes that match existing query patterns:

- `id` on every managed entity;
- Animal: `statusRawValue`, `birthDate`, `isArchived`;
- AnimalTag: `number`, `isActive`, `isPrimary`;
- Pasture: `sortOrder`;
- WorkingSession: `statusRawValue`, `date`;
- FieldCheckSession: `startedAt`, `completedAt`;
- FieldCheckFinding: `statusRawValue`, `recordedAt`.

Do not add model-level uniqueness constraints. Add further indexes only when actual Core Data query behavior justifies them.

## Store assignment rules

Repository/transaction code must use the selected Herd scope to select the target store.

For new records:

1. resolve the selected Herd by application UUID;
2. verify every relationship target belongs to that same Herd;
3. determine the Herd's persistent store/share;
4. insert/assign all new managed objects to that same store before save;
5. reject cross-herd/cross-store relationships as integrity errors.

Ordinary feature repositories must also scope every fetch to the selected Herd UUID. An attached private store and shared store may each contain valid records with unrelated application graphs; a fetch that does not constrain Herd ownership is an integrity bug even if IDs would usually make the result appear unambiguous.

Never default a new collaboratively scoped record to the private store merely because that store was loaded first. A participant editing an accepted herd must write into the shared store/share that owns that Herd.

## Remote import and mapping rules

CloudKit may import related records and required attributes in separate operations. Therefore:

- physical relationships remain optional;
- application-required attributes without meaningful static defaults may be physically optional;
- mappers must not invent Domain entities or required scalar values to fill incomplete imported state;
- repository reads should omit or explicitly fail invalid/incomplete aggregates rather than exposing contradictory Domain state;
- persistent-history/remote-change handling triggers application invalidation and a later read;
- imported `Animal.editorRevision` is authoritative for stale-editor detection;
- `NSManagedObjectID`, store identifiers, record-zone identifiers, and `CKRecord.ID` never enter Domain snapshots.

## Explicitly rejected SwiftData baggage

The Core Data model must **not** reproduce these current implementation artifacts:

- `Animal.tagNumber` / `Animal.tagColorID` duplicate primary-tag fields;
- `Animal.locationRawValue` when location can be derived from active working-session state;
- `Animal.statusReferenceID` alongside a real status-reference relationship;
- `Herd.schemaVersion`;
- `WorkingSession.currentQueueIndex`;
- `WorkingQueueItem.queueOrder`;
- legacy persistence naming based on "protocol" where the product now uses treatment-template terminology;
- `CollaborationRevisionRecord` and its field snapshots, participant/device IDs, tombstones, or bridge lineage;
- SwiftData public-ID repair metadata/backups;
- SwiftData/Core Data bridge entities and `Shared*Record` mirrors;
- duplicated relationship IDs unless the value is explicitly a historical snapshot.

## Behavioral contracts before the physical model

Before creating `yaHerdModel.xcdatamodeld`, establish the permanent persistence behavior contract suite described by the Core Data cutover plan. These tests define product behavior through Domain repository/transaction protocols rather than SwiftData types.

The existing SwiftData implementation may be used as the first runner for those contracts so the tests characterize intended current behavior before persistence changes. That runner is temporary; the contract definitions are permanent and later run unchanged against Core Data.

At minimum the pre-model contract milestone should lock down:

- application UUID identity and duplicate-ID failure behavior;
- selected-Herd scoping so owned and accepted Herd graphs cannot be combined by ordinary repositories;
- animal aggregate create/update/tag/revision behavior;
- movement and historical preservation behavior;
- pasture deletion transaction semantics;
- Field Check historical behavior;
- Working queue/session history, including animal sex and dam-tag snapshots after animal deletion;
- rollback/no-partial-commit semantics for important multi-record operations.

Do not postpone these behavior contracts until after Core Data repositories exist. They are the executable specification the Core Data implementation must satisfy.

## Model validation required when implemented

After the behavioral contract milestone, the Core Data foundation PR that creates `yaHerdModel.xcdatamodeld` should add focused model-level tests/validation for the production implementation, including:

- the model loads successfully;
- every durable entity has an `id` UUID attribute;
- every relationship is optional and has an inverse;
- every nonoptional attribute in `CloudData` has an explicit model default;
- UUID identity/revision attributes and other application-required values that lack meaningful static defaults follow the documented physical optionality policy;
- no entity declares a unique constraint;
- no relationship uses `Deny`;
- every herd-owned entity has a Herd relationship;
- private and shared store descriptions use the same model/configuration;
- a new private Herd graph is inserted into the private store;
- a record created for a shared Herd is assigned to the shared store;
- simultaneous private and shared Herd roots remain isolated by selected-Herd repository scope;
- accepting a shared Herd preserves the owned Herd and selects the accepted Herd deterministically;
- cross-store/cross-herd relationship attempts are rejected by persistence code;
- an animal aggregate create/update preserves UUIDs and rotates `editorRevision` correctly;
- pasture deletion preserves Movement and Field Check history as specified;
- Working queue history retains animal tag/color, sex, and dam tag/color after the live animal relationship disappears;
- model/schema validation can be run with `initializeCloudKitSchema(options: [.dryRun])` in a development/test-only path before any production schema promotion.

As Core Data repositories are implemented, point the same permanent behavior contract suite at the Core Data harness feature by feature. Do not rewrite the contracts to accommodate persistence-specific behavior.

## CloudKit schema promotion rule

Do not promote the generated CloudKit development schema to production during the cutover merely because the model initializes successfully.

Before production schema promotion:

- the model is implemented and reviewed;
- private/shared integration tests have exercised store routing and sharing;
- all required entity/attribute names are considered stable;
- obsolete bridge schema is not being reused as the new model contract;
- a dry-run schema initialization passes;
- the app has completed the SwiftData gutting and the Core Data graph is the production source of truth.

Development CloudKit schema may be reset/recreated while this app has not shipped the Core Data schema.

## Implementation sequence from this blueprint

The Core Data replacement is test-first at the persistence boundary. The model blueprint is already established, but physical model/runtime implementation begins only after the permanent behavior contracts are in place.

```text
0. permanent persistence behavior contracts + temporary SwiftData contract runner
1. reconcile this blueprint with any behavior exposed by those tests
2. yaHerdModel.xcdatamodeld + CD managed-object classes + model-structure tests
3. CoreDataPersistenceController / NSPersistentCloudKitContainer store setup
4. selected-Herd scope + Herd/reference-data repository + deterministic store routing
5. Pasture repositories + pasture deletion transaction
6. Animal repositories + aggregate transaction + tag/history mapping
7. Field Check repositories
8. Working repositories
9. Dashboard/Home read models
10. direct Core Data CKShare collaboration implementation
11. switch PersistenceAssembly to Core Data
12. delete SwiftData models/repositories/bootstrap/bridge/repair code and temporary SwiftData contract runner
13. strengthen final architecture verification and delete this cutover documentation when complete
```

Do not add a temporary SwiftData implementation of any **new production behavior** just to keep both systems symmetrical during this sequence. The only temporary SwiftData work justified by step 0 is the thin harness needed to run permanent persistence-neutral behavior contracts against the current implementation.