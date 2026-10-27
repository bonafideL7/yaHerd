# yaHerd iCloud Synchronization and Herd Collaboration

**Status:** Approved product requirements; **proposed architecture revision for review** to honor the later requirement of no Core Data schema versions or data migration. Synchronization is NOT implemented.
**Agent assignments:** ChatGPT implements, verifies and addresses PR review findings. Codex reviews code only; do not delegate feature implementation or automated test/CI changes to Codex.
**Requested outcome:** Offline-first device synchronization plus sharing and collaboration between different Apple Accounts.
**Inspection:** Core Data local-only implementation as restored by PR #255; inspect the latest main branch rather than assuming historical file state.
**Platforms:** yaHerd iOS 26+, Swift 6, SwiftUI, Core Data.
**Authority:** User-approved requirements establish intended behavior. Inspect current production code for actual implementation; the baseline and path names below are discovery aids, never an assertion that a later branch still has that structure.

Read the repository-root AGENTS.md first. This document is the single approved CloudKit feature specification, executable manual test-case plan, and Codex review guide, not a dependency matrix, implementation tracker, release status report, or permission to skip source inspection. It captures the eight original implementation workstreams; verify historical code references against latest main.

## 1. Required product behavior

A person can own one or more Herds, select a Herd, maintain its complete records offline, and synchronize those records between devices on the same Apple Account. A Herd owner can invite another Apple Account into a Herd. Authorized participants can view and edit the same Herd, including animals, tag and status reference data, pastures and pasture groups, animal movements, health/pregnancy history, field checks, treatment templates, working sessions and their related records. Participants see changes from other devices after CloudKit synchronization. A person can own some Herds and participate in others; only one Herd is active in the main application UI at any instant.

Use invitation-based sharing by default. The owner controls invitations and participant access. Native CloudKit share access must support read-only and read/write participants; the share owner manages participants and sharing. A participant can leave a shared Herd. An owner can revoke access. Do not confuse leaving, revoking, stopping sharing, and deleting a Herd. These have different data consequences.

Local work must not require a network connection. Persist successful local transactions immediately and synchronize when CloudKit can do so. The application must not promise immediate cross-device delivery, server-global transaction atomicity, or globally serialized offline edits. Show meaningful states for local save, cloud activity, account/permission problems, and recoverable conflicts. A successful local Core Data save is NOT proof of successful CloudKit export or import on another person's device.

Existing installations must retain all local data, stable UUIDs, historical records, selected Herd identity where valid, and relationships when synchronization is enabled. Do not change or version the Core Data model or migrate the existing SQLite store. Never silently replace, merge, duplicate, delete, or upload a Herd to the wrong Apple Account.

### Explicit initial-scope decisions

- Sharing boundary: one entire Herd and its owned data graph. No independent animal-level or pasture-level shares.
- Persistence: Keep the existing Core Data `NSPersistentContainer`, model, and SQLite data intact. **Proposed implementation:** `CKSyncEngine` for CloudKit private and shared databases, with a focused adapter mapping existing Core Data domain records to CloudKit records. The proposal needs approval before production implementation.
- Herd ownership: the share creator/owner remains owner. Ownership transfer is not part of the initial feature.
- Permissions: native read-only/read-write share permissions; no farm-specific server-enforced roles or custom role engine.
- Herd UI: multiple accessible Herds with one selected Herd. Keep the existing feature navigation patterns.
- Settings: device-only personal UI preferences remain local unless a concrete Herd-owned setting must be shared. Herd tag colors and other modeled Herd records synchronize.
- No SwiftData return, Core Data schema/version migration, destructive store conversion, custom server, second application data model or unrelated architectural rewrite. A bounded CloudKit record adapter is unavoidable with `CKSyncEngine`; reuse the current repositories for business rules rather than implementing duplicate domain logic.
- No automatic merge of Herds independently created on different devices. A name match does not prove shared identity.
- No automatic hard deletion or recreation of records to hide distributed conflicts.
- Do not expand the scope to cross-Herd links. CloudKit records must be confined to the intended Herd's record zone/share, and Core Data relationships must remain inside the owning Herd; cross-Herd references require a separate product decision.

