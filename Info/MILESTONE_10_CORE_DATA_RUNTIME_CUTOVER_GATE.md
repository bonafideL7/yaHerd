# Milestone 10 — Core Data runtime cutover gate

**Assessment:** The **active-runtime single-persistence-stack gate** described in `Core-Data-SwiftData-replacement-execution-plan.md` is satisfied by the current `main` composition. This is an architecture/runtime-cutover assessment, **not** a certification that all legacy user data can be upgraded or that a device-level release has been tested.

## Gate definition

Milestone 10 requires that every **active production** dependency path resolve to Core Data; no production startup, recovery, feature read, or feature write may instantiate SwiftData or mix repositories from distinct persistence stacks. The app may fail visibly rather than silently choosing another persistence store. Removal of unused, compiled SwiftData source belongs to **Milestone 11**. Architecture enforcement and final hardening belong to **Milestone 12**.

## Active production-path evidence

| Boundary | Verified static production path / permanent contract |
| --- | --- |
| Durable startup and lifetime | `yaHerd/App/yaHerdApp.swift` calls `CoreDataAppPersistenceAssembly.load(at:)` and retains the assembly inside `AppRuntime.persistenceLifetime`. `RootAppView` mounts only after bootstrap succeeds. |
| Recovery and failure | Durable load failure calls `CoreDataAppPersistenceAssembly.inMemoryRecovery()`, yielding an in-memory Core Data graph under `.recoveryReadOnly`. Failure of both Core Data stores shows `StartupStorageFailureView`; neither branch opens SwiftData. |
| Single Herd and source store | `CoreDataAppPersistenceAssembly.makeDependencies` builds Core Data repositories and M9 query actors against the same `CoreDataPersistenceAssembly` and `AppCurrentHerdSelection`. |
| Animal, Pasture, tag colors, and Herd | Core Data repositories are wrapped by mutation-publishing/read-only-policy decorators; Pasture deletion uses `CoreDataPastureDeletionTransactionWriter`. |
| Field Check and Working | `CoreDataFieldCheckRepository` and `CoreDataWorkingAppRepository` provide active commands, including transaction boundaries; their Animal candidates use M9 Core Data reference snapshots. |
| Home, Dashboard, Animal list, parent picker | Home/Dashboard use M9 query actors. The full Animal list uses `AnimalListSnapshotReading.fetchAnimalSummarySnapshot()` both from its observer **and** direct add-sheet/inline/sample-data reload helper. The shared sire/dam picker uses the async `AnimalParentOptionQueryReading`. |
| Post-commit signaling | `ApplicationMutationPipeline` / `ApplicationMutationCenter` publish only through the Core Data feature wrappers. Existing selected-Herd and revision contracts own consistency. |
| Legacy store safety | `CoreDataLegacyStorePreflight.ensureSafeFirstOpen` rejects unsafe first-open overlap with recognized legacy stores/journals; read-only recovery preserves and can export original artifacts. This **does not import** legacy records into Core Data. |

## Coverage and test ownership

`Info/MILESTONE_10_CORE_DATA_RUNTIME_CUTOVER_MATRIX.md` contains **22 materially distinct behaviors** with the repository's **14 required dimensions**. Every evaluation is qualified, and no M10 evaluation cell remains `Unverified:`. The dormant Dashboard pasture-grazing **UI activation** is explicitly `Delegated:` to a separate Dashboard pasture-list navigation and grazing-action activation work item. Its existing Core Data writer and read projection are covered by permanent M4/M9 contracts; that inactive UI integration is not evidence of an incomplete active Core Data runtime cutover.

Examples of existing contracts that substantiate the runtime boundary:

- `yaHerdTests/CoreData/CoreDataAppHerdBootstrapperTests.swift`: one active Core Data app graph, recovery/preflight guards, feature-port injection and revisions.
- `yaHerdTests/CoreData/CoreDataHomeReadModelContractTests.swift`: Dashboard projections and grazing writer's committed/read-only effects.
- `yaHerdTests/CoreData/CoreDataAnimalRepositoryContractTests.swift` and `yaHerdTests/RepositoryContracts/AnimalRepositoryReadModelContract.swift`: the full-list, reference, and parent-option actor semantics and fresh-context identity.
- `yaHerdTests/AnimalListViewModelReloadTests.swift`: complete-list snapshot selection, direct reload recovery, and no independent page fallback for complete cohorts.
- Permanent Field Check and Working contracts: session/queue transaction correctness, error rollback and cross-feature identity.

**Automated verification:** The platform's PR #125 verification completed successfully on head commit `950fe6a953fef5bc72522f2c5608cfaa43c373ab` (workflow run `37854230770`), and PR #125 merged into `main` at `384788ce8c7dbe7f7f095eb177a0a391572c4feb`. This gate assessment did **not** manually start any tests, builds, lint or CI workflows. A successful automated PR check is not a substitute for testing on a physical device and exercising existing data-store upgrades.

## Deliberately excluded / outstanding

1. **Dashboard pasture grazing UI:** `DashboardPastureListView` contains a dormant swipe action, but no active navigation destination constructs this view. `DashboardRoute.pastureList` exists as an unused route value. The Core Data grazing writer and contract exist, but there is **no active caller** and no injected grazing command in the running Home graph. Therefore, M10 does not claim that the dormant interaction is verified or enabled. The M10 matrix delegates its end-to-end success path to the **Dashboard pasture-list navigation and grazing-action activation work item**, responsible for mounting the route, injecting the Core Data-backed `PastureGrazingMarking` dependency and verifying the swipe action and failure/recovery experience.
2. **Existing SwiftData local stores:** M10 protects legacy bytes and supplies recovery/export; it does **not** migrate them. Legacy-data transfer/release upgrade handling requires an explicit product and data-preservation decision **before shipping the cutover to users with old local stores**. Do not interpret the M10 runtime gate as proof that an existing user's data is accessible after upgrading. Do not delete the only legacy data copy during M11 cleanup.
3. **Unused SwiftData implementations:** Legacy source remains compiled but uninstantiated in the production graph. Deletion is Milestone 11's task, not evidence of a hybrid M10 runtime.
4. **Architecture enforcement and final release confidence:** Static checks preventing a future SwiftData or synchronization bridge reintroduction, plus final Core Data hardening and release-level testing, belong to Milestone 12 / release qualification.

## Exit decision

The **M10 single-runtime composition gate is ready to close** on the merged code. Do not activate unused Dashboard UI merely to create an unnecessary M10 success path: its future interaction is explicitly delegated, not considered verified. Do not begin M11 by deleting legacy user files. M11 may remove obsolete compiled SwiftData implementation **after** preserving recognized legacy data and recording an explicit upgrade/migration policy; its removal and final architecture tests remain separate gates.
