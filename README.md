# yaHerd

## Privacy

yaHerd does not collect, sell, or share personal information with the developer or third-party analytics services.

Herd data and app settings are stored locally in yaHerd app data on the user's device. yaHerd does not synchronize herd data through iCloud or send herd data to developer-owned servers.

Deleting the app may remove locally stored yaHerd data according to iOS behavior. Use the app's available export or recovery tools when a local backup is needed.

## Persistent-store migrations

The current SwiftData schema and migration plan are maintained under `yaHerd/Data/Persistence/Schema/`. The planned local-only Core Data replacement is documented in [Core-Data-SwiftData-replacement-execution-plan.md](Core-Data-SwiftData-replacement-execution-plan.md) and [Info/CORE_DATA_CUTOVER.md](Info/CORE_DATA_CUTOVER.md).

## Read-only recovery mode

When persistent SwiftData storage cannot be opened, yaHerd enters a visibly read-only recovery state. Data mutations are blocked; storage diagnostics, store-file export, and an acknowledged repair attempt remain available. Recovery responsibilities are documented in [Info/ARCHITECTURE.md](Info/ARCHITECTURE.md).

## Swift 6 concurrency

The app and test targets use Swift 6, complete strict-concurrency checking, main-actor default isolation, and warnings-as-errors. Repository engineering and verification rules are documented in [AGENTS.md](AGENTS.md), with concurrency CI configuration in [.github/workflows/swift-concurrency.yml](.github/workflows/swift-concurrency.yml).

## Application settings

User-facing preferences are exposed through one typed, observable `ApplicationSettings` service with validation, key migration, and an in-memory test store.
