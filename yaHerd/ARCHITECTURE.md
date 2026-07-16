# Clean Architecture layout

## Top-level layers

- `App/`
  - app bootstrap, dependency wiring, app-scoped coordination, navigation entry points, preferences, diagnostics, and sync support
- `Domain/`
  - business rules, entities, repository contracts, use cases, domain services, validation, and policies
- `Data/`
  - SwiftData models, repository implementations, mappers, persistence support, seed/sample data, and sync/reset implementation details
- `Presentation/`
  - SwiftUI views, view models, presentation constants, UI support types, and local presentation state

## Dependency direction

- `Presentation` depends on `Domain`
- `Data` depends on `Domain`
- `Domain` does not depend on `Presentation`, `Data`, SwiftUI, SwiftData, or app wiring
- `App` wires concrete implementations to domain-facing abstractions
- SwiftData access should stay inside `Data` repositories and app bootstrap/persistence setup

## Feature structure pattern

Features should generally follow this shape:

- `Domain/Entities/<Feature>/*`
- `Domain/Repositories/<Feature>Repository.swift`
- `Domain/UseCases/<Feature>/*` only when the operation enforces policy, coordinates repositories, shapes a workflow, or defines a transaction
- `Domain/Services/*` or `Domain/Policies/*` when business rules are reusable across use cases, repositories, or view models
- `Data/Models/<Feature>/*`
- `Data/Mappers/<Feature>Mapper.swift`
- `Data/Repositories/SwiftData<Feature>Repository.swift`
- `Presentation/ViewModels/<Feature>/*`
- `Presentation/Views/<Feature>/*`

Use cases should depend on the smallest domain-facing protocol they need. A concrete repository may still implement a larger composite protocol for app wiring, but individual use cases should not depend on a broad repository surface when a narrower capability protocol is available.

Use cases are not mandatory wrappers around repository methods. Presentation may call a narrow Domain repository port directly for a single query or command when no application policy, validation, transaction, data shaping, or cross-repository orchestration is involved. Do not add `CreateXUseCase`, `UpdateXUseCase`, or `LoadXUseCase` types that only forward one call.

Keep a use case when it does at least one of the following:

- coordinates multiple repository capabilities or features
- enforces a precondition or workflow transition
- normalizes or validates input before persistence
- derives a result through a Domain service or policy
- defines a transaction boundary that must be tested as one operation

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

Each container preserves narrow Domain protocol types internally. A single concrete repository may satisfy several capability properties, but views receive one feature-scoped value rather than a long list of unrelated environment keys. Cross-feature ports are placed in the consuming feature container: for example, Animal receives pasture reference reading, Working receives animal summaries and pasture references, and Pasture receives animal movement and field-check archival capabilities used by its delete workflow.

Feature previews and focused tests should override only their feature container. The `preview(...)` factories supply fail-fast missing implementations for unspecified capabilities, so a preview can provide only the ports exercised by that screen. App-wide services such as recovery access mode remain separate global environment values because they apply to every feature.

Do not add new root-level repository environment keys. Add a capability to the relevant feature container, or introduce a new feature container when the dependency belongs to a distinct feature boundary. `Scripts/verify-architecture.sh` enforces the approved root environment values and rejects the removed per-capability keys.

## Dashboard reference implementation

The dashboard flow follows the same layered split as the rest of the app:

- `Domain/Entities/Dashboard/*`
- `Domain/Repositories/DashboardRepository.swift`
- `Domain/UseCases/Dashboard/*`
- `Domain/Services/DashboardService.swift`
- `Data/Mappers/DashboardMapper.swift`
- `Data/Repositories/SwiftDataDashboardRepository.swift`
- `Presentation/ViewModels/Dashboard/*`
- `Presentation/Views/Dashboard/*`
- `App/Navigation/DashboardRoute.swift`

The dashboard UI is a thin composition layer. Alert generation, overdue rules, stocking logic, list derivation, and snapshot assembly live in `Domain`.

Dashboard may reuse domain summaries from other features, but dashboard-specific record shapes and list derivation should stay in the Dashboard domain/service layer.

## Pasture reference implementation

The pasture flow is the current reference implementation for feature cleanup and narrow domain boundaries:

- `Domain/Entities/Pasture/*`
- `Domain/Policies/PastureStockingPolicy.swift`
- `Domain/Services/PastureInputValidator.swift`
- `Domain/Services/PastureGroupInputValidator.swift`
- `Domain/Services/PastureMetrics.swift`
- `Domain/Repositories/PastureRepository.swift`
- `Domain/UseCases/Pasture/*`
- `Data/Models/Pasture/*`
- `Data/Mappers/PastureMapper.swift`
- `Data/Repositories/SwiftDataPastureRepository.swift`
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

`PastureRepository` remains as a composite app-wiring contract implemented by `SwiftDataPastureRepository`, but use cases should prefer the narrow contracts.

Pasture business rules belong in Domain services and policies:

- `PastureInputValidator` handles pasture input normalization and validation.
- `PastureGroupInputValidator` handles pasture group input normalization and validation.
- `PastureStockingPolicy` owns stocking-field visibility and utilization thresholds.
- `PastureUtilizationStatus` represents utilization state so views do not recalculate domain thresholds.
- `PastureMetrics` owns pasture capacity and utilization calculations.

Reference data for pasture selection belongs to the Pasture boundary:

- Use `PastureReferenceDataReader.fetchPastureOptions()` directly when the caller only needs the query.
- Do not add pasture option loading back to `AnimalRepository`.

Pasture delete behavior is intentionally coordinated by `DeletePasturesUseCase`:

1. validate requested pasture IDs
2. fetch resident animals
3. unassign resident animals through `AnimalPastureMoving`
4. archive related field-check sessions through `FieldCheckPastureArchiveWriter`
5. delete the pasture records through `PastureDeleting`

That cross-feature sequence should not be moved into `SwiftDataPastureRepository`.

Pasture Groups are part of the Pasture feature. Groups use stable public IDs and should be managed through Pasture domain entities, use cases, repository capabilities, view models, and views:

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
- `PastureTilePickerViewModel` owns loading, error state, recent pasture tracking, and legacy migration.
- `PastureDetailViewModel` owns display decisions such as title text, summary visibility, active animal count text, stocking display state, and utilization display state.
- SwiftUI views should render state and handle layout/navigation presentation, not business rules.

## Animal reference implementation

The animal list/add/detail flow follows the same layered pattern:

- `Domain/Entities/Animal/*`
- `Domain/Repositories/AnimalRepository.swift`
- `Domain/UseCases/Animal/*`
- `Domain/Services/Animal*`
- `Data/Models/Animal/*`
- `Data/Mappers/AnimalMapper.swift`
- `Data/Repositories/SwiftDataAnimalRepository.swift`
- `Presentation/ViewModels/Animal/*`
- `Presentation/Views/Animal/*`

Animal remains the owner of animal identity, tags, status transitions, archive/restore behavior, health records, pregnancy records, parent options, offspring draft preparation, and movement of animals between pastures.

Pasture selection options should still come from the Pasture boundary. Animal flows may consume `PastureReferenceDataReader` directly, but should not make `AnimalRepository` responsible for Pasture reference data.

`AnimalSireInferencePolicy` owns the neutral eligibility and single-candidate inference rule. `SwiftDataAnimalRepository` maps stored animals into `AnimalSireCandidate` values and applies the policy rather than embedding that decision in persistence code.

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
- direct `Domain/Repositories/FieldCheckRepository.swift` capability protocols for isolated queries and commands
- `Data/Models/Check/*`
- `Data/Mappers/FieldCheckMapper.swift`
- `Data/Repositories/SwiftDataFieldCheckRepository.swift`
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
- `Data/Repositories/SwiftDataWorkingRepository.swift`
- `Presentation/ViewModels/Working/*`
- `Presentation/Views/Working/*`

Working-session screens call narrow repository ports directly for isolated reads and commands. `CompleteWorkingSessionUseCase` remains because it verifies the session state and complete destination assignment set, while `WorkingSessionCompleting` commits destination updates, animal movements, and the finished state atomically in one save. Pasture choices used by working-session setup come from the Pasture boundary, not from Animal persistence.

## Mapping rules

- Data models should be converted to Domain snapshots/summaries through mapper types in `Data/Mappers`.
- Avoid duplicate mapping paths for the same Domain entity.
- Pasture resident animals should use `AnimalMapper.makeSummary(from:)` instead of a Pasture-specific duplicate mapping function.
- Presentation views should consume Domain snapshots/summaries or view-model display state, not SwiftData models.

## Testing expectations

Feature cleanup should include focused tests for:

- validators
- domain policies
- domain services
- use cases
- repository behavior
- view-model state and orchestration

Pasture currently has focused coverage for validators, metrics/policies, use cases, SwiftData repository behavior, tile picker behavior, and tile list behavior. Keep that pattern when extending Pasture or cleaning up other features.

## Rules for future growth

1. keep views declarative and state-light
2. move screen logic into presentation view models
3. put business rules, derivations, validation, and thresholds in domain services, policies, and meaningful use cases
4. keep SwiftData access inside data repositories and app persistence setup
5. keep navigation types in `App` or `Presentation`, never in `Data` or `Domain`
6. call narrow repository capability protocols directly for simple one-port queries and commands
7. keep use cases only for policy, validation, derivation, workflow orchestration, or transaction definition
8. keep cross-feature orchestration in use cases, not data repositories
9. keep reference-data ownership with the feature that owns the data
10. add focused tests when introducing or refactoring feature behavior
11. avoid duplicate mappers for the same domain snapshot or summary
12. reject one-call pass-through use cases in `Scripts/verify-architecture.sh`
13. inject presentation dependencies through feature containers rather than individual repository environment keys

## SwiftData schema evolution

- `Data/Persistence/Schema/YaHerdSchemaV1.swift` contains the frozen 1.0 persistent models.
- `Data/Persistence/Schema/YaHerdCurrentModels.swift` exposes the current schema's models to the rest of the app through type aliases.
- `Data/Persistence/Schema/YaHerdMigrationPlan.swift` is the ordered schema and migration-stage history.
- `ModelContainerFactory` is the only production entry point for opening SwiftData stores and always supplies the migration plan.
- Startup bootstrap and repair utilities run only after the store opens and are not substitutes for schema migration stages.

See the repository-level `MIGRATIONS.md` for the required release workflow, fixture-store rules, and the model changes that require custom migration.

## Sharing platform boundary

Domain collaboration types are provider-neutral. `HerdShareInvitation` and `HerdSharePresentationRequest` carry only application identifiers, participant capabilities, invitation state, URLs, and opaque `HerdShareToken` values. They never retain `CKShare`, `CKContainer`, `CKShare.Metadata`, Core Data objects, or presentation callbacks.

`CloudKitShareAdapter` under `Data/Sharing/CloudKit` is the translation and lifetime boundary. It converts incoming `CKShare.Metadata` into a neutral invitation while retaining the metadata behind an opaque token, and it retains prepared `CKShare` sessions behind neutral presentation requests. `CoreDataHerdSharingRepository` resolves those tokens only when accepting an invitation or preparing the system sharing UI. `Scripts/verify-architecture.sh` rejects platform-framework imports and platform types under `Domain`.

## Sharing bridge risk boundary

The SwiftData/Core Data CloudKit sharing bridge is treated as a separate high-risk boundary. Store lifecycle, import orchestration, export orchestration, operation journaling, and reconciliation are split into focused files under `Data/Sharing/CoreData`. Import precedes export, each direction uses one persistent-store commit, retries are idempotent, and duplicate application-managed public IDs are explicitly detected. See `SHARING_BRIDGE_RELIABILITY.md` at the repository root for release requirements and the two-device test matrix.
## Recovery-mode boundary

Persistent-store failure is handled by a separate `AppDataAccessMode.recoveryReadOnly` runtime state. The recovery container is in memory with saving disabled, all mutation-capable repositories are wrapped by `HerdCollaborationWritePolicy`, and the CloudKit sharing repository and automatic synchronization are not attached. `RecoveryModeBannerOverlay` provides the persistent cross-presentation warning, while `RecoveryModeController` owns diagnostics, diagnostic-store export, and the acknowledged production-store open/repair attempt. Recovery mode never transitions to writable state during the current launch. See the repository-level `RECOVERY_MODE.md` for invariants and release tests.

## Concurrency boundary

The app and test targets compile in Swift 6 mode with complete strict-concurrency checking and main-actor default isolation. Domain repository protocols are explicitly `@MainActor` because production repositories use `ModelContainer.mainContext`. Observable UI state, navigation, sharing coordinators, mutation scheduling, and collaboration write validation use the same actor. Application sources may not introduce `@unchecked Sendable`, lock-backed state managers, or `Task.detached`; the CI gate in `Scripts/verify-concurrency.sh` enforces those restrictions. See `CONCURRENCY.md` at the repository root.

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