## 2. Core architecture and invariants

Keep the existing SwiftUI -> use case/domain repository -> Core Data repository -> persistence direction. CloudKit APIs, CKShare, CKRecord, CKRecordZone and managed objects belong in platform/persistence adapters, not Domain or Presentation contracts. Keep Core Data as the sole local source of truth; do not create a second persistence representation of application records. Extend the existing application assembly, repositories, mutation stream and Herd selection only where the actual sync path requires it.

Keep the existing local Core Data store and its local transaction semantics. For proposed explicit synchronization, each owned Herd maps to an isolated CloudKit custom record zone in its owner's private database; invited Herds are resolved through the participant's shared database. Record-zone identity and Apple Account/share ownership must be tracked independently of the Herd UUID. All local reads and writes stay Herd-scoped, and only authorized changes may be exported. Never upload to a different account or zone; preserve local multi-entity transaction atomicity.

The Herd is the unit of sharing. With zone-wide `CKShare`, all CloudKit records in that Herd's zone are included; no unrelated Herd may share the zone. Verify real zone sharing and all child-record types, including records created after invitations, on two Apple Accounts.

Keep application UUID identity stable. Core Data managed-object IDs are not domain identity and must not leak through repository interfaces. A UUID duplicate within a Herd, duplicate tag assignment, multiple active primary tags, invalid relationship, or conflicting state must be detected and addressed rather than ignored. Domain rules and the unchanged Core Data model remain the authority for local semantic validity. Stage and validate out-of-order remote records before atomically applying complete valid local changes; never weaken the model or synthesize IDs and required fields.

CloudKit is eventually consistent. A Core Data write gate, actor, editor revision, and local transaction coordinator cannot coordinate or lock multiple offline devices. Distinguish local concurrency protection from cross-device conflict semantics.

## 3. Current production implementation: inspect before using

This section records verified code as of the baseline above. Re-check all paths, declarations and callers on the branch being modified.

- yaHerd/Data/Persistence/CoreData/CoreDataPersistentContainer.swift: `NSPersistentContainer`, one SQLite store at Application Support/yaHerd/yaHerd.sqlite, automatic migration/inferred mapping disabled, asynchronous store load. Preserve this store and model unchanged.
- yaHerd/Data/CoreData/yaHerdModel.xcdatamodeld/yaHerdModel.xcdatamodel/contents: 18 entities, including required attributes and 26 required relationships. Apple requires optional relationships for automatic Core Data–CloudKit mirroring; this unchanged model is NOT eligible for that approach. Proposed explicit record sync does not invoke Core Data mirroring or require `syncable` changes.
- yaHerd/Data/Persistence/CoreData/CoreDataAppHerdBootstrapper.swift: creates "My Herd" whenever it finds none, selects when one, and fails for more than one. Import timing and shared Herds make this behavior unsuitable.
- yaHerd/App/Persistence/AppCurrentHerdSelection.swift: holds selected Herd UUID. yaHerd/App/Navigation/AppNavigationState.swift separately stores selectedHerdID for navigation restoration. Prevent divergence or stale cross-Herd navigation.
- yaHerd/Data/Persistence/CoreData/CoreDataContextFactory.swift: fresh background contexts for the existing local store; CoreDataTransactionExecutor.swift handles a subset of writes.
- yaHerd/Data/Repositories/CoreData/CoreDataAnimalRepository.swift, CoreDataPastureRepository.swift, CoreDataTagColorRepository.swift and CoreDataWorkingTreatmentTemplateRepository.swift: direct `context.save()` paths also exist. Audit ALL mutations for durable change capture, correct Herd/account authorization and atomic remote application; the mutation event stream alone is not a durable outbox.
- yaHerd/Data/Persistence/CoreData/CoreDataLookup.swift: UUID and Herd relationship lookups. Keep local graph consistency; staged remote CloudKit records must not be prematurely committed as incomplete Core Data objects.
- yaHerd/Data/Repositories/CoreData/CoreDataReadModelActor.swift and other projections: read models often require complete relationship graphs and may dereference relationships directly. Remotely imported related records can arrive in stages.
- yaHerd/App/Mutation/ApplicationMutationCenter.swift: only a local mutation source exists. Extend existing feature invalidation for remote changes.
- yaHerd/App/Persistence/CoreDataAppPersistenceAssembly.swift and yaHerd/App/yaHerdApp.swift: existing construction, recovery and dependency wiring.
- yaHerd/Presentation/Views/Settings/SettingsView.swift: current configuration UI, including hard-delete animal behavior.
- Scripts/verify-architecture.sh: intentionally rejects CloudKit use, entitlement names and sync naming. Update narrowly when legitimate implementation requires CloudKit. Do not disable architecture checks indiscriminately.
- yaHerd.xcodeproj/project.pbxproj and yaHerd/Info.plist: no production CloudKit entitlements/share acceptance setup in baseline.

