# yaHerd iCloud Synchronization and Herd Collaboration

**Status:** Approved feature requirements and implementation guidance; NOT an implemented feature.
**Requested outcome:** Offline-first device synchronization plus sharing and collaboration between different Apple Accounts.
**Initial inspection baseline:** main commit 5a5b29b6f2c4588de0e1b187133a7d1ea98838cc (2026-10-25).
**Platforms:** yaHerd iOS 26+, Swift 6, SwiftUI, Core Data.
**Authority:** User-approved requirements establish intended behavior. Inspect current production code for actual implementation; the baseline and path names below are discovery aids, never an assertion that a later branch still has that structure.

Read the repository-root AGENTS.md first. This document is a feature specification, not a dependency matrix, implementation tracker, release status report, or permission to skip source inspection.

## 1. Required product behavior

A person can own one or more Herds, select a Herd, maintain its complete records offline, and synchronize those records between devices on the same Apple Account. A Herd owner can invite another Apple Account into a Herd. Authorized participants can view and edit the same Herd, including animals, tag and status reference data, pastures and pasture groups, animal movements, health/pregnancy history, field checks, treatment templates, working sessions and their related records. Participants see changes from other devices after CloudKit synchronization. A person can own some Herds and participate in others; only one Herd is active in the main application UI at any instant.

Use invitation-based sharing by default. The owner controls invitations and participant access. Native CloudKit share access must support read-only and read/write participants; the share owner manages participants and sharing. A participant can leave a shared Herd. An owner can revoke access. Do not confuse leaving, revoking, stopping sharing, and deleting a Herd. These have different data consequences.

Local work must not require a network connection. Persist successful local transactions immediately and synchronize when CloudKit can do so. The application must not promise immediate cross-device delivery, server-global transaction atomicity, or globally serialized offline edits. Show meaningful states for local save, cloud activity, account/permission problems, and recoverable conflicts. A successful local Core Data save is NOT proof of successful CloudKit export or import on another person's device.

Existing installations must retain all local data, stable UUIDs, historical records, selected Herd identity where valid, and relationships throughout migration. Never silently replace, merge, duplicate, delete, or upload a Herd to the wrong Apple Account.

### Explicit initial-scope decisions

- Sharing boundary: one entire Herd and its owned data graph. No independent animal-level or pasture-level shares.
- Persistence: Core Data with NSPersistentCloudKitContainer, using private and shared CloudKit database scopes and corresponding local stores.
- Herd ownership: the share creator/owner remains owner. Ownership transfer is not part of the initial feature.
- Permissions: native read-only/read-write share permissions; no farm-specific server-enforced roles or custom role engine.
- Herd UI: multiple accessible Herds with one selected Herd. Keep the existing feature navigation patterns.
- Settings: device-only personal UI preferences remain local unless a concrete Herd-owned setting must be shared. Herd tag colors and other modeled Herd records synchronize.
- No SwiftData return, dual-write migration, custom sync server, custom CloudKit record replication engine, or unrelated architectural rewrite.
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

The stages below form an implementation order, not a status matrix. Every stage: inspect latest code; trace affected callers, reads, writes, recovery and navigation; implement the smallest production change; verify with available Xcode tooling and direct inspection; inspect final diff; request substantive code review; report runtime limitations. Do not create/modify tests or CI, or restore removed infrastructure, unless the user specifically asks. Implement only the requested stage and necessary prerequisites; do not roll into the next stage automatically.

### Stage 1: CloudKit-compatible Core Data model and safe migration

**Purpose:** A versioned Core Data model valid for CloudKit without losing local records.

