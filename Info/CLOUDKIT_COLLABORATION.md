# yaHerd iCloud Synchronization and Herd Collaboration

**Status:** Approved feature requirements and implementation guidance; NOT an implemented feature. Core Data model changes are permitted when required by CloudKit; custom migration logic and speculative versioning infrastructure are not requested.
**Agent assignments:** ChatGPT implements, verifies and addresses PR review findings. Codex reviews code only; do not delegate feature implementation or automated test/CI changes to Codex.
**Requested outcome:** Offline-first device synchronization plus sharing and collaboration between different Apple Accounts.
**Initial inspection baseline:** main commit 5a5b29b6f2c4588de0e1b187133a7d1ea98838cc (2026-10-25).
**Platforms:** yaHerd iOS 26+, Swift 6, SwiftUI, Core Data.
**Authority:** User-approved requirements establish intended behavior. Inspect current production code for actual implementation; the baseline and path names below are discovery aids, never an assertion that a later branch still has that structure.

Read the repository-root AGENTS.md first. This document is the single approved CloudKit feature specification, executable manual test-case plan, and Codex review guide, not a dependency matrix, implementation tracker, release status report, or permission to skip source inspection. It captures the eight original implementation workstreams; verify historical code references against latest main.

## 1. Required product behavior

A person can own one or more Herds, select a Herd, maintain its complete records offline, and synchronize those records between devices on the same Apple Account. A Herd owner can invite another Apple Account into a Herd. Authorized participants can view and edit the same Herd, including animals, tag and status reference data, pastures and pasture groups, animal movements, health/pregnancy history, field checks, treatment templates, working sessions and their related records. Participants see changes from other devices after CloudKit synchronization. A person can own some Herds and participate in others; only one Herd is active in the main application UI at any instant.

Use invitation-based sharing by default. The owner controls invitations and participant access. Native CloudKit share access must support read-only and read/write participants; the share owner manages participants and sharing. A participant can leave a shared Herd. An owner can revoke access. Do not confuse leaving, revoking, stopping sharing, and deleting a Herd. These have different data consequences.

Local work must not require a network connection. Persist successful local transactions immediately and synchronize when CloudKit can do so. The application must not promise immediate cross-device delivery, server-global transaction atomicity, or globally serialized offline edits. Show meaningful states for local save, cloud activity, account/permission problems, and recoverable conflicts. A successful local Core Data save is NOT proof of successful CloudKit export or import on another person's device.

Existing installations must retain all local data, stable UUIDs, historical records, selected Herd identity where valid, and relationships when upgrading to a CloudKit-compatible model. Never silently replace, merge, duplicate, delete, or upload a Herd to the wrong Apple Account.

### Explicit initial-scope decisions

- Sharing boundary: one entire Herd and its owned data graph. No independent animal-level or pasture-level shares.
- Persistence: Core Data with NSPersistentCloudKitContainer, using private and shared CloudKit database scopes and corresponding local stores.
- Herd ownership: the share creator/owner remains owner. Ownership transfer is not part of the initial feature.
- Permissions: native read-only/read-write share permissions; no farm-specific server-enforced roles or custom role engine.
- Herd UI: multiple accessible Herds with one selected Herd. Keep the existing feature navigation patterns.
- Settings: device-only personal UI preferences remain local unless a concrete Herd-owned setting must be shared. Herd tag colors and other modeled Herd records synchronize.
- No SwiftData return, hand-written migration system, unnecessary Core Data model-version scaffolding, dual-write conversion, custom sync server, custom CloudKit record replication engine, or unrelated architectural rewrite. Use Core Data's supported automatic lightweight migration if verified necessary to open existing user stores after a required model change.
- No automatic merge of Herds independently created on different devices. A name match does not prove shared identity.
- No automatic hard deletion or recreation of records to hide distributed conflicts.
- Do not expand the scope to cross-Herd links; Core Data relationships must remain inside the same CloudKit share/store, and user-permitted cross-Herd references require a separate design.

## 2. Core architecture and invariants

Keep the existing SwiftUI -> use case/domain repository -> Core Data repository -> persistence direction. CloudKit APIs, CKShare, NSManagedObjectID, NSPersistentStore and managed objects belong in platform/persistence adapters, not ordinary Domain or Presentation contracts. Prefer extending the current application persistence assembly, context factory, read-model actors, transaction executor, successful-mutation stream and Herd-scoped repositories. Avoid redundant write systems or another navigation framework.

An owned Herd resides in the private CloudKit-backed store. Herds shared by other owners reside in the shared CloudKit-backed store. Select the correct store for each Herd. Store ownership is not implied by the Herd UUID alone, and every read, insert, update and delete must be scoped to the selected Herd and correct persistent store. Explicitly assign new managed objects to the owning store where required. Never create a relationship that crosses stores or crosses Herd ownership boundaries. Multi-entity local transactions must remain atomic in their own target store.

The Herd root is the unit of sharing. Audit every relationship and newly created child entity for actual share membership; do not assume that all downstream records are automatically shared merely because the root is shared. Verify Apple API behavior against the current SDK before finalizing the strategy.

Keep application UUID identity stable. Core Data managed-object IDs are not domain identity and must not leak through repository interfaces. A UUID duplicate within a Herd, duplicate tag assignment, multiple active primary tags, invalid relationship, or conflicting state must be detected and addressed rather than ignored. Domain rules remain the authority for semantic validity; Core Data nullability required for CloudKit does not weaken logical domain validation.

CloudKit is eventually consistent. A Core Data write gate, actor, editor revision, and local transaction coordinator cannot coordinate or lock multiple offline devices. Distinguish local concurrency protection from cross-device conflict semantics.

