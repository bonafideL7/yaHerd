# Recovery mode

Recovery mode is entered only when yaHerd cannot open the requested persistent SwiftData store and can still create an in-memory diagnostic container. It is a read-only containment state, not an alternate editing mode.

## Runtime invariants

While recovery mode is active:

- Every SwiftUI scene renders its own red `RECOVERY MODE — READ ONLY` banner at the scene root.
- The Storage Recovery screen is presented by the scene that initiated it through native SwiftUI presentation.
- Recovery presentation does not create a secondary `UIWindow`, search `UIApplication.connectedScenes`, or share presentation state through a singleton overlay.
- The SwiftData recovery configuration is in memory and has `allowsSave` disabled.
- All application repositories validate `AppDataAccessMode` before a mutation and reject writes.
- Create, edit, archive, delete, status, field-check, working-session, and settings mutation controls are disabled or removed.
- The Core Data CloudKit sharing repository is not created.
- Sharing readiness is reported as unavailable.
- Automatic sharing access refresh, mutation-triggered sync, foreground sync, imports, exports to the sharing bridge, and invitation processing are disabled.
- Startup bootstrap and historical data-repair routines do not run against the in-memory container.
- Recovery mode remains active for the entire launch. A successful store-open test does not switch the live app back to writable storage.

Do not add a code path that bypasses the repository write policy or writes directly to the recovery `ModelContext`.

## Diagnostics and export

The Storage Recovery screen shows:

- requested and active storage modes;
- the original startup error;
- in-memory record counts or count failures;
- discovered SwiftData and sharing-bridge store files;
- file count, size, and modification details.

`Export Storage and Diagnostics` creates an uncompressed TAR archive containing:

- `RecoveryDiagnostics.json`;
- a human-readable `README.txt`;
- discoverable SwiftData store, WAL, and SHM files;
- discoverable Core Data sharing-bridge store files.

The archive can contain herd and animal data and must be treated as private. The export is a diagnostic preservation path, not a replacement backup or an assurance that a damaged SQLite store is recoverable.

## Repair attempt

The user must:

1. review the warning;
2. deliberately enable the repair-risk acknowledgment;
3. confirm the destructive repair dialog.

The repair action attempts to open the original persistent store through `ModelContainerFactory` and the production schema migration plan with CloudKit disabled. It does not copy in-memory data into the store, start synchronization, or make the current launch writable. After a successful open test, the user must terminate and relaunch yaHerd.

## Required tests before release

- Force both iCloud and local SwiftData container creation to fail and verify recovery mode starts.
- Open multiple iPad windows and verify every scene shows its own recovery banner.
- Open Storage Recovery from one window and verify only that scene presents the sheet.
- Close, background, and reactivate scenes and verify recovery presentation remains attached to the correct scene without stale windows.
- Verify VoiceOver focus moves into the native recovery sheet and returns to the initiating scene when dismissed.
- Verify every repository mutation fails before touching SwiftData or the sharing bridge.
- Verify `ModelContainerFactory.makeRecoveryContainer()` rejects `ModelContext.save()`.
- Verify automatic and manual sharing/sync entry points are never invoked.
- Verify editing, archive, delete, status, field-check, working-session, and setup controls are disabled or absent.
- Verify diagnostics refresh and the TAR export contains the expected inventory and terminal blocks.
- Verify repair cannot start without acknowledgment and confirmation.
- Verify failed repair leaves the app read-only.
- Verify successful store opening still requires a relaunch before normal editing resumes.
