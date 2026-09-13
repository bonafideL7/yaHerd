# yaHerd Architecture

> This document describes the **target production architecture** and the clean-architecture rules that should remain stable as implementation details change. During the Core Data cutover, existing SwiftData and bridge code may temporarily violate persistence-specific rules; `CORE_DATA_CUTOVER.md` governs that temporary work. The clean-architecture boundaries in this document remain authoritative throughout the cutover.

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
  - app bootstrap, dependency wiring, app-scoped coordination, navigation entry points, mutation/invalidation routing, preferences, diagnostics, recovery, and sync integration
- `Domain/`
  - business rules, entities, stable application identity, repository contracts, transaction contracts, use cases, domain services, validation, and policies
- `Data/`
  - Core Data models, repository implementations, mappers, persistence support, CloudKit sharing integration, seed/sample data, and persistence diagnostics
- `Presentation/`
  - SwiftUI views, view models, presentation constants, UI support types, and local presentation state

## Dependency direction

- `Presentation` depends on `Domain`.
- `Data` depends on `Domain`.
- `Domain` does not depend on `Presentation`, `Data`, SwiftUI, Core Data, CloudKit, SwiftData, or app wiring.
- `App` wires concrete implementations to domain-facing abstractions.
- Presentation never receives a persistence model, `NSManagedObject`, `NSManagedObjectContext`, or persistence-native identifier.
- Core Data and CloudKit access stay inside `Data` and narrowly-scoped app bootstrap/integration code.

## Feature structure pattern

Features should generally follow this shape:

- `Domain/Entities/<Feature>/*`
- `Domain/Repositories/<Feature>Repository.swift`
- `Domain/Transactions/*` when an operation must define one persistence commit boundary
- `Domain/UseCases/<Feature>/*` only when the operation enforces policy, coordinates repositories, shapes a workflow, or defines a transaction plan
- `Domain/Services/*` or `Domain/Policies/*` when business rules are reusable across use cases, repositories, or view models
- `Data/Models/<Feature>/*`
- `Data/Mappers/<Feature>Mapper.swift`
- `Data/Repositories/*`
- `Presentation/ViewModels/<Feature>/*`
- `Presentation/Views/<Feature>/*`

Use cases should depend on the smallest domain-facing protocol they need. A concrete repository may still implement a larger composite protocol for app wiring, but individual use cases should not depend on a broad repository surface when a narrower capability protocol is available.

Use cases are not mandatory wrappers around repository methods. Presentation may call a narrow Domain repository port directly for a single query or command when no application policy, validation, transaction, data shaping, or cross-repository orchestration is involved. Do not add `CreateXUseCase`, `UpdateXUseCase`, or `LoadXUseCase` types that only forward one call.

Keep a use case when it does at least one of the following:

- coordinates multiple repository capabilities or features
- enforces a precondition or workflow transition
- normalizes or validates input before persistence
- derives a result through a Domain service or policy
- defines or authors a transaction plan that must be committed atomically

Cross-feature orchestration belongs in use cases, not data repositories. Repositories fetch and persist data and implement storage transactions; reusable business decisions belong in Domain services or policies.

The ceremonial-use-case cleanup reduced the application layer from 59 Swift use-case files to 25 focused files. Removed types were single-call CRUD/query wrappers; callers now use the same narrow Domain repository contracts directly. `Scripts/verify-architecture.sh` rejects new one-call forwarding use cases.

## Dependency injection boundary

`yaHerdApp` injects dependencies by feature boundary instead of exposing one environment value per repository capability. The approved presentation containers are:

- `HomeFeatureDependencies`
- `AnimalFeatureDependencies`
- `PastureFeatureDependencies`
- `FieldCheckFeatureDependencies`
- `WorkingSessionFeatureDependencies`
- `CollaborationDependencies`

Each container preserves narrow Domain protocol types internally. A single concrete repository may satisfy several capability properties, but views receive one feature-scoped value rather than a long list of unrelated environment keys. Cross-feature ports are placed in the consuming feature container: for example, Animal receives pasture reference reading, Working receives animal summaries and pasture references, and Pasture receives the capabilities needed to author its delete workflow.