## 3. Current production implementation: inspect before using

This section records verified code as of the baseline above. Re-check all paths, declarations and callers on the branch being modified.

- yaHerd/Data/Persistence/CoreData/CoreDataPersistentContainer.swift: NSPersistentContainer, one SQLite store at Application Support/yaHerd/yaHerd.sqlite, migration/inferred mapping disabled, asynchronous store load. Do not overwrite an existing database in the conversion.
- yaHerd/Data/CoreData/yaHerdModel.xcdatamodeld/yaHerdModel.xcdatamodel/contents: 18 Core Data entities; inspected XML contains nonoptional relationships, nonoptional attributes without defaults, and syncable="NO" declarations. Confirm the actual current model and validate CloudKit rules with Xcode rather than assuming XML flags alone are a definitive compatibility test.
- yaHerd/Data/Persistence/CoreData/CoreDataAppHerdBootstrapper.swift: creates "My Herd" whenever it finds none, selects when one, and fails for more than one. Import timing and shared Herds make this behavior unsuitable.
- yaHerd/App/Persistence/AppCurrentHerdSelection.swift: holds selected Herd UUID. yaHerd/App/Navigation/AppNavigationState.swift separately stores selectedHerdID for navigation restoration. Prevent divergence or stale cross-Herd navigation.
- yaHerd/Data/Persistence/CoreData/CoreDataContextFactory.swift: fresh background contexts without selected-store assignment. The corresponding CoreDataTransactionExecutor.swift handles a subset of writes.
- yaHerd/Data/Repositories/CoreData/CoreDataAnimalRepository.swift, CoreDataPastureRepository.swift, CoreDataTagColorRepository.swift and CoreDataWorkingTreatmentTemplateRepository.swift: direct context.save paths also exist. Audit ALL repository writes for store routing and authorization rather than assuming one shared transaction helper covers them.
- yaHerd/Data/Persistence/CoreData/CoreDataLookup.swift: UUID and herd relationship lookups. Adapt to store-qualified resolution and potentially incomplete remote graphs.
- yaHerd/Data/Repositories/CoreData/CoreDataReadModelActor.swift and other projections: read models often require complete relationship graphs and may dereference relationships directly. Remotely imported related records can arrive in stages.
- yaHerd/App/Mutation/ApplicationMutationCenter.swift: only a local mutation source exists. Extend existing feature invalidation for remote changes.
- yaHerd/App/Persistence/CoreDataAppPersistenceAssembly.swift and yaHerd/App/yaHerdApp.swift: existing construction, recovery and dependency wiring.
- yaHerd/Presentation/Views/Settings/SettingsView.swift: current configuration UI, including hard-delete animal behavior.
- Scripts/verify-architecture.sh: intentionally rejects CloudKit use, entitlement names and sync naming. Update narrowly when legitimate implementation requires CloudKit. Do not disable architecture checks indiscriminately.
- yaHerd.xcodeproj/project.pbxproj and yaHerd/Info.plist: no production CloudKit entitlements/share acceptance setup in baseline.

## 4. Implementation stages and completion requirements

The stages below form an implementation order, not a status matrix. ChatGPT implements production changes; Codex reviews only. Every stage: inspect latest code; trace affected callers, reads, writes, recovery and navigation; implement the smallest production change; verify with available Xcode tooling, direct inspection and relevant Section 5 manual cases; inspect final diff; request substantive Codex code review; correct genuine production defects; report runtime limitations. Implement only the requested stage and necessary prerequisites; do not roll into the next stage automatically.

### Stage 1: CloudKit-compatible Core Data model and existing-data compatibility

**Purpose:** Make only the necessary Core Data model changes for CloudKit mirroring and keep existing local databases readable without custom migration logic.

1. Inspect the current Core Data model and determine the smallest changes required for CloudKit. Update the existing model directly where supported; do not create duplicate V1/V2 model files or version-selection machinery speculatively. Keep a prior model only if actual existing-store compatibility verification demonstrates it is needed.
2. Inventory the actual entity model for all attributes, optionality, defaults, relationships, inverses, delete rules, constraints and entity configurations. CloudKit mirror compatibility is a hard constraint.
3. Make relationships optional where required by Apple's Core Data CloudKit integration. Update the generated/manual managed-object interfaces and all callers of now-optional relationships; preserve domain-level required relationship validation separately.
4. Review required attributes without defaults. Use a genuine semantic default only when valid; otherwise use optional storage plus guarded projections and validation. Do not invent dates, IDs or other business meaning.
5. Verify unique constraints, unsupported relationships/configurations, inverses, delete rules and modeled relationship graph against the current SDK. Review entity syncability metadata, but do not assume syncable="NO" alone proves a CloudKit failure.
6. Audit mapping/encoding of optional and missing imported fields in all Core Data projections, feature read models, seeders and transactions. Distinguish incomplete imports from corrupt data; never crash or silently create fabricated records.
7. Check whether the required model changes are supported by Core Data's built-in lightweight migration. The current production store explicitly disables automatic migration: change that setting only when necessary, and only for writable stores. Do not implement a custom mapping, staging, or data-migration engine without a demonstrated need. Preserve existing SQLite data, WAL/journal metadata and read-only recovery behavior; never manipulate SQLite files independently while Core Data owns them.
8. Verify real pre-update SQLite stores open successfully under the revised model with stable UUIDs, unchanged record counts and preserved history/relationships, including archived animals, tags, parentage, pasture groups, movements, treatments, field checks and working sessions. If automatic compatibility fails, investigate the exact model mismatch before adding new logic.
9. Validate model compatibility using current Xcode/Apple APIs and development CloudKit schema tooling. Never initialize or mutate production schema from normal startup.
10. Document only actual compatibility limitations in implementation output; no new status artifacts are required.