## 4. Proposed implementation stages and completion requirements

**Approval boundary:** These stages replace the earlier automatic `NSPersistentCloudKitContainer` approach **only if this proposed architecture is approved**. Apple requires optional relationships for automatic Core Data mirroring, whereas the current model has 26 required relationships. Retaining the current model and refusing data-model migration therefore requires explicit CloudKit record synchronization. `CKSyncEngine` handles transport, retry scheduling and change tokens; the app remains responsible for mapping records, identifying durable local changes, applying remote changes, account isolation and conflict resolution. Do not implement either incompatible architecture by assumption.

### Stage 1: Prove schema-preserving synchronization feasibility

1. Inspect the current 18 entities, CRUD/save entry points, local graph constraints, recovery paths, UUID identity and relationships. Preserve the existing model and database byte-for-byte in an unchanged local-only build.
2. Validate Apple `CKSyncEngine` private/shared database support, account lifecycle and zone-wide `CKShare` capability using the actual target SDK, development entitlements and an isolated development fixture.
3. Specify a stable, deterministic mapping between each existing entity's application UUID and its CloudKit record identity, zone, fields, history and references. Avoid serializing live managed object IDs or copying the database file as a CloudKit asset.
4. Establish a durable, crash-recoverable way to detect changes made through ALL existing repository write paths, including deletes. Evaluate Core Data persistent-history tracking with the **unchanged entity model**, and verify it can be enabled safely for existing SQLite stores; otherwise design a reconciliation mechanism without introducing a second application data store. Do not rely only on volatile `ApplicationMutationCenter` notifications.
5. Prove remote records can arrive out of order, be staged safely and be reconciled into fully valid local transactions, without creating placeholder Herds, inventing UUIDs or violating required relationships.
6. Verify that a seeded populated local store can be read and reloaded without any schema migration. Keep all CloudKit test data in a development container.

**Accept when:** A focused executable development experiment demonstrates the unchanged model can support lossless record encoding/decoding, crash-safe change detection and staged relationship reconciliation. Existing records must not be rewritten or uploaded during this feasibility work. If this cannot be demonstrated, stop before implementing the sync engine and revisit the approved constraints.

### Stage 2: CloudKit record adapter and durable private/shared synchronization

1. Keep the existing local `NSPersistentContainer` and one authoritative Core Data graph. Add an isolated CloudKit adapter and `CKSyncEngine` instance per required database scope (`.private` and `.shared`). Do not add a shadow Core Data store.
2. Use one custom CloudKit record zone per owned Herd and a zone-wide `CKShare`, so the intended entire Herd and future child records belong to the same share. Never place two Herds in one share zone.
3. Persist the engine's opaque sync state, record system fields, pending changes, zone/account associations and any staging data safely across termination; isolate them by actual iCloud account and Herd. Avoid duplicate exports after retries.
4. Treat existing local Herds as authoritative until explicitly associated with an Apple Account and zone; make the initial upload idempotent, with stable IDs, no automatic duplicate Herd creation, and no silent cross-account upload.
5. Handle save success, failed export, partial remote import, deleted records, account switching, access revocation and interrupted sync separately. Use CKSyncEngine for transport; do not assume it applies records or resolves conflicts for the app.
6. Feed validated imports into existing Core Data transaction and application-mutation pathways without bypassing permission/integrity checks or re-exporting remote updates indefinitely.
7. Cover private and shared zones, all current entity types and all write paths with focused automated tests and real two-account development checks.