Feature previews and focused tests should override only their feature container. The `preview(...)` factories supply fail-fast missing implementations for unspecified capabilities, so a preview can provide only the ports exercised by that screen. App-wide services such as recovery access mode remain separate global environment values because they apply to every feature.

Do not add new root-level repository environment keys. Add a capability to the relevant feature container, or introduce a new feature container when the dependency belongs to a distinct feature boundary. `Scripts/verify-architecture.sh` enforces the approved root environment values and rejects the removed per-capability keys.

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

## Dashboard reference implementation

The dashboard flow follows the same layered split as the rest of the app:

- `Domain/Entities/Dashboard/*`
- `Domain/Repositories/DashboardRepository.swift`
- `Domain/UseCases/Dashboard/*` where orchestration is meaningful
- `Domain/Services/DashboardService.swift`
- `Data/Mappers/DashboardMapper.swift`
- a Data-layer dashboard repository implementation
- `Presentation/ViewModels/Dashboard/*`
- `Presentation/Views/Dashboard/*`
- `App/Navigation/DashboardRoute.swift`

The dashboard UI is a thin composition layer. Alert generation, overdue rules, stocking logic, list derivation, and snapshot assembly live in `Domain`.

Dashboard may reuse domain summaries from other features, but dashboard-specific record shapes and list derivation should stay in the Dashboard domain/service layer.

## Pasture reference implementation

The pasture flow is the reference implementation for feature cleanup and narrow domain boundaries:

- `Domain/Entities/Pasture/*`
- `Domain/Policies/PastureStockingPolicy.swift`
- `Domain/Services/PastureInputValidator.swift`
- `Domain/Services/PastureGroupInputValidator.swift`
- `Domain/Services/PastureMetrics.swift`
- `Domain/Repositories/PastureRepository.swift`
- `Domain/UseCases/Pasture/*`
- `Data/Models/Pasture/*`
- `Data/Mappers/PastureMapper.swift`
- a Data-layer pasture repository implementation
- `Presentation/ViewModels/Pasture/*`
- `Presentation/Views/Pasture/*`

Pasture use cases depend on narrow capability protocols instead of the full `PastureRepository` composite. Examples include:

- `PastureListReader`
- `PastureDetailReader`
- `PastureResidentAnimalReader`
- `PastureReferenceDataReader`
- `PastureNameChecking`
- `PastureCreating`
- `PastureUpdating`
- `PastureOrdering`
- `PastureDeleting`
- `PastureGroupListReader`
- `PastureGroupDetailReader`
- `PastureGroupNameChecking`
- `PastureGroupCreating`
- `PastureGroupUpdating`
- `PastureGroupDeleting`
- `PastureGroupAssignmentWriting`

`PastureRepository` may remain as a composite app-wiring contract, but use cases should prefer the narrow contracts.

Pasture business rules belong in Domain services and policies:

- `PastureInputValidator` handles pasture input normalization and validation.
- `PastureGroupInputValidator` handles pasture group input normalization and validation.
- `PastureStockingPolicy` owns stocking-field visibility and utilization thresholds.
- `PastureUtilizationStatus` represents utilization state so views do not recalculate domain thresholds.
- `PastureMetrics` owns pasture capacity and utilization calculations.

Reference data for pasture selection belongs to the Pasture boundary:

- Use `PastureReferenceDataReader.fetchPastureOptions()` directly when the caller only needs the query.
- Do not add pasture option loading back to `AnimalRepository`.

Pasture deletion remains Domain-orchestrated. `DeletePasturesUseCase` owns validation and the meaning/order of the workflow: determine the expected resident set, move residents out, preserve/archive field-check history, and delete the pasture. For the production Core Data implementation the use case should author a normalized transaction plan and pass it to the persistence transaction port. Data revalidates stale state and commits the supplied plan atomically; it does not discover or redefine the cross-feature workflow.

Pasture Groups are part of the Pasture feature. Groups use stable application IDs and should be managed through Pasture domain entities, use cases, repository capabilities, view models, and views:

- `PastureGroupInput`
- `PastureGroupSummary`
- `PastureGroupDetailSnapshot`
- `PastureGroupListReader` and `PastureGroupDetailReader` for direct queries
- `CreatePastureGroupUseCase`
- `UpdatePastureGroupUseCase`
- `DeletePastureGroupsUseCase`
- `AssignPastureToGroupUseCase`