**Accept when:** Real existing databases open with unchanged UUIDs and preserved data/history, valid local writes still work, and the updated model passes development CloudKit compatibility validation. No custom migration implementation is introduced without demonstrated necessity. A successful build alone is insufficient.

**Review focus:** Data loss, required-versus-optional attribute/relationship semantics, existing-store opening failures, optionality crashes, destructive delete-rule changes, unsupported CloudKit schema evolution.

### Stage 2: Private and shared persistent stores and all-path routing

**Purpose:** One CloudKit-enabled Core Data persistence boundary that can read owned and shared Herds safely.

1. Configure iCloud/CloudKit capability, a stable CloudKit container identifier, correct development-team signing, Push Notifications and Remote notifications background mode as required by the actual target and SDK. Include all necessary debug/release entitlements and Info.plist settings.
2. Implement NSPersistentCloudKitContainer inside the existing persistence wrapper; use separate, stable SQLite URLs and NSPersistentCloudKitContainerOptions database scopes .private and .shared. Preserve in-memory/read-only recovery paths without exporting recovery data.
3. Enable persistent history tracking and store remote-change notifications for both stores. Distinguish local store-load failures from temporary CloudKit communication errors.
4. Retain the existing local database and application identities when adopting it as the owned/private store, using Core Data-supported persistent-store configuration. Do not write a data-copy or migration pipeline unless an actual store-layout requirement demands one. Never mirror one physical store into both private and shared scopes or blindly duplicate records.
5. Expose a focused internal store resolver and store-qualified context behavior. Selected Herd -> owning persistent store must be authoritative and stable for each transaction.
6. Restrict Herd-specific reads using NSFetchRequest.affectedStores or equivalent supported store scoping. Ensure unknown Herd IDs, duplicate IDs and cross-Herd references fail safely.
7. Assign newly inserted managed objects to the correct store. Preserve a single-store atomic commit for multi-entity operations.
8. Audit every save path, including synchronous animal, pasture, tag color, template, Herd, field check and working repositories, and asynchronous transaction executor. Apply consistent destination-store and error/rollback behavior without unnecessary duplicated abstractions.
9. Validate that read actors, background contexts, seeders and recovery code do not accidentally read/write the wrong store. Retain concurrency isolation guarantees and existing app performance characteristics.

**Accept when:** Both stores load correctly; existing owned records stay in the private store; selected shared records read/write through the shared store; no cross-store insert or cross-Herd lookup succeeds; recovery cannot upload synthetic data.

**Review focus:** Silent wrong-store writes, duplicate local records, context isolation, adoption of the existing store, partial store-load failures, complete audit of direct saves.

### Stage 3: Multi-Herd lifecycle, selection and navigation

**Purpose:** A user can own multiple Herds and participate in others without a single-Herd startup assumption.

1. Replace CoreDataAppHerdBootstrapper's zero/one/many implicit policy with explicit available-Herd discovery across private and shared stores. Initial CloudKit import may not be complete when the local query is empty.
2. Provide explicit Create Herd and Join Herd flows; do not create a second "My Herd" automatically on every new device. Support deliberate offline Herd creation without confusing that creation with an empty iCloud database.
3. Introduce minimal domain-facing Herd list/selection capabilities including stable application UUID, display name, owner/participant category and effective access where available.
4. Make AppCurrentHerdSelection the authoritative application selection and coordinate it with AppNavigationState.selectedHerdID. Restore only selections still accessible; preserve coherent state if a read temporarily fails.
5. Ensure async loads capture their originating Herd selection; results from Herd A must not be shown after switching to Herd B. Clear/revalidate navigation stacks, selected records, filters, active workflows and drafts as appropriate.
6. Update CoreDataLookup, repositories and actors so Herd ID plus owning store identify each query. Never resolve the first equal ID from the wrong store.
7. Detect newly imported/shared Herd roots and update the Herd list without restart. Distinguish "waiting for import" from truly empty data, removal of share, lost account authorization and local-store corruption.
8. Handle selected-Herd removal or sharing revocation through navigational revalidation and accessible fallback state rather than an unrecoverable startup failure.

**Accept when:** Several owned and shared Herds can coexist; switching keeps all records and routes scoped; a new signed-in device does not create unwanted roots; revoked/missing selection does not leak old records.

**Review focus:** Selection coherence, UUID collisions, stale async results, restored routes, cloud-import races, transient errors.

### Stage 4: Remote history, invalidation and cloud status

**Purpose:** Imported changes reach existing UI and application state correctly.

1. Observe NSPersistentStoreRemoteChange and CloudKit container event notifications for setup, import and export activity. Track the relevant store identity.
2. Implement persistent-history consumption on background contexts with a separate durable token for each store. Skip or coalesce locally authored transactions without missing genuine remote updates.
3. Consume, classify and publish remote changes through ApplicationMutationCenter; extend ApplicationMutationSource rather than introducing independent feature-specific notification systems.
4. Invalidate the proper home/dashboard/animals/pastures/field-check/working views, Herd inventory, selected-record details and navigation targets. Fall back to broad invalidation if event-to-feature mapping is uncertain.
5. Advance history tokens only after successful processing; handle invalid history tokens, deletion/reset of stores, foreground return and repeated notifications safely. Do not purge Core Data history in a way that disrupts CloudKit exports.
6. Account for share metadata changes separately from normal Core Data history; refresh invitation/ownership/permission state as needed.
7. Report local-save success separately from cloud-event progress. Do not promise "fully synced on all devices" from a successful export event.
8. Log actionable errors without exposing personal Apple Account identifiers, share URLs, medical notes or detailed private record contents.

