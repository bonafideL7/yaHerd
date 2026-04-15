# Architecture cleanup notes

## What changed

### 1. Added an app-level dependency container
- New file: `App/AppDependencies.swift`
- Purpose: create repositories once at the app boundary and inject them downward.

### 2. Moved repository construction out of the app's screens
- `App/yaHerdApp.swift` now creates one shared `ModelContainer`.
- `AppDependencies` is created from the shared container's `mainContext`.
- `MainTabView` receives dependencies through the environment instead of rebuilding repositories.

### 3. Removed direct repository construction from core screens
Updated screens:
- `Presentation/Views/Animal/List/AnimalListView.swift`
- `Presentation/Views/Animal/Detail/AnimalDetailView.swift`
- `Presentation/Views/Pasture/PastureDetailView.swift`
- `Presentation/Views/Dashboard/DashboardView.swift`

These screens now use injected repository protocols instead of directly instantiating `SwiftData...Repository`.

### 4. Reduced presentation-layer coupling to SwiftData models
- Removed `init(animal: Animal)` from `AnimalDetailView`
- Removed `init(pasture: Pasture)` from `PastureDetailView`

The detail screens now use IDs only.

### 5. Removed a dashboard architecture leak
- `DashboardView` no longer uses `@Query` to resolve a live `WorkingSession` from SwiftData.
- It now renders the active session summary that already exists in the dashboard snapshot.

## What is still not fully clean

These areas still need follow-up work:
- `AnimalListView` still uses `modelContext` only for sample-data seeding in the empty state.
- Most Working screens still depend on live SwiftData models.
- Some add/edit sheets still save directly through views instead of dedicated screen-level dependency injection.
- Repository protocols for Working still pass SwiftData model types instead of IDs/snapshots.

## Recommended next step

Refactor the Working flow next:
- make Working screens ID-based
- remove `@Query` from Working views
- redesign `WorkingRepository` around IDs and domain snapshots

## Second pass: Working feature boundary cleanup

This pass focuses on the Working feature because it still had the heaviest presentation-to-data leakage.

### What changed

- Added stable `publicID` fields to:
  - `WorkingSession`
  - `WorkingQueueItem`
  - `WorkingProtocolTemplate`

- Updated `WorkingSessionsView`
  - still uses `@Query` for the list for now
  - now navigates to `WorkingSessionDetailView(sessionID:)` instead of passing the live session object through navigation
  - uses injected `AppDependencies` for delete actions instead of building a repository in the view

- Updated `WorkingSessionDetailView`
  - now loads the session by `publicID`
  - no longer takes a live `WorkingSession` in its initializer
  - uses injected `AppDependencies` for delete actions

- Updated Working feature write actions to use injected dependencies instead of view-local repository construction:
  - `NewWorkingSessionView`
  - `ProtocolTemplatesView`
  - `WorkingCollectAnimalsView`
  - `WorkingFinishSessionView`
  - `WorkingChuteView`
  - `WorkingSessionAnimalEditView`

- Updated Working UI tag display/search usage to prefer `displayTagNumber` instead of legacy `tagNumber` in key working screens.

### Why this matters

This does two important things:

1. It reduces direct data-layer construction inside presentation.
2. It starts moving Working navigation toward stable app-owned IDs instead of passing live persistence models everywhere.

### What still remains in Working

This is not the final cleanup. Working still has architectural debt:

- several Working views still accept live SwiftData models after the first detail boundary
- Working repository protocols still accept `WorkingSession`, `WorkingQueueItem`, `Animal`, and `Pasture` instead of domain IDs / inputs
- some Working views still use `@Query` directly for app data instead of going through screen view models or use cases

### Next recommended pass

The next pass should redesign `WorkingRepository` so methods operate on IDs and value inputs, for example:

- `createSession(input:)`
- `collectAnimals(sessionID:animalIDs:)`
- `saveQueueItem(sessionID:queueItemID:input:)`
- `finishSession(sessionID:)`
- `deleteSession(sessionID:)`

That is the pass that will remove most of the remaining SwiftData coupling from Working.


## Pass 3: Working repository boundary cleanup

This pass changed the public `WorkingRepository` contract so it no longer accepts live SwiftData models in its method signatures.