Pasture presentation should stay state-light:

- `PastureTileListViewModel` owns filtering, selection, delete state, drag/drop state, and reorder coordination.
- `PastureTilePickerViewModel` owns loading, error state, and recent pasture tracking.
- `PastureDetailViewModel` owns display decisions such as title text, summary visibility, active animal count text, stocking display state, and utilization display state.
- SwiftUI views should render state and handle layout/navigation presentation, not business rules.

## Animal reference implementation

The animal list/add/detail flow follows the same layered pattern:

- `Domain/Entities/Animal/*`
- `Domain/Repositories/AnimalRepository.swift`
- `Domain/Transactions/*` for aggregate transaction contracts
- `Domain/UseCases/Animal/*`
- `Domain/Services/Animal*`
- `Data/Models/Animal/*`
- `Data/Mappers/AnimalMapper.swift`
- a Data-layer animal repository/transaction implementation
- `Presentation/ViewModels/Animal/*`
- `Presentation/Views/Animal/*`

Animal remains the owner of animal identity, tags, status transitions, archive/restore behavior, health records, pregnancy records, parent options, offspring draft preparation, and movement of animals between pastures.

Pasture selection options should still come from the Pasture boundary. Animal flows may consume `PastureReferenceDataReader` directly, but should not make `AnimalRepository` responsible for Pasture reference data.

`AnimalSireInferencePolicy` owns the neutral eligibility and single-candidate inference rule. The Data repository maps stored animals into `AnimalSireCandidate` values and applies the policy rather than embedding that decision in persistence code.

Complete-state animal editor updates use optimistic concurrency. The editor read carries an aggregate revision; the update transaction must compare that expected revision with current persisted state before mutating so a stale editor cannot silently overwrite a remote/imported change.

## Home reference implementation

Home is separated from Dashboard even though it reuses herd/pasture domain summaries where appropriate:

- `Domain/Entities/Home/*`
- `Domain/UseCases/Home/*`
- `Domain/Services/HomeService.swift`
- `Presentation/ViewModels/Home/*`
- `Presentation/Views/Home/*`

Home-specific task derivation, setup state, and current-work counts should stay out of `HomeView`. The SwiftUI view should render the `HomeViewModel` snapshot and handle only local navigation and presentation state.

## Check reference implementation

The pasture check flow is separated as:

- `Domain/Entities/Check/*`
- `Domain/Repositories/FieldCheckRepository.swift`
- direct capability protocols for isolated queries and commands
- `Data/Models/Check/*`
- `Data/Mappers/FieldCheckMapper.swift`
- a Data-layer field-check repository implementation
- `Presentation/ViewModels/Check/*`
- `Presentation/Views/Check/*`

Checks stay flexible by design: one session can mix head counts, tag-by-tag verification, and findings without templates or type-specific modes.

Check-specific archive capabilities that are needed by other use cases should be exposed through narrow protocols, such as `FieldCheckPastureArchiveWriter`, instead of making unrelated features depend on the full `FieldCheckRepository` surface.

## Working reference implementation

The working-session flow follows the same layered pattern:

- `Domain/Entities/Working/*`
- `Domain/Repositories/WorkingRepository.swift`
- `Domain/UseCases/Working/*`
- `Data/Models/Work/*`
- `Data/Mappers/WorkingMapper.swift`
- a Data-layer working repository implementation
- `Presentation/ViewModels/Working/*`
- `Presentation/Views/Working/*`

Working-session screens call narrow repository ports directly for isolated reads and commands. `CompleteWorkingSessionUseCase` remains because it verifies the session state and complete destination assignment set, while `WorkingSessionCompleting` commits destination updates, animal movements, and the finished state atomically in one transaction. Pasture choices used by working-session setup come from the Pasture boundary, not from Animal persistence.

## Mapping rules

- Data models should be converted to Domain snapshots/summaries through mapper types in `Data/Mappers`.
- Avoid duplicate mapping paths for the same Domain entity.
- Pasture resident animals should use `AnimalMapper.makeSummary(from:)` instead of a Pasture-specific duplicate mapping function.
- Presentation views should consume Domain snapshots/summaries or view-model display state, not persistence models.
- Managed objects and contexts never cross the Data boundary.

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

