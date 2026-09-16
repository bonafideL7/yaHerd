Privacy Policy

yaHerd does not collect, sell, or share personal information with the developer or third-party analytics services.

Herd data and app settings are stored locally in yaHerd app data on the user's device. yaHerd does not synchronize herd data through iCloud or send herd data to developer-owned servers.

Deleting the app may remove locally stored yaHerd data according to iOS behavior. Use the app's available export or recovery tools when a local backup is needed.

## Persistent-store migrations

SwiftData schema releases, migration rules, and required upgrade tests are documented in [MIGRATIONS.md](MIGRATIONS.md).

## Read-only recovery mode

When persistent SwiftData storage cannot be opened, yaHerd enters a visibly read-only recovery state. Data mutations are blocked; storage diagnostics, a store-file export, and an acknowledged repair attempt are available. See [RECOVERY_MODE.md](RECOVERY_MODE.md).

## Swift 6 concurrency

The app and test targets use Swift 6, complete strict-concurrency checking, main-actor default isolation, and warnings-as-errors. Main-context repositories are explicitly main-actor isolated. The CI policy and review rules are documented in [CONCURRENCY.md](CONCURRENCY.md).

## Application settings

User-facing preferences are exposed through one typed, observable `ApplicationSettings` service with validation, key migration, and an in-memory test store. See [APPLICATION_SETTINGS.md](APPLICATION_SETTINGS.md).
