
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
- enforces the public-ID recovery invariant that `RecoveryMutation` stores value-only mutation coordinates and may not reintroduce escaping `applyFinal`/`applyBackup` closures that capture SwiftData-backed nodes;
- reads Xcode's effective build settings and requires Swift 6, complete strict concurrency, approachable concurrency, and warnings-as-errors for the configurations being compiled;
- rejects effective module-wide `MainActor` default isolation;
- prints the selected Xcode and Swift compiler versions so CI/local compiler differences are visible and diagnosable;
- runs an intentionally invalid actor-retained non-`Sendable` boundary access and requires the compiler to reject it with a concurrency diagnostic;
- builds the app in Debug for iOS Simulator on ordinary pull-request verification;
- runs the broader Release simulator, Debug build-for-testing, and Release generic-device builds only during full verification, such as `main` or an explicit manual full run;
- disables the compiler index store during verification builds;
- preserves DerivedData by default so routine verification does not pay for an unnecessary clean build; clean verification remains available explicitly;
- uses the verified app/test target settings during builds rather than globally overriding Swift settings, which would incorrectly promote warnings from third-party Swift packages to errors;
- fails any app or test compilation that emits concurrency warnings because those targets have warnings-as-errors enabled.

The compile gate intentionally does not force `ARCHS` or `ONLY_ACTIVE_ARCH`; it should exercise Xcode's normal build behavior instead of a narrower CI-only architecture override.

CI can only diagnose errors supported by the Xcode/Swift toolchain installed on the runner. The workflow therefore prints both toolchain versions on every run. Where a known safety invariant can be expressed structurally, such as the value-only recovery mutation representation, the script enforces that invariant independently of compiler version rather than assuming an older compiler understands a newer isolation diagnostic.

## Review checklist for new asynchronous code

- Identify the actor that owns every mutable value.
- Confirm all values crossing an actor boundary conform to `Sendable` without an unsafe escape hatch.
- Confirm non-`Sendable` persistence models are not captured by closures that can leave their actor isolation.
- Confirm cancellation behavior and whether a task can outlive its screen or coordinator.
- Confirm persistence operations execute on the actor that owns their context.
- Add a focused test for ordering, cancellation, or repeated execution when those behaviors matter.

Main-actor dependencies such as `ApplicationSettings` and `CloudKitSchemaChecker` must not be created in default argument expressions. Use explicit main-actor convenience initializers; class initializers that delegate with `self.init` must be declared `convenience`.

`ApplicationSettings` is injected once at the app root and observed through SwiftUI's type-based environment. Views must not create replacement settings services during rendering.