**Accept when:** A remote create/update/delete becomes visible in already-open relevant screens without restart; navigation survives remote removal safely; checkpoints and retries do not drop changes or emit endless duplicate updates.

**Review focus:** Token corruption, incorrect author filtering, missed events, refresh loops, stale query generations, inaccurate status labels, privacy.

### Stage 5: Create, accept and manage complete Herd shares

**Purpose:** Owner and invited participant can actually collaborate across different Apple Accounts.

1. Establish the selected Herd's true owning private store and share state. Query an existing share before attempting to create one; share creation and repeated presentation must be idempotent.
2. Use NSPersistentCloudKitContainer's sharing APIs to create a CKShare for the intended Herd root and associate all required Herd-owned related entities. Verify the actual membership and share-zone placement of entities including children created after the original share.
3. Set owner-approved invitation visibility and supported permissions. Default away from public/unrestricted URL access; prefer invitation-only sharing.
4. Integrate Apple's native sharing UI (UICloudSharingController or a current supported SwiftUI bridge) with accessible Share/Manage Sharing actions.
5. Set CKSharingSupported and implement supported scene-delegate acceptance callbacks, including cold-start connection options, while preserving current SwiftUI app initialization. Do not accept against an uninitialized or incorrect store.
6. Accept incoming CKShare.Metadata using acceptShareInvitations(from:into:completion:) on the intended shared persistent store. Handle repeat/expired/revoked invitations and network errors without duplicating Herds.
7. Treat invitation acceptance and eventual record import as distinct steps; show loading/available state until the shared Herd root is actually present.
8. Implement owner participant-management operations and participant leave-sharing actions using Apple's approved APIs, including share persistence when a direct CKShare update needs it.
9. Distinguish revoke participant, leave share, stop sharing and delete Herd in service logic, confirmations and recovery. Use destructive purge APIs only when that action's full consequences are intended.
10. Verify that sharing does not create cross-store relationships or leave descendants outside the share unexpectedly.

**Accept when:** Two physical devices using different Apple Accounts can share a populated Herd, exchange new and edited records, revoke/leave correctly, and relaunch or reaccept without duplication.

**Review focus:** Share root, accidental public access, incomplete graph membership, scene cold launch, duplicate share creation, unintentional data deletion, owner vs participant capabilities.

### Stage 6: Read/write permissions in all code paths

**Purpose:** Permission enforcement exists at persistence/transaction boundaries and in the UI.

1. Expose a persistence-neutral capability/authorization interface for the selected Herd. Resolve owner/participant role and record update/delete capabilities with appropriate CloudKit-backed APIs; account for temporary unknown/unavailable state.
2. Enforce authorization at every mutation boundary, including direct repository saves and bulk actions, not only toolbar visibility.
3. Disable/limit inline editing, context menus, swipe actions, add/edit/delete dialogs, animal move/archive/restore, field checks, health entries, working session completion, tag-color changes and other writes for read-only participants.
4. Revalidate permission before commit. Avoid trusting an editor-open-time permission when revocation may have occurred.
5. Maintain local recovery-mode write restrictions independently of Herd sharing authorization.
6. Handle offline participants and permissions that cannot currently be refreshed honestly. CloudKit remains server-authoritative; never claim guaranteed immediate enforcement of a just-revoked remote permission while a device is offline.
7. Preserve unsaved user input where feasible when access changes; offer specific non-destructive feedback.

**Accept when:** Owner and read/write participant can perform allowed operations; viewer cannot write via ANY primary or alternate app path; revoked users cannot successfully upload new authorized changes after server revocation; UI states are accurate.

**Review focus:** Hidden mutations, stale authorization, misleading offline guarantees, security/privacy leakage, save-vs-cloud-permission errors.

### Stage 7: Remote integrity and conflict recovery

**Purpose:** Distributed edits preserve domain invariants and expose irreconcilable outcomes.

1. Inventory the existing local invariants and optimistic revisions for animal aggregates, tags, status references, pasture membership, pasture-group ordering, template naming, field-check sessions and working-session transitions.
2. Keep local transaction boundaries and revision checks; propagate observed remote revisions into stale-editor handling.
3. Add integrity inspection after relevant remote imports, allowing for temporarily incomplete relationship graphs. A missing parent during import is not automatically evidence of irreparable corruption.
4. Detect duplicate logical identities/tag assignments, conflicting primary-tag state, invalid foreign-Herd or cross-store relationships, invalid working/field-check transitions and delete-vs-edit races.
5. Preserve conflicting records when feasible. Do not invent replacement UUIDs, select arbitrary record winners, or silently re-create a remotely deleted business entity.
6. Implement only the necessary domain-specific reconciliation or user-resolvable conflict presentation. Avoid repeated automatic repair writes that create endless sync loops.
7. Treat app-local actor gates and Core Data transactions as local-only guarantees. For highly concurrent shared workflows, explicitly define whether eventual consistency with conflict recovery is sufficient; do not claim CloudKit provides globally atomic offline operations.
8. Review hard-delete behavior and data-retention impact carefully in a multi-user environment.

**Accept when:** Independent offline edits converge; same-record edits and destructive races have documented/recoverable behavior; critical tag, Herd and session invariants are not silently violated.

**Review focus:** Semantic data loss, hidden last-writer effects, infinite repair loops, missing relationship dereferences, false guarantees of distributed atomicity.