Changed from model-based inputs:
- `createSession(date:sourcePasture:protocolName:protocolItems:)`
- `collectAnimals(session:animals:)`
- `complete(queueItem:in:treatmentEntries:pregnancyCheck:markCastrated:observationNotes:)`
- `saveEdits(for:in:input:)`
- `deleteWorkData(for:in:)`
- `deleteSession(_:)`
- `finishSession(_:)`
- `updateTemplate(_:name:items:)`
- `deleteTemplates(_:)`

Changed to ID-based inputs:
- `createSession(date:sourcePastureID:protocolName:protocolItems:)`
- `collectAnimals(sessionID:animalIDs:)`
- `complete(queueItemID:inSessionID:treatmentEntries:pregnancyCheck:markCastrated:observationNotes:)`
- `saveEdits(forQueueItemID:inSessionID:input:)`
- `deleteWorkData(forQueueItemID:inSessionID:)`
- `deleteSession(id:)`
- `finishSession(id:)`
- `updateTemplate(id:name:items:)`
- `deleteTemplates(ids:)`

What this improves:
- The domain contract is no longer tied to `WorkingSession`, `WorkingQueueItem`, `Animal`, `Pasture`, or `WorkingProtocolTemplate` model instances.
- Views now call use cases with stable public IDs instead of handing persistence objects into repository methods.
- SwiftData model lookup is now concentrated inside `SwiftDataWorkingRepository`.

What is still left:
- Working views still read SwiftData directly with `@Query` and `@Bindable`.
- Child working screens still pass live models through navigation.
- The next cleanup is screen/view-model level snapshots so presentation stops binding directly to SwiftData models.

## Pass 4 - Working presentation moved toward snapshots and view models

This pass removes the direct SwiftData query/model dependency from the main Working list/detail/template screens.

### Added
- `Domain/Entities/Working/WorkingSnapshots.swift`
  - `WorkingSessionSummary`
  - `WorkingSessionDetailSnapshot`
  - `WorkingQueueItemSnapshot`
  - `WorkingProtocolTemplateSummary`
  - `WorkingProtocolTemplateDetailSnapshot`
- `Presentation/ViewModels/Working/WorkingViewModels.swift`
  - `WorkingSessionsViewModel`
  - `WorkingSessionDetailViewModel`
  - `WorkingProtocolTemplatesViewModel`
  - `WorkingProtocolTemplateDetailViewModel`
  - `NewWorkingSessionViewModel`

### Repository changes
- `WorkingRepository` now exposes read methods for Working presentation:
  - `fetchSessions()`
  - `fetchSessionDetail(id:)`
  - `fetchTemplates()`
  - `fetchTemplateDetail(id:)`
- `SwiftDataWorkingRepository` maps SwiftData models into Working snapshots for those read methods.

### View changes
The following screens no longer build themselves directly from `@Query` / `@Bindable` Working model state:
- `WorkingSessionsView`
- `WorkingSessionDetailView`
- `ProtocolTemplatesView`
- `ProtocolTemplateDetailView`
- `NewWorkingSessionView`

These screens now:
- use `AppDependencies`
- load through view models
- render domain snapshots instead of live `WorkingSession` / `WorkingProtocolTemplate` objects

### Contained compatibility updates
To avoid a bigger UI rewrite in this pass, a few child screens still query the live session internally by `sessionID`:
- `WorkingQueueView`
- `WorkingSessionAnimalsView`
- `WorkingCollectAnimalsView`
- `WorkingFinishSessionView`

That keeps the UI behavior close to the current app while removing the larger presentation leaks from the top-level Working screens.

### What still remains
Working is cleaner, but not fully clean yet.

Still left to remove:
- `WorkingChuteView` still uses live `WorkingSession` / `WorkingQueueItem`
- `WorkingSessionAnimalEditView` still uses `@Bindable` plus direct `@Query` access to treatment / preg / health data
- finish-session destination edits still rely on direct model mutation before the repository finishes the session

### Why this pass matters
Before this pass, the main Working navigation screens were still presentation-bound to SwiftData.
After this pass, the top of the Working flow is driven by repository-fed snapshots and view models, which is the correct architecture direction.

## Pass 5 - Working chute/edit/finish cleanup

This pass removes the remaining high-value Working presentation leaks.

### What changed

