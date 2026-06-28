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
4. clean up related field-check sessions through `FieldCheckPastureCleanupWriter`
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

Check-specific cleanup capabilities that are needed by other use cases should be exposed through narrow protocols, such as `FieldCheckPastureCleanupWriter`, instead of making unrelated features depend on the full `FieldCheckRepository` surface.

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