**Accept when:** Offline local writes remain durable; syncing preserves identities, completeness and history; restarts and retries do not lose/duplicate records; an owner and invited participant can exchange validated changes without corrupting the local model.

### Stage 3: Multi-Herd lifecycle and selection

1. Replace implicit zero/one/many Herd bootstrap behavior with explicit Herd discovery, Create Herd and Join Herd flows; a cloud import delay must not create an extra "My Herd".
2. Keep `AppCurrentHerdSelection` and `AppNavigationState.selectedHerdID` consistent. Scope all reads, edits, async results, restored routes and drafts to the selected Herd and its verified account/zone identity.
3. Protect private and shared Herd content across account changes, sign-out, invitation revocation and shared-Herd removal. Never leak the previous owner's data.
4. Preserve existing navigation and repository interfaces unless an actual new Herd-selection capability requires extension.

**Accept when:** Multiple owned/joined Herds coexist, switching cannot mix data, and unavailable or revoked Herds fail safely.

### Stage 4: Remote updates, UI invalidation and sync status

1. Use `CKSyncEngine` change events and the durable local mutation/reconciliation checkpoint for import/export progress; resume safely after interruption.
2. Publish validated remote application changes through `ApplicationMutationCenter`, including dashboard, animals, pastures, field checks and working sessions, without treating local saves as proof of upload.
3. Surface accurate pending, failed, unavailable-account and imported statuses. Keep remote batches idempotent and do not create feedback loops.
4. Avoid logging private animal/medical details, Apple Account identifiers or share URLs.

**Accept when:** Updates from another device reach already-open screens without restart and do not misrepresent synchronization completion.

### Stage 5: Complete Herd sharing lifecycle

1. Create or reuse the correct zone-wide `CKShare` for the owned Herd; use invitation-only sharing and Apple's supported native sharing UI.
2. Handle `CKShare.Metadata` acceptance, cold start, repeat invitations, expired links, permission changes, leaving, revocation and owner stop-sharing through the CloudKit API appropriate to explicit records.
3. Preserve the distinction between share changes and actual imported local Herd availability. Confirm every modeled child record is in the correct zone, including later creations.
4. Never delete local or cloud Herd records simply to resolve a stalled share or missing owner.

**Accept when:** Different Apple Accounts can share the entire Herd with stable record identities, working access changes and no accidental public sharing or cross-Herd leakage.

### Stage 6: Permissions at all write boundaries

1. Expose read-only/read-write/owner capability information independently of SwiftUI controls.
2. Enforce owner/participant permission at every local mutation and outgoing CloudKit operation, including direct repository saves and bulk workflows; distinguish offline local edits from eventual server authorization.
3. Revalidate access at commit/export and protect account-scoped local storage on sign-out/revocation.
4. Preserve existing read-only recovery restrictions.

**Accept when:** A viewer cannot edit via alternate paths and revoked changes cannot be uploaded as authorized; offline limitations are reported without false guarantees.

### Stage 7: Distributed integrity and conflict handling

1. Inventory existing aggregate revisions, identity invariants, tags, pasture membership, status, working sessions and history before defining conflict rules.
2. Handle duplicate record IDs, concurrent offline edits, edits versus deletes, share revocation, missing remote parents and out-of-order child records without fabricated defaults or silent data loss.
3. Stage remote changes until complete enough for existing Core Data constraints; apply each locally valid change atomically and checkpoint imports only after success.
4. Avoid arbitrary winner selection, unlimited self-repair loops or assumptions of globally atomic multi-record CloudKit writes.

