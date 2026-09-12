import Foundation

@MainActor
protocol AppSettingsSyncing: AnyObject {
    func startIfNeeded(syncMode: SyncMode)
    func stop()
    func refreshFromICloudIfStarted()
    func deleteCloudSettings() -> Int
}

@MainActor
final class AppSettingsSynchronizer: AppSettingsSyncing {
    private let settings: ApplicationSettings
    private let cloudStore: any ApplicationSettingsCloudStore
    private let keys: [ApplicationSettingKey]
    private var cloudObservationTask: Task<Void, Never>?
    private var compatibilityCloudObservationTask: Task<Void, Never>?
    private var isApplyingCloudValues = false
    private var isStarted = false

    convenience init(settings: ApplicationSettings) {
        self.init(
            settings: settings,
            cloudStore: UbiquitousApplicationSettingsCloudStore(),
            keys: ApplicationSettingsCatalog.synchronizedKeys
        )
    }

    init(
        settings: ApplicationSettings,
        cloudStore: any ApplicationSettingsCloudStore,
        keys: [ApplicationSettingKey]
    ) {
        self.settings = settings
        self.cloudStore = cloudStore
        self.keys = keys

        // Intentionally do not touch NSUbiquitousKeyValueStore or start observation here.
        // AppSettingsSynchronizer is created before SwiftUI's first frame, so all iCloud work
        // must remain deferred until startIfNeeded() runs from RunningAppView post-launch setup.
    }

    isolated deinit {
        stop()
    }

    func startIfNeeded(syncMode: SyncMode) {
        guard syncMode == .iCloud else {
            stop()
            return
        }

        migrateCloudKeys()
        applyCloudSettingsToApplicationSettings()
        seedMissingCloudSettingsFromLocalSettings()

        guard !isStarted else { return }
        isStarted = true
        settings.setPersistedChangeHandler { [weak self] key in
            self?.saveLocalSettingToICloud(key)
        }
        observeCloudChanges()
        observeCompatibilityCloudChanges()
    }

    func stop() {
        cloudObservationTask?.cancel()
        cloudObservationTask = nil
        compatibilityCloudObservationTask?.cancel()
        compatibilityCloudObservationTask = nil
        settings.setPersistedChangeHandler(nil)
        isStarted = false
        isApplyingCloudValues = false
    }

    func refreshFromICloudIfStarted() {
        guard isStarted else { return }
        migrateCloudKeys()
        applyCloudSettingsToApplicationSettings()
    }

    @discardableResult
    func deleteCloudSettings() -> Int {
        stop()

        var deletedCount = 0
        let storedKeys = keys.flatMap { [$0.rawValue] + $0.legacyKeys }
            + ApplicationSettingsCatalog.deprecatedCloudKeys
            + [ApplicationSettingsCatalog.schemaVersionKey]
        for storedKey in Set(storedKeys) {
            guard cloudStore.object(forKey: storedKey) != nil else { continue }
            cloudStore.removeObject(forKey: storedKey)
            deletedCount += 1
        }

        // Compatibility tombstones are safety metadata, not user preferences.
        // Keep them in place while older supported releases may still exist.
        publishCompatibilityCloudTombstones()
        cloudStore.synchronize()
        return deletedCount
    }

    private func migrateCloudKeys() {
        ApplicationSettingsKeyMigrator.migrate(
            keys: keys,
            read: { cloudStore.object(forKey: $0) },
            write: { cloudStore.set($1, forKey: $0) },
            remove: { cloudStore.removeObject(forKey: $0) }
        )
        purgeDeprecatedCloudKeys()
        publishCompatibilityCloudTombstones()
    }

    private func purgeDeprecatedCloudKeys() {
        for deprecatedKey in ApplicationSettingsCatalog.deprecatedCloudKeys {
            cloudStore.removeObject(forKey: deprecatedKey)
        }
    }

    private func publishCompatibilityCloudTombstones() {
        for (key, value) in ApplicationSettingsCatalog.compatibilityCloudBooleanTombstones {
            cloudStore.set(value, forKey: key)
        }
    }

    private func applyCloudSettingsToApplicationSettings() {
        isApplyingCloudValues = true
        defer { isApplyingCloudValues = false }

        for key in keys {
            guard let value = cloudStore.object(forKey: key.rawValue) else { continue }
            settings.applyExternalValue(value, for: key)
            if let normalizedValue = settings.encodedValue(for: key) {
                cloudStore.set(normalizedValue, forKey: key.rawValue)
            }
        }
    }

    private func seedMissingCloudSettingsFromLocalSettings() {
        for key in keys {
            guard cloudStore.object(forKey: key.rawValue) == nil,
                  let value = settings.encodedValue(for: key) else {
                continue
            }
            cloudStore.set(value, forKey: key.rawValue)
        }
    }

    private func saveLocalSettingToICloud(_ key: ApplicationSettingKey) {
        guard isStarted,
              !isApplyingCloudValues,
              keys.contains(key),
              let value = settings.encodedValue(for: key) else {
            return
        }

        cloudStore.set(value, forKey: key.rawValue)
    }

    private func observeCloudChanges() {
        cloudObservationTask = Task<Void, Never> { @MainActor [weak self] in
            let changes = NotificationCenter.default.notifications(
                named: NSUbiquitousKeyValueStore.didChangeExternallyNotification
            )
            .map { notification -> [String]? in
                notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            }

            for await changedKeys in changes {
                guard !Task.isCancelled else { return }
                self?.handleCloudChange(changedKeys: changedKeys)
            }
        }
    }

    private func observeCompatibilityCloudChanges() {
        guard compatibilityCloudObservationTask == nil else { return }
        compatibilityCloudObservationTask = Task<Void, Never> { @MainActor [weak self] in
            let changes = NotificationCenter.default.notifications(
                named: NSUbiquitousKeyValueStore.didChangeExternallyNotification
            )
            .map { notification -> [String]? in
                notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            }

            for await changedKeys in changes {
                guard !Task.isCancelled else { return }
                self?.handleCompatibilityCloudChange(changedKeys: changedKeys)
            }
        }
    }

    private func handleCompatibilityCloudChange(changedKeys: [String]?) {
        let safetyKeys = Set(ApplicationSettingsCatalog.compatibilityCloudBooleanTombstones.keys)
            .union(ApplicationSettingsCatalog.deprecatedCloudKeys)

        if let changedKeys,
           !changedKeys.contains(where: safetyKeys.contains) {
            return
        }

        purgeDeprecatedCloudKeys()
        publishCompatibilityCloudTombstones()
    }

    private func handleCloudChange(changedKeys: [String]?) {
        migrateCloudKeys()

        guard let changedKeys else {
            applyCloudSettingsToApplicationSettings()
            return
        }

        let relevantKeys = Set(keys.flatMap { [$0.rawValue] + $0.legacyKeys })
        guard changedKeys.contains(where: relevantKeys.contains) else { return }
        applyCloudSettingsToApplicationSettings()
    }
}