### Stage 8: UX, account lifecycle, production deployment and real-device verification

**Purpose:** Usable and supportable sharing, safe account transitions, and a verified production CloudKit configuration.

1. Add a native Herd picker, Create/Join affordances, Share/Manage Sharing controls, participant detail/leave controls, permission indications and navigation consistent with current iOS 26 design. Keep the feature accessible from existing Settings and Herd entry points.
2. Surface meaningful iCloud availability/activity/error information. Distinguish local persistence, upload activity, pending import and permission errors. Do not label a Herd completely synchronized just because one device exported a transaction.
3. Handle iCloud sign-out, account switch, unavailable account, share revocation, restored device and reinstall without exposing previous account content or uploading it under a different account. Inspect Apple's actual persistent-store/account behavior and choose an explicit safe protection strategy rather than assuming a store is automatically cleared.
4. Preserve current read-only recovery and useful diagnostic export without unintentionally exporting private shared records or silently replacing the working database.
5. Initialize and inspect the CloudKit DEVELOPMENT schema only with intentional developer workflows. Review schema implications before deployment; never perform schema initialization on normal production launch.
6. Deploy verified schema to CloudKit PRODUCTION and validate TestFlight against production behavior. Plan schema evolution carefully because existing production fields/types cannot be casually removed.
7. Execute the detailed Section 5 manual test cases across two different Apple Accounts and, if available, a second device on the owner's Account. Exercise offline work, cold-launch invitation acceptance, read-only access, revocation, multiple Herds, concurrent edits, pending import, local migration, account change, deletion, relaunch and interrupted sync.
8. Inspect production logs/status for persistent errors, stalled export/import, unnecessary refresh and crashes. Describe unverified cases as limitations rather than declaring coverage.
9. Perform the final security and user-data audit before production release.

**Accept when:** The feature works across real distinct Apple Accounts, upgraded data is preserved, data does not cross account/Herd boundaries, production schema is deployed safely, and observed behavior matches requirements. Compilation alone is insufficient.

## 5. Executable manual test-case plan

This is a behavior and release verification plan for ChatGPT to follow during implementation. Focused automated test creation and maintenance follow AGENTS.md; do not create separate tracking files, unnecessary testing infrastructure or unrelated CI changes. Codex reviews code and evidence, not implementation. Never mark a case passed without actually executing it.

### 5.1 Test environment, fixtures, and evidence

- **Physical devices:** A = an owner's iPhone signed into Apple Account A; A2 = another device on Account A for same-account sync (recommended); B = iPhone on different Apple Account B with read/write access; C = third Apple Account with read-only access where available. Two physical devices on different accounts are the minimum for real cross-account sharing verification; if A2 or C is unavailable, explicitly mark dependent coverage as not executed rather than asserting it.
- **Cloud environments:** Use an intentionally initialized/inspected CloudKit **development** schema for engineering scenarios. Use a separately deployed CloudKit **production** schema and TestFlight build for final acceptance. Never initialize production schema from normal app startup.
- **Existing-data fixture:** Preserve a genuine local-only build's SQLite/Core Data store and a separate restorable copy. Capture Herd IDs, per-entity counts and representative stable UUIDs, active/archived state, parentage, tag/status colors, pastures/groups, movement/health/pregnancy history, field checks and findings, treatment templates, working sessions and child records. The baseline model contains 18 entities; inspect current main and cover every entity that actually exists when testing. Preserve negative/empty cases separately.
- **Multiple-Herd fixture:** Include two owned Herds and at least one Herd shared by another Account. Give them distinct, recognizable content so wrong-Herd reads are evident.
- **Recording actual results:** In the implementing PR report, record case IDs, device and OS/build, CloudKit environment, prerequisite state, actions performed, expected vs observed outcome, and privacy-safe diagnostics. Use "passed", "failed", "blocked", or "not executed" with reasons. Do not create a separate test tracker. Never disclose personal Apple Account identifiers, sensitive Herd records or live invitation URLs in logs.
- **Cloud timing:** Wait for actual propagation/import and compare data, not an invented immediate timeout. CloudKit event success on one device alone does not prove another device received records. A prolonged stall needs a diagnosis, not an unsupported "synced" assertion.
- **Failure injection:** Use safe development fixtures, network toggles, app termination, supported Xcode/CloudKit tooling and restorable stores. If an import-order, quota or server failure cannot be induced safely, mark the relevant subcase not executed; do not claim simulation occurred.

### 5.2 Existing-store compatibility, schema and store isolation (Stages 1–2)

**M01 — Existing populated store upgrade.** Setup: Install the prior local-only build with the representative data fixture. Steps: record counts/UUIDs and relationship/history samples; preserve a restorable original; install the new build; inspect all major features. **Pass:** No missing/duplicated data or changed application IDs, and previous CRUD behavior remains correct.

**M02 — Empty upgrade and clean installation.** Setup: One originally empty local store and one fresh device. Steps: upgrade/launch while iCloud is present and absent. **Pass:** No accidental duplicate starter Herd, synthetic recovery upload, corrupt empty store or false "cloud empty" conclusion before import finishes.

**M03 — Existing-store compatibility failure/retry.** Setup: Safe backed-up fixture and a controllable store-load/migration failure. Steps: interrupt or fail migration using supported development means and relaunch. **Pass:** Original data remains recoverable; no silent reset, duplicate roots, partial destructive conversion or forced upload. If not inducible, state limitation.

**M04 — Model and development schema compatibility.** Setup: Updated Core Data model and existing-store fixture in development environment. Steps: run current SDK CloudKit model/schema validation, inspect attributes, relationships, inverses and constraints; intentionally initialize the development schema only. **Pass:** Compatible model, guarded optional imported values, unchanged production schema.

