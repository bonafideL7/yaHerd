# Swift 6 concurrency policy

yaHerd builds in Swift 6 language mode with complete strict-concurrency checking. Concurrency warnings are build failures in local Xcode builds and CI.

## Build settings

The effective Debug and Release settings for both `yaHerd` and `yaHerdTests` must resolve to:

- `SWIFT_VERSION = 6.0`.
- `SWIFT_STRICT_CONCURRENCY = complete`.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.

Module-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is prohibited. Actor ownership must be explicit at the relevant UI, repository, persistence, or service boundary so a target-wide default cannot hide isolation mistakes.

`Scripts/verify-concurrency.sh` checks the effective Xcode build settings rather than only searching `project.pbxproj` for matching strings. A configuration that contains the expected text but does not apply it to the app or test target must fail verification.

## Isolation rules

1. SwiftData models stay on the model actor or actor that owns their `ModelContext`. They must not be transferred between actors as ordinary values.
2. Repositories that use `ModelContainer.mainContext` remain `@MainActor`. Model-actor repositories remain isolated to their model actor.
3. UI coordinators, observable UI state, collaboration write policy, and mutation-sync scheduling stay on `MainActor` unless deliberately moved behind another actor boundary.
4. Synchronous use cases that orchestrate main-actor repository calls are explicitly `@MainActor`. Do not rely on target-wide default isolation.
5. Repository-backed validators are `@MainActor` when their duplicate checks call main-context repositories. Pure validation helpers may be nonisolated only when they do not capture repository state.
6. SwiftUI `EnvironmentKey.defaultValue` is a synchronous nonisolated requirement. Stateless fallback implementations of main-actor repository protocols must expose a nonisolated fallback initializer. Feature dependency containers used by environment defaults remain nonisolated while repository methods retain their declared actor isolation.
7. A type must not use `@unchecked Sendable` to silence a compiler error. Redesign ownership or isolate the state to an actor.
8. Do not move `ModelContext`, managed SwiftData models, `NSManagedObject`, or CloudKit sharing metadata across actors.
9. Background work operates on immutable `Sendable` snapshots and returns immutable results to the owning actor for persistence.
10. Tasks launched from views or UI coordinators declare their executor explicitly when they mutate UI or repository state.
11. Long-lived tasks are stored, canceled when superseded, and avoid strongly retaining their owner.
12. Do not introduce lock-backed mutable state managers. Use an actor or an appropriate global actor.
13. Do not capture non-`Sendable` SwiftData models or non-`Sendable` repair/planning structures in escaping or potentially executor-crossing standard-library closures. Snapshot required scalar values or iterate while remaining on the owning actor.

## Collaboration subsystem

`HerdSharingMutationSyncScheduler` and `HerdCollaborationWritePolicy` are main-actor-isolated state machines. This matches the actor that owns the main SwiftData context and sharing sync coordinator.

The Core Data sharing bridge remains main-actor isolated because its import/export transaction includes the main SwiftData context. A future background implementation must first convert SwiftData and Core Data records into `Sendable` snapshots and must not pass managed objects between executors.

## CI verification gate

`.github/workflows/swift-concurrency.yml` runs `Scripts/verify-concurrency.sh` for:

- newly opened pull requests;
- every subsequent PR synchronization/push;
- reopened pull requests;
- pull requests marked ready for review;
- every push to `main`;
- manual workflow dispatches.

The script:

- rejects `@unchecked Sendable`, `NSLock`, `Task.detached`, and unstructured tasks without an explicit executor in application sources;
- verifies repository-backed use cases and validators remain explicitly isolated;
- verifies stateless environment fallback repositories have nonisolated initializers and feature dependency containers remain nonisolated;
- reads Xcode's effective Debug and Release build settings for both the app and test targets and requires Swift 6, complete strict concurrency, approachable concurrency, and warnings-as-errors;
- rejects effective module-wide `MainActor` default isolation;
- prints the selected Xcode and Swift compiler versions so CI/local compiler differences are visible and diagnosable;
- runs an intentionally invalid Swift 6 transfer fixture and requires the compiler to reject it with a concurrency diagnostic;
- deletes the concurrency verification DerivedData before compilation;
- builds the app in Debug for iOS Simulator;
- builds the app in Release for iOS Simulator;
- runs Debug `build-for-testing` so the test target is compiled under the same strict settings;
- builds Release for a generic iOS device;
- forces `SWIFT_VERSION=6.0`, `SWIFT_STRICT_CONCURRENCY=complete`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, and warning emission on every verification build;
- fails if a build log still contains warnings or a `Sending ... risks causing data races` diagnostic.

The compile gate intentionally does not force `ARCHS` or `ONLY_ACTIVE_ARCH`; it should exercise Xcode's normal build behavior instead of a narrower CI-only architecture override.

CI can only diagnose errors supported by the Xcode/Swift toolchain installed on the runner. The workflow therefore prints both toolchain versions on every run. If local Xcode reports stricter diagnostics than CI, the CI image/toolchain must be upgraded rather than treating the older CI result as authoritative.

## Review checklist for new asynchronous code

- Identify the actor that owns every mutable value.
- Confirm all values crossing an actor boundary conform to `Sendable` without an unsafe escape hatch.
- Confirm non-`Sendable` persistence models are not captured by closures that can leave their actor isolation.
- Confirm cancellation behavior and whether a task can outlive its screen or coordinator.
- Confirm persistence operations execute on the actor that owns their context.
- Add a focused test for ordering, cancellation, or repeated execution when those behaviors matter.

Main-actor dependencies such as `ApplicationSettings` and `CloudKitSchemaChecker` must not be created in default argument expressions. Use explicit main-actor convenience initializers; class initializers that delegate with `self.init` must be declared `convenience`.

`ApplicationSettings` is injected once at the app root and observed through SwiftUI's type-based environment. Views must not create replacement settings services during rendering.

### Foundation notification sources

`NotificationCenter.notifications(named:object:)` requires the source object to be `Sendable`. `NSUbiquitousKeyValueStore` is explicitly non-Sendable on iOS, so iCloud key-value notifications are observed without an object filter and mapped to sendable changed-key arrays before iteration. Do not capture the store in an unstructured task or pass it as the async notification source.