1. Preserve the pre-CloudKit model version in the existing xcdatamodeld bundle; add an explicit new version and select it correctly. Do not rewrite history to make migration appear unnecessary.
2. Inventory the actual entity model for all attributes, optionality, defaults, relationships, inverses, delete rules, constraints and entity configurations. CloudKit mirror compatibility is a hard constraint.
3. Make relationships optional where required by Apple's Core Data CloudKit integration. Update the generated/manual managed-object interfaces and all callers of now-optional relationships; preserve domain-level required relationship validation separately.
4. Review required attributes without defaults. Use a genuine semantic default only when valid; otherwise use optional storage plus guarded projections and validation. Do not invent dates, IDs or other business meaning.
5. Verify unique constraints, unsupported relationships/configurations, inverses, delete rules and modeled relationship graph against the current SDK. Review entity syncability metadata, but do not assume syncable="NO" alone proves a CloudKit failure.
6. Audit mapping/encoding of optional and missing imported fields in all Core Data projections, feature read models, seeders and transactions. Distinguish incomplete imports from corrupt data; never crash or silently create fabricated records.
7. Choose and implement a supported explicit versioned migration path; the baseline store has automatic migration disabled. Preserve the pre-upgrade store, WAL/journal metadata and ability to diagnose failed migration. Do not manipulate SQLite files independently while Core Data owns them.
8. Verify migration with actual pre-update app data: populated and empty Herds, archived animals, tags, parentage, pasture groups, movements, treatments, field checks, working sessions, and edge-case relationships.
9. Validate model compatibility using current Xcode/Apple APIs and development CloudKit schema tooling. Never initialize or mutate production schema from normal startup.
10. Document only actual compatibility limitations in implementation output; no new status artifacts are required.

**Accept when:** Existing data migrates and loads without changed UUIDs or lost history, valid local writes still function, and the new model passes actual development CloudKit compatibility validation. A successful build alone is insufficient.

**Review focus:** Data loss, attribute/relationship semantics, migration failures/retries, optionality crashes, destructive delete-rule changes, unsupported schema evolution.

### Stage 2: Private and shared persistent stores and all-path routing

**Purpose:** One CloudKit-enabled Core Data persistence boundary that can read owned and shared Herds safely.

1. Configure iCloud/CloudKit capability, a stable CloudKit container identifier, correct development-team signing, Push Notifications and Remote notifications background mode as required by the actual target and SDK. Include all necessary debug/release entitlements and Info.plist settings.
2. Implement NSPersistentCloudKitContainer inside the existing persistence wrapper; use separate, stable SQLite URLs and NSPersistentCloudKitContainerOptions database scopes .private and .shared. Preserve in-memory/read-only recovery paths without exporting recovery data.
3. Enable persistent history tracking and store remote-change notifications for both stores. Distinguish local store-load failures from temporary CloudKit communication errors.
4. Migrate/import the existing local database as the owned/private data source using Core Data-supported operations. Never mirror one physical store into private and shared scopes or blindly duplicate records.
5. Expose a focused internal store resolver and store-qualified context behavior. Selected Herd -> owning persistent store must be authoritative and stable for each transaction.
6. Restrict Herd-specific reads using NSFetchRequest.affectedStores or equivalent supported store scoping. Ensure unknown Herd IDs, duplicate IDs and cross-Herd references fail safely.
7. Assign newly inserted managed objects to the correct store. Preserve a single-store atomic commit for multi-entity operations.
8. Audit every save path, including synchronous animal, pasture, tag color, template, Herd, field check and working repositories, and asynchronous transaction executor. Apply consistent destination-store and error/rollback behavior without unnecessary duplicated abstractions.
9. Validate that read actors, background contexts, seeders and recovery code do not accidentally read/write the wrong store. Retain concurrency isolation guarantees and existing app performance characteristics.

**Accept when:** Both stores load correctly; existing owned records stay in the private store; selected shared records read/write through the shared store; no cross-store insert or cross-Herd lookup succeeds; recovery cannot upload synthetic data.

**Review focus:** Silent wrong-store writes, duplicate local records, context isolation, migration handoff, partial store-load failures, complete audit of direct saves.

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
7. Conduct end-to-end behavioral verification across two different Apple Accounts and, if available, a second device on the owner's Account. Exercise offline work, cold-launch invitation acceptance, read-only access, revocation, multiple Herds, concurrent edits, pending import, local migration, account change, deletion, relaunch and interrupted sync.
8. Inspect production logs/status for persistent errors, stalled export/import, unnecessary refresh and crashes. Describe unverified cases as limitations rather than declaring coverage.
9. Perform the final security and user-data audit before production release.

**Accept when:** The feature works across real distinct Apple Accounts, upgraded data is preserved, data does not cross account/Herd boundaries, production schema is deployed safely, and observed behavior matches requirements. Compilation alone is insufficient.

## 5. Required end-to-end behavior scenarios

These are observable manual/device verification scenarios, NOT a directive to add automated tests or CI infrastructure.