**Accept when:** Repeated/reordered/conflicting updates preserve local invariants or produce recoverable user-visible conflicts.

### Stage 8: Production readiness, account lifecycle and device verification

1. Add native Herd selection, invitation and sharing management in the existing iOS navigation patterns.
2. Enable only the required CloudKit and remote-notification capabilities, inspect the actual development CloudKit record schema, and deploy only intentionally to production.
3. Test existing installations and clean installs, account changes, revoked participants, recovery mode, offline operation, app termination and real cross-account synchronization.
4. Run and review all applicable automated tests and the manual cases in Section 5; do not claim completion without physical-device and production-CloudKit verification.

**Accept when:** All important Herd data remains available and consistent after initial sync, real users can collaborate safely, and both local and cloud recovery are non-destructive.

## 5. Executable manual test-case plan

This is a behavior and release verification plan for ChatGPT to follow during implementation. Write focused automated tests as required by AGENTS.md; do not create unrelated testing infrastructure, CI modifications or separate tracking files. Codex reviews code and evidence, not implementation. Never mark a case passed without actually executing it.

### 5.1 Test environment, fixtures, and evidence

- **Physical devices:** A = an owner's iPhone signed into Apple Account A; A2 = another device on Account A for same-account sync (recommended); B = iPhone on different Apple Account B with read/write access; C = third Apple Account with read-only access where available. Two physical devices on different accounts are the minimum for real cross-account sharing verification; if A2 or C is unavailable, explicitly mark dependent coverage as not executed rather than asserting it.
- **Cloud environments:** Use an intentionally initialized/inspected CloudKit **development** schema for engineering scenarios. Use a separately deployed CloudKit **production** schema and TestFlight build for final acceptance. Never initialize production schema from normal app startup.
- **Existing-data fixture:** Preserve a genuine local-only build's SQLite/Core Data store and a separate restorable copy. Capture Herd IDs, per-entity counts and representative stable UUIDs, active/archived state, parentage, tag/status colors, pastures/groups, movement/health/pregnancy history, field checks and findings, treatment templates, working sessions and child records. The baseline model contains 18 entities; inspect current main and cover every entity that actually exists when testing. Preserve negative/empty cases separately.
- **Multiple-Herd fixture:** Include two owned Herds and at least one Herd shared by another Account. Give them distinct, recognizable content so wrong-Herd reads are evident.
- **Recording actual results:** In the implementing PR report, record case IDs, device and OS/build, CloudKit environment, prerequisite state, actions performed, expected vs observed outcome, and privacy-safe diagnostics. Use "passed", "failed", "blocked", or "not executed" with reasons. Do not create a separate test tracker. Never disclose personal Apple Account identifiers, sensitive Herd records or live invitation URLs in logs.
- **Cloud timing:** Wait for actual propagation/import and compare data, not an invented immediate timeout. CloudKit event success on one device alone does not prove another device received records. A prolonged stall needs a diagnosis, not an unsupported "synced" assertion.
- **Failure injection:** Use safe development fixtures, network toggles, app termination, supported Xcode/CloudKit tooling and restorable stores. If an import-order, quota or server failure cannot be induced safely, mark the relevant subcase not executed; do not claim simulation occurred.

### 5.2 Existing-data preservation, CloudKit record mapping and account isolation (Stages 1–2)

**M01 — Existing populated store adoption without model migration.** Setup: Install the prior local-only build with the representative data fixture. Steps: record counts/UUIDs and relationship/history samples; preserve a restorable original; install the new build; inspect all major features. **Pass:** No missing/duplicated data or changed application IDs, and previous CRUD behavior remains correct.

**M02 — Empty upgrade and clean installation.** Setup: One originally empty local store and one fresh device. Steps: upgrade/launch while iCloud is present and absent. **Pass:** No accidental duplicate starter Herd, synthetic recovery upload, corrupt empty store or false "cloud empty" conclusion before import finishes.

