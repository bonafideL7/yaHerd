Privacy Policy

yaHerd does not collect, sell, or share personal information with the developer or third-party analytics services.

Herd data is stored locally on the user's device by default. If iCloud Sync is enabled, herd data and supported app settings are mirrored through the user's private iCloud account using Apple CloudKit so the same data can be available on the user's Apple devices. yaHerd does not send herd data to developer-owned servers.

Users can keep yaHerd in Local Only mode, disable iCloud Sync, or delete yaHerd iCloud sync data from the app's sync diagnostics tools where available. Deleting the app or disabling iCloud features may affect locally stored or synced data according to Apple's iOS and iCloud behavior.

## Persistent-store migrations

SwiftData schema releases, migration rules, and required upgrade tests are documented in [MIGRATIONS.md](MIGRATIONS.md).

### Collaboration persistence release gate

CloudKit collaboration uses a transitional SwiftData/Core Data bridge. Any change to shared models, import/export order, deletion handling, or conflict restoration requires the failure-injection tests and physical two-device/separate-Apple-ID test matrix documented in `SHARING_BRIDGE_RELIABILITY.md`.
## Read-only recovery mode

When persistent SwiftData storage cannot be opened, yaHerd enters a visibly read-only recovery state. Data mutations, sharing, and synchronization are blocked; storage diagnostics, a store-file export, and an acknowledged repair attempt are available. See [RECOVERY_MODE.md](RECOVERY_MODE.md).

## Swift 6 concurrency

The app and test targets use Swift 6, complete strict-concurrency checking, main-actor default isolation, and warnings-as-errors. Main-context repositories and collaboration state are explicitly main-actor isolated. The CI policy and review rules are documented in [CONCURRENCY.md](CONCURRENCY.md).

## Application settings

User-facing preferences are exposed through one typed, observable `ApplicationSettings` service with validation, local-versus-iCloud classification, key migration, and an in-memory test store. See [APPLICATION_SETTINGS.md](APPLICATION_SETTINGS.md).