- Added `WorkingQueueItemEditorSnapshot` and supporting snapshot types.
- Added `WorkingRepository.fetchQueueItemEditor(sessionID:queueItemID:)`.
- Added `WorkingRepository.saveDestinations(sessionID:assignments:)`.
- Updated `SwiftDataWorkingRepository` to load editor state and persist destination assignments internally.
- Added `WorkingQueueItemEditorViewModel` and `WorkingFinishSessionViewModel`.
- Reworked these views to load by ID and render snapshot state instead of binding directly to live SwiftData models:
  - `WorkingChuteView`
  - `WorkingSessionAnimalEditView`
  - `WorkingFinishSessionView`
  - `WorkingQueueView`
  - `WorkingSessionAnimalsView`

### Why this matters

Before this pass, those screens still depended on `@Query`, `@Bindable`, and direct mutation of `WorkingSession` / `WorkingQueueItem` models.

After this pass:
- screen entry points are ID-based
- editor screens load repository-backed snapshots
- destination selection for finishing a session is local UI state until saved through the repository
- persistence lookups and persistence mutation are pushed back into the data layer

### What still remains

Working is much cleaner now, but it is still not fully view-model-first everywhere. The next remaining cleanup is mostly refinement rather than structural rescue.


## Pass 6 - Validation, mapping, and correctness

- Fixed the animal editor dirty-state bug so sold/dead dates are only compared when that status is active. This removes false unsaved-change prompts caused by comparing `nil` dates to `.now`.
- Expanded animal validation to enforce self-parent rejection, duplicate sire/dam rejection, sire/dam sex checks, and sold/dead status date requirements.
- Moved animal summary/detail/parent-option/tag snapshot mapping into `Data/Mappers/AnimalMapper.swift` so the repository is less overloaded.
- Stopped silently defaulting missing sex values to female in key mapping paths; these now preserve `unknown` instead.
- Made dashboard working-session identifiers stable by basing them on `WorkingSession.publicID` instead of a derived string.


## Pass 7

- Extracted `PastureMapper`, `DashboardMapper`, and `WorkingMapper` so repositories stop inlining most snapshot conversion logic.
- Split the large combined Working entity, use case, and view model files into smaller focused files.
- Fixed a working-session correctness bug where observation records were inserted twice on completion.
- Added working-session collection validation so animals cannot be collected twice into the same session or collected while already assigned to another active session.


## Pass 8
- Added a real `yaHerdTests` unit-test target to the Xcode project and shared scheme.
- Added focused tests for animal validation, animal editor dirty-state rules, dashboard mapping, and working-session collection/observation behavior.
- Added in-memory SwiftData test support for repository-level unit tests.


## Pass 9

- Removed more direct repository construction from presentation sheets and pickers.
- `AddAnimalView`, `HealthRecordAddView`, `PregnancyCheckAddView`, `AnimalParentPickerView`, `AddPastureView`, `AddPastureGroupView`, and `PasturePickerView` now use `AppDependencies` instead of building SwiftData repositories locally.
- Removed `@Query` from `PasturePickerView`; it now loads pasture options through the animal repository boundary.
- Updated Settings app copy from iOS 18 to iOS 26+.
- Remaining known presentation leak: `PastureTilePickerView` still uses direct SwiftData query/model state because its tile cards depend on live pasture model fields such as acreage and resident head count.


## Pass 10
- Removed direct SwiftData query usage from `WorkingCollectAnimalsView`; it now loads `WorkingSessionDetailSnapshot` and `AnimalSummary` data through repositories and selects by `UUID` rather than live models.
- Removed direct SwiftData query usage from `PastureTilePickerView`; it now loads `PastureSummary` values through `PastureRepository` and the tile cards render summary data instead of live `Pasture` models.
- Removed the last known `modelContext` usage from `AnimalListView` by moving sample-data seeding behind `AppDependencies`.
- Remaining known presentation leak: `AnimalTimelineContainerView` still fetches a live `Animal` model for the timeline screen.


## Pass 11

- Removed the last known presentation-level `modelContext` usage from `AnimalTimelineContainerView`.
- Added `AnimalRepository.fetchTimeline(id:)` so the timeline screen now loads through the repository boundary instead of fetching a live `Animal` model from presentation.
- Moved animal timeline event types to domain-facing entities and kept timeline construction in the data layer.
- Removed stale `SwiftData` imports from dashboard and pasture presentation files that no longer use it.