**M03 — Initial upload/interrupted sync retry.** Setup: Safe backed-up fixture, intentional CloudKit export failure and app termination. Steps: attempt an initial sync, interrupt it, then relaunch and retry. **Pass:** Original SQLite store is preserved; record IDs are stable; no missing records, duplicated Herds, or accidental account reassignment. If not inducible, state limitation.

**M04 — Unchanged model and CloudKit record schema.** Setup: Original local Core Data model and development CloudKit environment. Steps: confirm no entity/model version change; inspect the explicit CloudKit record mapping, zone/share configuration and development schema. **Pass:** Original model and SQLite remain unchanged; all 18 modeled entities can be represented and safely reconciled; production CloudKit schema is unchanged.

**M05 — Owned/shared CloudKit zone isolation.** Setup: A owns Herd P; B joins Herd S. Steps: read, create, edit and delete representative records in each selected Herd; inspect account/zone metadata and CloudKit record membership. **Pass:** The original local Core Data model is unchanged, data is scoped to the correct Herd and CloudKit zone/share, and no foreign-Herd changes or duplicate uploads occur.

**M06 — Per-account/zone sync failure and recovery.** Setup: Local Core Data store, owner zone and shared zone. Steps: induce a shared-zone permission/network failure; observe unaffected local data, account isolation and recovery mode. **Pass:** A specific error is surfaced; unrelated Herds remain available; fallback/in-memory data is never uploaded.

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

**S01 — Share a populated Herd across accounts.** Setup: A owns a full Herd; B is a different Apple Account. Steps: create invitation, accept on B, inspect every modeled descendant type. **Pass:** Only the intended Herd and its complete child graph arrive in B's shared CloudKit zone and local Herd with stable UUIDs.

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

**C07 — Cross-Herd ownership safety.** Setup: At least two accessible Herds, potentially similar record identifiers in development fixture. Steps: attempt parent/pasture/child relationship or mutation against wrong Herd/CloudKit zone. **Pass:** Correct lookup and transaction rejection, no data leakage or foreign-Herd/zone links.

**C08 — Reconciliation convergence.** Setup: Development fixture with remotely induced domain conflict. Steps: reconnect devices and observe history and repair activity. **Pass:** Bounded repair/user-actionable state, not indefinite automatic alternating writes.

### 5.6 Account failures and release acceptance (Stages 7–8)

**R01 — Apple Account transition.** Setup: A has private and joined shared Herd data. Steps: sign out of iCloud, sign into a different Apple Account and relaunch. **Pass:** Previous account's data is not disclosed or exported to new account; safe local access/recovery policy is observed.

**R02 — iCloud unavailable and CloudKit service errors.** Setup: Restorable owned/shared fixture. Steps: Disable iCloud/network; safely induce quota, denied permission, or service failure where controllable. **Pass:** Preserved local data, accurate actionable errors, no silent empty-store replacement; unavailable fault cases listed as not executed.

**R03 — Interrupted share import/export.** Setup: Large populated share invitation. Steps: terminate app or disconnect mid-transfer, then reconnect. **Pass:** Resume without duplicate Herd/share/child objects or permanently incomplete relationships.

**R04 — Archive versus permanent deletion and sharing removal.** Setup: Herd with archived animals and history. Steps: Separately exercise archive, hard delete, participant leave, revoke and owner stop-sharing on safe fixtures. **Pass:** Only intended effects, correct historical retention/relationships, no unintended purge.

**R05 — TestFlight production schema.** Setup: Development schema reviewed, production CloudKit schema intentionally deployed, TestFlight on distinct accounts. Steps: Repeat S01, S03, S06, S07, H04 (if A2 available), and C01. **Pass:** Same end-to-end behavior on production CloudKit; no reliance on development-only entitlement/schema.