Repositories do not own reusable business decisions that belong in Domain services or policies, and they do not redefine cross-feature workflow ordering supplied by Domain.

## Transaction boundary

Multi-record business operations must have one explicit persistence transaction boundary. A successful command means the entire logical operation committed. A thrown error means no partial logical result is left committed.

Important examples include:

- animal aggregate create/update, including tags and generated history;
- pasture deletion, resident-animal movement/history, and field-check historical preservation;
- working-session collection, queue-item work-data replacement, session completion, and session deletion;
- field-check commands that update the session plus roster/finding/animal state;
- multi-animal pasture movement.

Core Data implementations should perform these writes on one appropriate context and save only after the complete mutation succeeds. On failure, roll back/reset the transaction context as appropriate. Mutation publication and sync scheduling happen **after** a successful commit, never before.

Domain use cases still own validation, workflow policy, and the meaning/order of cross-feature operations. Persistence owns stale-state validation where required, atomic execution, commit, and rollback. A use case may build a normalized transaction request/plan, but it must not recreate the transaction by chaining independently-saving persistence calls.

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
- Do not reproduce duplicated persistence state when one relationship/record set can be authoritative. In particular, the production animal model should not maintain separate scalar primary-tag fields in addition to authoritative tag records.

Do not copy the current SwiftData schema merely to reduce cutover work. Model the finished product.

## Synchronization and UI invalidation

Persistence synchronization and UI invalidation are separate concerns.

- Core Data/CloudKit owns transport and merge behavior.
- Data observes relevant persistent-store/remote-change events.
- Data/App translates those events into persistence-neutral application mutation/invalidation events.
- Presentation reloads through Domain repository/read-model contracts.
- Views and view models do not subscribe to Core Data notifications directly.

A local successful transaction publishes one logical application mutation after commit. `ApplicationMutationCenter` owns application invalidation; collaboration/sync scheduling observes successful local mutations separately rather than being coupled to UI refresh. Remote imports publish persistence-neutral invalidation without pretending they are local writes.

`HomeViewModel` subscribes to `ApplicationMutationStreaming` and reloads when an event affects `.home`. Home should not return to navigation-owned refresh counters, sheet-dismiss reloads, tab-selection reloads, `task(id:)` refresh tokens, or ad-hoc `onAppear` refresh calls.

## Sharing platform boundary

Domain collaboration types are provider-neutral. `HerdShareInvitation` and `HerdSharePresentationRequest` carry only application identifiers, participant capabilities, invitation state, URLs, and opaque provider tokens. They never retain `CKShare`, `CKContainer`, `CKShare.Metadata`, Core Data objects, or presentation callbacks.

CloudKit translation/lifetime adapters belong under `Data/Sharing/CloudKit` or another Data-layer provider boundary. Incoming `CKShare.Metadata` should be translated into a neutral invitation before crossing into Domain/App coordination, and prepared system-sharing state should likewise be hidden behind neutral requests/tokens.

Cross-user herd sharing is implemented directly on the production Core Data graph through `NSPersistentCloudKitContainer` and `CKShare`. The final sharing path must not contain a second Core Data mirror of application data. Existing bridge-specific models, import/export snapshots, reconciliation journals, and public-ID bridge repair logic are cutover artifacts to be deleted unless a requirement is independently demonstrated in the final Core Data design.

`Scripts/verify-architecture.sh` should continue to reject platform-framework imports and platform types under `Domain`.

## Recovery-mode boundary

Persistent-store failure must produce a controlled runtime state that cannot accidentally write to an unintended replacement store. Recovery behavior should be designed around the production Core Data stores rather than mechanically ported from SwiftData.

Recovery UI remains app-scoped rather than feature-owned. Recovery access must be read-only until the user explicitly chooses an allowed recovery action. Diagnostics may expose store locations, modes, history/sync state, and exportable diagnostic information, but persistence objects remain internal.

Only carry forward existing recovery/public-ID tooling when the final Core Data architecture has the same requirement. Delete tooling whose sole purpose was repairing or coordinating the old dual-stack design.

## Concurrency boundary

The app and test targets compile in Swift 6 mode with complete strict-concurrency checking and main-actor default isolation.

