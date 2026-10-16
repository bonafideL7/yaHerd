# yaHerd

## Privacy

yaHerd does not collect, sell, or share personal information with the developer or third-party analytics services.

Herd data and app settings are stored locally in yaHerd app data on the user's device. yaHerd does not synchronize herd data through iCloud or send herd data to developer-owned servers.

Deleting the app may remove locally stored yaHerd data according to iOS behavior. Use the app's available export or recovery tools when a local backup is needed.

## Persistent storage and first launch

The running app uses a local-only **Core Data** `NSPersistentContainer` backed by `yaHerd.sqlite`. All active feature repositories use the same Core Data store. There is no SwiftData runtime fallback or dual-write path.

The app has not launched. There is no legacy user data to migrate and no SwiftData import, conversion, compatibility or upgrade support. First launch initializes the local Core Data store directly. Obsolete SwiftData-named files are not read, exported or migrated; they do not block startup. Core Data failures are handled separately by read-only recovery.

See [the implemented architecture](Info/ARCHITECTURE.md), [the final Core Data contract audit](Info/MILESTONE_12_FINAL_CORE_DATA_CONTRACT_AUDIT_MATRIX.md) and [the historical implementation plan](Core-Data-SwiftData-replacement-execution-plan.md).

## Read-only recovery mode

If persistent Core Data storage cannot be opened, yaHerd attempts to start an **in-memory Core Data** recovery session. Data mutations are blocked. Storage diagnostics, export of the Core Data SQLite store and its journals, and a non-mutating read-only Core Data store check remain available. Recovery does not import data from another persistence system.

If the in-memory recovery store also fails, yaHerd displays a storage-unavailable screen instead of an operational app. Recovery responsibilities are documented in [Info/ARCHITECTURE.md](Info/ARCHITECTURE.md).

## Swift 6 concurrency

The app and test targets use Swift 6, complete strict-concurrency checking, main-actor default isolation, and warnings-as-errors. Repository engineering and verification rules are documented in [AGENTS.md](AGENTS.md), with concurrency CI configuration in [.github/workflows/swift-concurrency.yml](.github/workflows/swift-concurrency.yml).

## Application settings

User-facing preferences are exposed through one typed, observable `ApplicationSettings` service with validation, key migration, and an in-memory test store.