- Upgrade an existing local-only installation with a representative populated Herd; IDs, counts and history match before/after.
- Start on a new device signed into the owner's existing iCloud Account; existing Herds import without an extra implicit "My Herd".
- Create another deliberate owned Herd and switch among owned and shared Herds; no stale cross-Herd lists, filters or routes appear.
- Invite an unrelated Apple Account to a populated Herd; accept during normal operation and after app cold launch; verify complete initial data and relationships.
- Add an animal and tag as invited editor; owner sees the correct new records without restart, not duplicates.
- Change different records offline on two devices and reconnect; both survive.
- Edit the same animal offline; observe chosen conflict policy. Do not treat silent last-writer overwrite as verified correct collaboration.
- Assign a duplicate tag or primary tag concurrently; detect and recover rather than masking.
- Move an animal while another participant deletes a pasture; inspect historical records, memberships and invalid transitions.
- Concurrently complete/modify a working session; detect invalid or competing completion.
- Delete an animal that another device currently displays; navigation and editors revalidate appropriately.
- Invite as read-only participant; verify every mutation entry point, including swipe, inline, context menu and background action, is blocked.
- Revoke a participant and have them go offline/online; verify the effective access and user messaging.
- Leave a shared Herd; verify loss of access and local selection fallback without harming the owner's data.
- Turn off networking during cloud export/import; local saves persist and are retried when service becomes available.
- Sign out of iCloud, sign into a different Apple Account and relaunch; no unauthorized exposure or upload of previous account data.
- Interrupt migration and initial sharing import; app recovers without duplicate roots or destroyed data.
- Validate failure handling for expired invitation, denied permission, quota and a temporary CloudKit service error.
- Exercise TestFlight with the production CloudKit schema, not only a development-account schema.

## 6. Pull-request implementation rules

Use focused implementation stages as PR boundaries; a phase and its demonstrably necessary dependencies may be combined when they cannot function independently. Start each stage against latest merged main and inspect current code first. Do not assume an earlier stage was completed just because this document describes it.

Before submitting each PR:
1. Identify the intended behavior and exact affected production call paths.
2. Explain the root cause or missing behavior that required changes.
3. Audit reads, writes, related workflows, errors, rollback, recovery, remote changes and navigation.
4. Use Xcode build/direct source inspection; exercise live behavior when the available environment permits.
5. Inspect the final diff for scope, dead/duplicate logic, unintended changes and restored removed infrastructure.
6. Request review against AGENTS.md and the applicable feature stage. Fix actual production defects.
7. Report modified paths, evidence of verification, known gaps and unresolved risks. Do not modify tests or CI unless the user expressly instructs it.

Required changes to Scripts/verify-architecture.sh must be narrowly justified by approved CloudKit implementation. Keep its other architectural restrictions intact; do not rewrite automation or CI to create a false passing signal.

## 7. Codex implementation instructions

When asked to implement a stage:

- Read root AGENTS.md and this feature specification, then read the latest actual source and relevant Apple API documentation.
- Treat this document as approved intended product behavior, not a claim about current implementation or an instruction to preserve incorrect assumptions.
- Perform only the user-requested stage and required dependent work. Preserve existing names/contracts whenever feasible; avoid duplicate abstractions or custom synchronization engines.
- Address both normal and failure paths, including an absent account, sharing permission, imported graph incompleteness, wrong-store routing, stale navigation, user-data preservation and destructive operations where relevant.
- Do not invent a passing verification result, restore discarded code, author process artifacts or change tests/CI.
- Create a focused PR when requested, inspect comments, fix actual defects and report limitations. Do not merge contrary to user direction.

Example invocation:

"Implement Stage 2 in Info/CLOUDKIT_COLLABORATION.md. Follow AGENTS.md. Inspect current code first. Update production persistence and all related write paths, verify available builds and execution paths, review the final diff against Stage 2 acceptance criteria, and open a PR. Do not add documentation, tests, CI, or unrelated changes."

## 8. Codex code-review agent instructions

Review the actual PR diff and production execution paths against the requested stage and all affected feature-wide safety invariants. Do not review only this document, invent missing code based on an old plan, or assume tests have been run.

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

Conclude with implementation-stage satisfaction, concrete verified defects, build/runtime actions actually executed, unverified real-device requirements and merge readiness. Never equate successful compilation with verified cross-account collaboration.

## 9. Release gates and reference resources

Do NOT claim production completion until:
- Local migration is safe and existing UUIDs/historical relationships are retained.
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