**M05 — Owned/shared routing and isolation.** Setup: A owns private Herd P; B has shared Herd S. Steps: read, create, edit and delete representative records in each selected Herd; inspect their Core Data store memberships. **Pass:** Reads/writes use their true owning store and share; no cross-store relationships, foreign-Herd mutations or accidental duplication.

**M06 — Per-store failure and recovery.** Setup: Separate private/shared stores. Steps: induce a supported shared-store load/permission problem while observing the private store and recovery mode. **Pass:** Specific error is surfaced, unaffected data remains safe, and fallback/in-memory data is never uploaded as genuine Herd data.

### 5.3 Herd selection and synchronization (Stages 2–4)

**H01 — Initial cloud discovery without duplicate bootstrap.** Setup: A already owns Herd P in iCloud; A2 has no local store. Steps: launch A2 before and after import completes. **Pass:** P is discovered with its original UUID; no automatic second "My Herd" root.

**H02 — Deliberate offline Herd creation.** Setup: Device offline with no selected Herd. Steps: explicitly create a Herd and animal, relaunch offline, reconnect. **Pass:** Exactly one new user-requested Herd persists and eventually exports with stable IDs.

**H03 — Multi-Herd switch and stale navigation.** Setup: Owned and shared Herds with unrelated records. Steps: open animal/pasture details, active workflow, filter and editor in Herd P; switch to Herd S before a delayed fetch completes; restart. **Pass:** No stale cross-Herd data, filters, drafts, routes or saves; coherent selected-Herd restoration.

**H04 — Same-Apple-Account private synchronization.** Setup: A and A2 on Account A. Steps: create/edit one of each entity/relationship class in the private Herd; observe import on A2; make a reverse edit. **Pass:** Bidirectional convergence of records, IDs, relationships and history without duplicates. Without A2, mark unverified.

**H05 — Open-view remote invalidation.** Setup: A and B displaying an already-shared Herd. Steps: edit animal, pasture, health record, field check and working data on one device while other views, counts and Dashboard are visible. **Pass:** Relevant screens update without force relaunch, and deleted details/routes safely revalidate.

**H06 — Durable remote history after relaunch.** Setup: B terminates app after initial import. Steps: A edits several feature areas; B reopens. **Pass:** Pending changes processed once or safely coalesced, history tokens remain valid or recover, and no permanent stale cache or infinite refresh loop.

**H07 — Network loss and export retry.** Setup: A/B authorized editors. Steps: take B offline, make local updates, terminate/restart still offline, reconnect and compare both devices. **Pass:** Local saves survive, eventually converge, no duplicate exports or "fully synced" status based only on local commit.

**H08 — Incomplete remote graph.** Setup: Populated share with animals, parents, pasture, field checks and working children. Steps: import while connectivity is constrained or use safe development instrumentation for partial arrival where possible. **Pass:** No required-relationship crashes, invented identity, false permanent corruption or permanently dropped child; graph displays coherently when complete.

### 5.4 Share creation, invitations and access (Stages 5–6)

**S01 — Share a populated Herd across accounts.** Setup: A owns a full Herd; B is a different Apple Account. Steps: create invitation, accept on B, inspect every modeled descendant type. **Pass:** Only the intended Herd and its complete child graph arrive in B's shared store with stable UUIDs.

**S02 — Warm invitation acceptance.** Setup: yaHerd open on B. Steps: accept an invitation from iOS. **Pass:** Scene callback processes once, no duplicate Herd and correct pending-import/available states.

**S03 — Cold-launch invitation acceptance.** Setup: yaHerd fully terminated on B. Steps: open invitation and launch app. **Pass:** Pending invitation waits for store initialization, is accepted once, and eventually yields a navigable shared Herd.

**S04 — Repeat, invalid and revoked invitations.** Setup: Previously accepted share and separate expired/revoked invitation fixture. Steps: retry acceptance and invalid link. **Pass:** No second root/share, no unauthorized record disclosure, meaningful errors, no loss of unrelated data.

**S05 — New records added after sharing.** Setup: A/B already share Herd. Steps: Add animal and tag, pasture/group, health/pregnancy/movement history, field-check children and working-session/treatment children from either authorized device. **Pass:** New descendants join the correct share and appear on other account; no manual re-sharing required.

**S06 — Bidirectional read/write collaboration.** Setup: B invited as editor. Steps: B edits pasture/moves animal; A records treatment/field check; B modifies working session. **Pass:** Changes are locally atomic, use appropriate stores and converge with correct relationships/history.

**S07 — Read-only access through every editing path.** Setup: B or C as read-only participant. Steps: Attempt inline/full editing, swipe/context-menu archive/delete/restore, bulk edits, tags, pastures, animal movements, health additions, field checks, templates and working-session actions. **Pass:** UI does not offer unauthorized actions, and repository commit paths reject bypasses; reads still work.

**S08 — Permission downgrade with open editor.** Setup: B editing while A changes B from writer to viewer. Steps: B attempts save after permission update and after reconnection if offline. **Pass:** Server-rejected/unauthorized writes do not become authorized cloud state, app preserves a recoverable draft where feasible, and messaging acknowledges offline revocation timing.

**S09 — Revoke, leave and stop sharing separately.** Setup: Owned Herd shared with B; additional safe fixture Herd. Steps: A revokes B, B leaves different share, A stops another share. **Pass:** Distinct intended consequences, proper selection fallback, owner data and unrelated Herds not deleted.

