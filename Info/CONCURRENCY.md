# Swift 6 concurrency policy

yaHerd builds in Swift 6 language mode with complete strict-concurrency checking. Concurrency warnings are build failures in both local Xcode builds and CI.

## Build settings

The project-level Debug and Release configurations set:

- `SWIFT_VERSION = 6.0` on the app and test targets.
- `SWIFT_STRICT_CONCURRENCY = complete`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.

The main-actor default is intentional. yaHerd is a SwiftUI application whose primary repositories use `ModelContainer.mainContext`. Repository protocols are also explicitly `@MainActor` so the persistence boundary remains clear even if a target's default actor isolation changes later.

## Isolation rules

1. SwiftData models and repositories that use the main `ModelContext` stay on `MainActor`.
2. UI coordinators, observable state, collaboration write policy, and mutation-sync scheduling stay on `MainActor`.
3. Synchronous use cases that orchestrate repository calls are explicitly `@MainActor`. Do not rely only on the target's default actor-isolation setting; the annotation documents and enforces the persistence boundary at the declaration site.
4. Repository-backed validators are `@MainActor` because their duplicate checks call main-context repositories. Pure validation helpers may be `nonisolated` only when they do not capture repository state.
5. SwiftUI `EnvironmentKey.defaultValue` is a synchronous nonisolated requirement. Stateless fallback implementations of main-actor repository protocols must expose a nonisolated fallback initializer so the key can construct them without weakening repository method isolation. Feature dependency containers are declared `nonisolated struct` so they can hold main-actor repository references and still be constructed for an environment default under target-wide `MainActor` isolation. Repository methods remain main-actor isolated.
6. A type must not use `@unchecked Sendable` to silence a compiler error. Redesign its ownership or isolate it to an actor.
7. Do not move `ModelContext`, managed SwiftData models, `NSManagedObject`, or CloudKit sharing metadata across actors.
8. Background work must operate on immutable `Sendable` snapshots and return immutable results to `MainActor` for persistence.
9. Tasks launched from views or UI coordinators must declare `@MainActor` when they mutate UI or repository state.
10. Long-lived tasks must be stored, canceled when superseded, and avoid strongly retaining their owner.
11. Do not introduce lock-backed mutable state managers. Use an actor or an appropriate global actor.

## Collaboration subsystem

`HerdSharingMutationSyncScheduler` and `HerdCollaborationWritePolicy` previously protected mutable state with `NSLock`; the scheduler also declared `@unchecked Sendable`. Both are now main-actor-isolated state machines. This matches the actor that owns the main SwiftData context and the sharing sync coordinator.

The Core Data sharing bridge remains main-actor isolated because its import/export transaction includes the main SwiftData context. A future background implementation must first convert SwiftData and Core Data records into `Sendable` snapshots and must not pass managed objects between executors.

## CI release gate

`.github/workflows/swift-concurrency.yml` runs `Scripts/verify-concurrency.sh`. The script:

- rejects `@unchecked Sendable`, `NSLock`, `Task.detached`, and unstructured tasks without an explicit executor in application sources;
- verifies that repository-backed use cases and validators remain explicitly `@MainActor`;
- verifies that stateless environment fallback repositories have nonisolated initializers and feature dependency containers remain nonisolated;
- verifies the required Swift 6 project settings;
- compiles the app and test target with warnings treated as errors using `xcodebuild build-for-testing`.

Any concurrency warning therefore fails the pull request build.

## Review checklist for new asynchronous code

- Identify the actor that owns every mutable value.
- Confirm all values crossing an actor boundary conform to `Sendable` without an unsafe escape hatch.
- Confirm cancellation behavior and whether a task can outlive its screen or coordinator.
- Confirm persistence operations execute on the actor that owns their context.
- Add a focused test for ordering, cancellation, or repeated execution when those behaviors matter.

- Main-actor dependencies such as `ApplicationSettings` and `CloudKitSchemaChecker` must not be created in default argument expressions. Use explicit main-actor convenience initializers; class initializers that delegate with `self.init` must be declared `convenience`.
- `ApplicationSettings` is injected once at the app root and observed through SwiftUI's type-based environment. Views must not create replacement settings services during rendering.

### Foundation notification sources

`NotificationCenter.notifications(named:object:)` requires the source object to be `Sendable`. `NSUbiquitousKeyValueStore` is explicitly non-Sendable on iOS, so iCloud key-value notifications are observed without an object filter and mapped to sendable changed-key arrays before iteration. Do not capture the store in an unstructured task or pass it as the async notification source.