- Observable UI state and navigation remain `@MainActor`.
- Core Data work follows Core Data queue confinement rather than forcing all persistence onto the main actor.
- Background/private contexts perform work using Core Data's concurrency APIs on their own queue/executor.
- Managed objects never cross their context boundary into Domain or Presentation.
- Sendable Domain snapshots cross concurrency boundaries instead.
- Long reads, imports, and maintenance work should not block the main actor.
- Application sources should not introduce `@unchecked Sendable`, lock-backed state managers, or `Task.detached` as shortcuts around isolation; `Scripts/verify-concurrency.sh` enforces the project restrictions.

Repository protocol isolation may evolve as the Core Data implementation is introduced; it should reflect actual caller and context safety rather than historical SwiftData `mainContext` constraints. See `CONCURRENCY.md` for the broader concurrency rules.

## Application navigation boundary

`MainTabView` is a tab composition view, not the owner of application workflow state. App-scoped navigation lives in `AppNavigationState` and is divided into:

- `selectedTab`
- `HerdRouter` for the single herd navigation stack, list mode, search criteria, filters, sorting, and typed herd routes
- `WorkflowRouter` for resumable field-check and working-session routes
- `presentedSheet`
- `fullScreenWorkflow`

`HerdRoute`, `WorkflowRoute`, `AppPresentedSheet`, `AppFullScreenWorkflow`, and `AppNavigationRequest` are typed `Codable` values. `RootAppView` persists an `AppNavigationSnapshot` in scene storage and restores it when the scene starts. The same request model is used by URL routes and app-level notification routing.

The supported URL shape is `yaherd://<destination>/<identifier>`, including animal, pasture, field-check, work-session, and search destinations. A field-check URL may include a `finding` query item to reopen a specific finding editor.

Search is part of the herd feature hierarchy. Do not add a second Search tab containing another `HerdView`; that creates duplicate view trees and competing navigation ownership. The herd tab owns one `NavigationStack`, one search state, and one route path.

Do not add app-level modal state, workflow routes, search/filter state, or `NavigationPath` values back to `MainTabView`. Add behavior to the appropriate router or presentation modifier. `NavigationCoordinator.globalPath` was removed because it was not connected to the actual stacks.

## Testing expectations

Feature cleanup and production persistence work should include focused tests for:

- validators
- domain policies
- domain services
- meaningful use cases
- repository behavior
- transaction rollback/all-or-nothing behavior
- stable application UUID preservation and duplicate-ID handling
- relationship/delete-rule behavior
- private/shared store routing
- remote-change invalidation
- mapper behavior
- view-model state and orchestration

Do not add new tests whose only purpose is preserving the temporary SwiftData implementation. Shared Domain tests should exist only where they remain valuable after SwiftData deletion.

## Rules for future growth

1. keep views declarative and state-light
2. move screen logic into presentation view models
3. put business rules, derivations, validation, and thresholds in Domain services, policies, and meaningful use cases
4. keep Core Data/CloudKit access inside Data and narrowly-scoped app persistence integration
5. keep navigation types in `App` or `Presentation`, never in `Data` or `Domain`
6. call narrow repository capability protocols directly for simple one-port queries and commands
7. keep use cases only for policy, validation, derivation, workflow orchestration, or transaction-plan definition
8. keep cross-feature orchestration in use cases, not data repositories
9. keep reference-data ownership with the feature that owns the data
10. add focused tests when introducing or refactoring stable feature behavior and production persistence behavior
11. avoid duplicate mappers for the same Domain snapshot or summary
12. reject one-call pass-through use cases in `Scripts/verify-architecture.sh`
13. inject presentation dependencies through feature containers rather than individual repository environment keys
14. keep application UUIDs as the only Domain identity for durable entities
15. keep Core Data and CloudKit types out of Domain and Presentation
16. use explicit transaction boundaries for multi-record logical writes
17. publish application mutations only after a successful commit
18. do not introduce a second persistence graph, dual writes, mirror records, or migration-only adapters
19. prefer deleting obsolete SwiftData/bridge code over porting it

## Cutover status

SwiftData and the existing SwiftData/Core Data sharing bridge are temporary implementation code. They are not architectural precedent. Follow `CORE_DATA_CUTOVER.md` until the replacement is complete; after cutover, remove that document and any remaining transition-only code.