**R06 — Load and app regressions.** Setup: Representative busy multi-Herd dataset with animals, pastures and sessions. Steps: Use Home, Dashboard, animal/pasture lists, filters, field checks, working and editors while cloud events arrive. **Pass:** No significant new UI freezes, incorrect counts, repeated fetch storms, crashes or lost local functionality. Record measured limits if the environment supports them; invent no numerical benchmark.

### 5.7 Completion gates

- **Stage 1:** M01–M04. Preservation of the unchanged local model/data and actual CloudKit record-mapping feasibility are mandatory.
- **Stage 2:** M05–M06 and initial upload/fresh-creation coverage. Wrong-account or wrong-zone writes block progression.
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
7. Report modified paths, evidence of verification, known gaps and unresolved risks. Do not modify tests or CI unless the user expressly instructs it.

Required changes to Scripts/verify-architecture.sh must be narrowly justified by approved CloudKit implementation. Keep its other architectural restrictions intact; do not rewrite automation or CI to create a false passing signal.

## 7. ChatGPT implementation instructions (Codex is review-only)

ChatGPT, not Codex, implements production changes, performs available verification, creates PRs and fixes review findings. When asked to implement a stage:

- Read root AGENTS.md and this feature specification, then read the latest actual source and relevant Apple API documentation.
- Treat this document as approved intended product behavior, not a claim about current implementation or an instruction to preserve incorrect assumptions.
- Perform only the user-requested stage and required dependent work. Preserve existing names/contracts whenever feasible; avoid duplicate abstractions or custom synchronization engines.
- Address both normal and failure paths, including an absent account, sharing permission, imported graph incompleteness, wrong-store routing, stale navigation, user-data preservation and destructive operations where relevant.
- Execute applicable Section 5 manual cases when the environment permits and clearly report unexecuted cases. Add focused tests for new behavior as required by AGENTS.md; do not invent passing results, restore discarded code or author unrelated process artifacts.
- Create a focused PR when requested, inspect comments, fix actual defects and report limitations. Do not merge contrary to user direction.

Example request to ChatGPT (not Codex):

"Implement the approved next CloudKit stage in Info/CLOUDKIT_COLLABORATION.md. Follow AGENTS.md. Inspect production source and tests first; add focused regression/feature coverage, make the smallest justified production changes, verify with CI and direct path inspection, and open a reviewable PR. Do not restore unrelated infrastructure."

## 8. Codex code-review agent instructions (review only)

Codex reviews code only. Do not implement a feature stage, modify production code, open an implementation PR, create automated tests or modify CI. Report findings to ChatGPT for production corrections. Review the actual PR diff and production execution paths against the requested stage and all affected feature-wide safety invariants. Do not review only this document, invent missing code based on an old plan, or assume tests have been run.

Check specifically:
- Existing data and backup/recovery preserve application data and stable UUIDs.
- Every relevant read and write preserves Herd scope, account association and CloudKit zone identity, including all direct synchronous saves.
- The share root and all intended child records are included; invitations and participants follow actual native CloudKit lifecycle and permissions.
- There are no cross-Herd/cross-zone links, duplicate roots or silently omitted child records.
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
- Existing SQLite/Core Data data remains unchanged when sync is enabled; stable UUIDs and historical relationships are retained.
- Private/shared CloudKit zone routing, owner/account association and all production local write paths have been audited.
- Multi-Herd selection, invitations, owner/editor/viewer permissions and revocation work.
- Remote changes are visible without relaunch and navigation remains correctly scoped.
- Offline conflicts, partial imports and destructive workflows have explainable/recoverable outcomes.
- Apple Account changes preserve privacy and prohibit unintended cross-account upload.
- The production CloudKit schema is deliberately deployed and real distinct-Apple-Account sharing works using the shipping app configuration.
- The final implementation has been reviewed against actual code, not the expected diagram or successful build alone.

Apple API references to check against the SDK in use:
- https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5
- https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit
- https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users
- https://developer.apple.com/documentation/cloudkit/shared-records
- https://developer.apple.com/documentation/cloudkit/ckshare
- https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes

These references explain framework behavior; they do not override the current SDK, existing production implementation, or user requirements.
