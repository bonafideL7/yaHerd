# Application settings

`ApplicationSettings` is the only supported API for user-facing application settings. Views and feature models must not declare `@AppStorage`, read `UserDefaults` directly, or repeat setting key strings.

## Components

- `ApplicationSettingCatalog.swift` defines every key, its canonical storage name, legacy aliases, and whether it is device-local or synchronized.
- `ApplicationSettingsStore.swift` contains local/cloud storage ports, `UserDefaults` and in-memory implementations, and key migration support.
- `ApplicationSettings.swift` exposes typed observable properties, defaults, validation, serialization, and normalized persistence.
- `UbiquitousApplicationSettingsCloudStore.swift` isolates Apple's non-Sendable iCloud key-value store behind the main actor.
- `AppSettingsSynchronizer.swift` mirrors only settings classified as `synchronized` through the cloud-store port.

## Classification

Synchronized preferences:

- hard-delete behavior;
- dashboard visibility;
- default target acres per head;
- default usable acreage percentage;
- dismissed home setup suggestions.

Device-local state:

- selected data storage mode;
- recent pasture IDs;
- home setup-section expansion state;
- the temporary legacy recent-pasture-name value used during migration.

The storage mode remains local because enabling CloudKit changes how the persistent store opens on a specific installation. Recent navigation and disclosure state remain local because they describe activity on one device rather than herd policy.

## Adding or changing a setting

1. Add one `ApplicationSettingKey` case.
2. Define its scope and any legacy key aliases in the catalog.
3. Add a typed property, default, decoder, encoder, and validator in `ApplicationSettings`.
4. Add migration and validation tests using `InMemoryApplicationSettingsStore`.
5. Use the injected `ApplicationSettings` instance from SwiftUI environment; do not add `@AppStorage`.
6. When renaming a key, retain the old raw key in `legacyKeys` until all supported releases have crossed the migration.

The architecture verification script rejects new `@AppStorage` declarations and known application-setting key strings outside the catalog. Unit tests use both in-memory local and cloud stores, so migration, validation, classification, and synchronization behavior do not require global defaults or an iCloud account.

## Legacy source-file compatibility

`App/Preferences/AppPreferences.swift` is intentionally retained as a declaration-free compatibility tombstone. When a release archive is copied over an older checkout, it overwrites the previous file that defined `AppSettingsSyncing` and `AppSettingsSynchronizer`. Removing this tombstone can leave those obsolete declarations on disk and cause invalid-redeclaration compiler errors for overlay-style upgrades.
