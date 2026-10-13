# yaHerd

## Privacy

yaHerd does not collect, sell, or share personal information with the developer or third-party analytics services.

Herd data and app settings are stored locally in yaHerd app data on the user's device. yaHerd does not synchronize herd data through iCloud or send herd data to developer-owned servers.

Deleting the app may remove locally stored yaHerd data according to iOS behavior. Use the app's available export or recovery tools when a local backup is needed.

## Persistent storage and existing-user upgrades

The running app uses a local-only **Core Data** `NSPersistentContainer` backed by `yaHerd.sqlite`. All active feature repositories use the same Core Data store. There is no SwiftData runtime fallback or dual-write path.

Historical SwiftData model sources are retained outside the production target in [LegacySwiftData/](LegacySwiftData/README.md) solely as a record of the old schema. **They are not a data importer.** On a first Core Data launch, recognized legacy SwiftData store files and SQLite sidecars prevent silent creation of an empty replacement store. The app instead enters read-only recovery so those original files can be exported without conversion.

**Existing SwiftData records are not currently imported into Core Data.** Preserving the original storage files does not make their records available in the new runtime. Shipping this replacement as a data-preserving upgrade for devices with legacy data requires separate, explicitly approved import or release handling. Do not delete the only copy of those files.

See [the Core Data replacement execution plan](Core-Data-SwiftData-replacement-execution-plan.md) and [the runtime cutover gate](Info/MILESTONE_10_CORE_DATA_RUNTIME_CUTOVER_GATE.md).

## Read-only recovery mode

If persistent Core Data storage cannot be opened, including when a recognized legacy store blocks first-open initialization, yaHerd attempts to start an **in-memory Core Data** recovery session. Data mutations are blocked. Storage diagnostics, export of recognized local store files and their SQLite journals, and a non-mutating read-only Core Data store check are available. Recovery does **not** load or convert old SwiftData records.

If the in-memory recovery store also fails, yaHerd displays a storage-unavailable screen instead of an operational app. Recovery responsibilities are documented in [Info/ARCHITECTURE.md](Info/ARCHITECTURE.md).

## Swift 6 concurrency

The app and test targets use Swift 6, complete strict-concurrency checking, main-actor default isolation, and warnings-as-errors. Repository engineering and verification rules are documented in [AGENTS.md](AGENTS.md), with concurrency CI configuration in [.github/workflows/swift-concurrency.yml](.github/workflows/swift-concurrency.yml).

## Application settings

User-facing preferences are exposed through one typed, observable `ApplicationSettings` service with validation, key migration, and an in-memory test store.
