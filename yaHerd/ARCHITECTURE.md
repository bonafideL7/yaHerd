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
- `Domain/UseCases/<Feature>/*`
- `Domain/Services/*` or `Domain/Policies/*` when business rules are reusable across use cases/view models
- `Data/Models/<Feature>/*`
- `Data/Mappers/<Feature>Mapper.swift`
- `Data/Repositories/SwiftData<Feature>Repository.swift`
- `Presentation/ViewModels/<Feature>/*`
- `Presentation/Views/<Feature>/*`

Use cases should depend on the smallest domain-facing protocol they need. A concrete repository may still implement a larger composite protocol for app wiring, but individual use cases should not depend on a broad repository surface when a narrower capability protocol is available.

Cross-feature orchestration belongs in use cases, not data repositories. Repositories should persist and fetch data; they should not hide business policy involving other features.

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

- Use `PastureReferenceDataReader` and `LoadPastureOptionsUseCase`.
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
- `LoadPastureGroupsUseCase`
- `LoadPastureGroupDetailUseCase`
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

Pasture selection options should still come from the Pasture boundary. Animal flows may consume `PastureReferenceDataReader` or `LoadPastureOptionsUseCase`, but should not make `AnimalRepository` responsible for Pasture reference data.

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
- `Domain/UseCases/Check/*`
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

Working-session screens should keep workflow orchestration in use cases and view models. Pasture choices used by working-session setup should come from the Pasture boundary, not from Animal persistence.

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
3. put business rules, derivations, validation, and thresholds in domain services, policies, and use cases
4. keep SwiftData access inside data repositories and app persistence setup
5. keep navigation types in `App` or `Presentation`, never in `Data` or `Domain`
6. prefer narrow repository capability protocols for use cases over broad feature repositories
7. keep cross-feature orchestration in use cases, not data repositories
8. keep reference-data ownership with the feature that owns the data
9. add focused tests when introducing or refactoring feature behavior
10. avoid duplicate mappers for the same domain snapshot or summary

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