**S10 — Invitation-only privacy.** Setup: Active shared Herd with native CKShare. Steps: Examine access settings; try opening an invitation as an uninvited Apple Account. **Pass:** Public access is not accidentally enabled; uninvited users cannot access unrelated Herd content.

### 5.5 Concurrent editing, integrity and deletion (Stages 6–7)

**C01 — Independent offline edits.** Setup: A/B sharing and offline. Steps: Change different animals/records, reconnect in each order across repeat runs. **Pass:** Both independent valid changes survive after convergence.

**C02 — Same-animal concurrent edits.** Setup: Same animal open on both offline devices. Steps: Change overlapping fields, reconnect in alternate orders. **Pass:** Result matches an explicit implemented conflict policy; report when a remote overwrite cannot be preserved, rather than claiming app-local revisions guarantee cloud serializability.

**C03 — Duplicate tag/primary-tag race.** Setup: A/B offline. Steps: Assign same tag or incompatible active primary tags concurrently, reconnect. **Pass:** Detect and expose recoverable invariant conflict; no invented UUID or endless repair-write loop.

**C04 — Animal move versus pasture deletion.** Setup: Both devices have animal assigned to pasture P. Steps: A moves animal while offline B removes/archives P; reconnect. **Pass:** Domain-valid membership and history or explicit conflict state; no silent loss/cross-Herd relationship.

**C05 — Competing session transitions.** Setup: Both devices viewing same working/field-check session offline. Steps: Make conflicting completion/cancel/edit changes, reconnect. **Pass:** No silently invalid session state or duplicate completion; conflict recovery follows domain rules.

**C06 — Delete versus edit/open navigation.** Setup: A has animal editor open. Steps: B deletes that animal while A has unsaved edits; synchronize. **Pass:** No silent resurrection, crash, invalid route or unintended data loss; editor presents appropriate conflict/removal outcome.

**C07 — Cross-Herd ownership safety.** Setup: At least two accessible Herds, potentially similar record identifiers in development fixture. Steps: attempt parent/pasture/child relationship or mutation against wrong Herd/store. **Pass:** Correct lookup and transaction rejection, no data leakage or foreign-store links.

**C08 — Reconciliation convergence.** Setup: Development fixture with remotely induced domain conflict. Steps: reconnect devices and observe history and repair activity. **Pass:** Bounded repair/user-actionable state, not indefinite automatic alternating writes.

### 5.6 Account failures and release acceptance (Stages 7–8)

**R01 — Apple Account transition.** Setup: A has private and joined shared Herd data. Steps: sign out of iCloud, sign into a different Apple Account and relaunch. **Pass:** Previous account's data is not disclosed or exported to new account; safe local access/recovery policy is observed.

**R02 — iCloud unavailable and CloudKit service errors.** Setup: Restorable owned/shared fixture. Steps: Disable iCloud/network; safely induce quota, denied permission, or service failure where controllable. **Pass:** Preserved local data, accurate actionable errors, no silent empty-store replacement; unavailable fault cases listed as not executed.

**R03 — Interrupted share import/export.** Setup: Large populated share invitation. Steps: terminate app or disconnect mid-transfer, then reconnect. **Pass:** Resume without duplicate Herd/share/child objects or permanently incomplete relationships.

**R04 — Archive versus permanent deletion and sharing removal.** Setup: Herd with archived animals and history. Steps: Separately exercise archive, hard delete, participant leave, revoke and owner stop-sharing on safe fixtures. **Pass:** Only intended effects, correct historical retention/relationships, no unintended purge.

**R05 — TestFlight production schema.** Setup: Development schema reviewed, production CloudKit schema intentionally deployed, TestFlight on distinct accounts. Steps: Repeat S01, S03, S06, S07, H04 (if A2 available), and C01. **Pass:** Same end-to-end behavior on production CloudKit; no reliance on development-only entitlement/schema.

**R06 — Load and app regressions.** Setup: Representative busy multi-Herd dataset with animals, pastures and sessions. Steps: Use Home, Dashboard, animal/pasture lists, filters, field checks, working and editors while cloud events arrive. **Pass:** No significant new UI freezes, incorrect counts, repeated fetch storms, crashes or lost local functionality. Record measured limits if the environment supports them; invent no numerical benchmark.

### 5.7 Completion gates

- **Stage 1:** M01–M04. Existing-data preservation and actual model compatibility validation are mandatory; custom migration code is not a default requirement.
- **Stage 2:** M05–M06 and related existing-store adoption/fresh creation coverage. Wrong-store writes block progression.
- **Stage 3:** H01–H03 and C07. Duplicate roots and cross-Herd data exposure block progression.
- **Stage 4:** H04–H08. Real remote import/refresh behavior must be demonstrated when physical devices are available; simulated events cannot substitute.
- **Stage 5:** S01–S06, S09–S10 and R03. Different-Apple-Account sharing and complete graph inclusion are mandatory for acceptance.
- **Stage 6:** S07–S08 and R01. Unauthorized writes and account-data leakage are release blockers.
- **Stage 7:** C01–C08 and R04. Silent critical invariant corruption or destructive loss is a release blocker.
- **Stage 8/release:** All applicable cases including R01–R06, production schema and TestFlight. Unexecuted device tests mean **not release verified**, not passed.

Immediate release blockers include data loss, wrong-account upload, foreign-Herd/store access, unintended hard deletion, duplicate Herd/share creation, unauthorized committed edits, silently corrupted domain-critical invariants and invalid production CloudKit schema. Other findings are prioritized by actual production consequences. When a scenario cannot be safely reproduced, report that limitation instead of treating a successful build as behavioral verification.

## 6. Pull-request implementation rules

ChatGPT is the implementing agent and produces PR changes; Codex serves only as PR code reviewer. Use focused implementation stages as PR boundaries; a phase and its demonstrably necessary dependencies may be combined when they cannot function independently. Start each stage against latest merged main and inspect current code first. Do not assume an earlier stage was completed just because this document describes it.

Before submitting each PR:
1. Identify the intended behavior and exact affected production call paths.
2. Explain the root cause or missing behavior that required changes.
3. Audit reads, writes, related workflows, errors, rollback, recovery, remote changes and navigation.
4. Use Xcode build/direct source inspection; run the applicable Section 5 manual test cases when equipment and accounts permit, and report cases not executed.
5. Inspect the final diff for scope, dead/duplicate logic, unintended changes and restored removed infrastructure.
6. Request Codex code review against AGENTS.md and the applicable feature stage. ChatGPT fixes actual production defects.
7. Report modified paths, evidence of verification, known gaps and unresolved risks. Add or maintain focused tests under AGENTS.md; do not change unrelated tests or CI infrastructure.

Required changes to Scripts/verify-architecture.sh must be narrowly justified by approved CloudKit implementation. Keep its other architectural restrictions intact; do not rewrite automation or CI to create a false passing signal.

## 7. ChatGPT implementation instructions (Codex is review-only)

ChatGPT, not Codex, implements production changes, performs available verification, creates PRs and fixes review findings. When asked to implement a stage:

- Read root AGENTS.md and this feature specification, then read the latest actual source and relevant Apple API documentation.
- Treat this document as approved intended product behavior, not a claim about current implementation or an instruction to preserve incorrect assumptions.
- Perform only the user-requested stage and required dependent work. Preserve existing names/contracts whenever feasible; avoid duplicate abstractions or custom synchronization engines.
- Address both normal and failure paths, including an absent account, sharing permission, imported graph incompleteness, wrong-store routing, stale navigation, user-data preservation and destructive operations where relevant.
- Execute applicable Section 5 manual cases when the environment permits and clearly report unexecuted cases. Add focused tests for new behavior under AGENTS.md; do not invent passing verification results, restore discarded code or author unrelated process artifacts.
- Create a focused PR when requested, inspect comments, fix actual defects and report limitations. Do not merge contrary to user direction.

Example request to ChatGPT (not Codex):

"Implement Stage 2 in Info/CLOUDKIT_COLLABORATION.md. Follow AGENTS.md. Inspect current code and relevant tests first. Add focused tests for new behavior, make only necessary production changes, verify available builds and execution paths, review the final diff, and open a PR. Do not add unrelated documentation or infrastructure."

## 8. Codex code-review agent instructions (review only)

Codex reviews code only. Do not implement a feature stage, modify production code, open an implementation PR, create automated tests or modify CI. Report findings to ChatGPT for production corrections. Review the actual PR diff and production execution paths against the requested stage and all affected feature-wide safety invariants. Do not review only this document, invent missing code based on an old plan, or assume tests have been run.

Check specifically:
- Migration and backup/recovery preserve application data and stable UUIDs.
- Every relevant read and write correctly resolves Herd and owning store, including background and direct synchronous saves.
- The share root and all intended child records are included; invitations and participants follow actual native CloudKit lifecycle and permissions.
- There are no cross-Herd/cross-store links, duplicate roots or silently omitted child records.
- Read-only restrictions are enforced at commit paths; revocation and account switches do not expose/upload unauthorized data.
- Remote changes update the mutation stream, feature lists, details, navigation and active workflows; history tokens and retries are safe.
- Partial import does not crash strict projections or masquerade as permanent data corruption.
- Concurrent offline editing cannot silently violate critical domain rules; conflict recovery avoids invented identities and infinite writes.
- Deletion, sharing removal and persistent-store recovery are non-destructive except when user intent explicitly authorizes the consequences.
- Existing unrelated functionality continues to behave as expected and the diff contains no unjustified complexity.

For each confirmed issue give severity, file/line, trigger, expected vs actual behavior, production impact, root cause and minimal corrective change. Severity must reflect tangible risk, not the absence of tests or documents. Identify all materially affected sibling paths in the same review. Avoid serial nitpicking or unlimited re-review cycles. An empty findings review is acceptable.

Conclude with implementation-stage satisfaction, concrete verified defects, build/runtime actions actually executed, Section 5 manual cases demonstrated or not executed, unverified real-device requirements and merge readiness. Never equate successful compilation with verified cross-account collaboration.

## 9. Release gates and reference resources

Do NOT claim production completion until:
- Existing stores open safely after required Core Data model changes; UUIDs and historical relationships remain intact without unnecessary custom migration code.
- Private/shared store placement and all production read/write paths have been audited.
- Multi-Herd selection, invitations, owner/editor/viewer permissions and revocation work.
- Remote changes are visible without relaunch and navigation remains correctly scoped.
- Offline conflicts, partial imports and destructive workflows have explainable/recoverable outcomes.
- Apple Account changes preserve privacy and prohibit unintended cross-account upload.
- The production CloudKit schema is deliberately deployed and real distinct-Apple-Account sharing works using the shipping app configuration.
- The final implementation has been reviewed against actual code, not the expected diagram or successful build alone.

Apple API references to check against the SDK in use:
- https://developer.apple.com/documentation/coredata/mirroring-a-core-data-store-with-cloudkit
- https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit
- https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
- https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer
- https://developer.apple.com/documentation/cloudkit/ckshare
- https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes

These references explain framework behavior; they do not override the current SDK, existing production implementation, or user requirements.
