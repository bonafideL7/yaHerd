//
//  AppPreferences.swift
//  yaHerd
//

import Foundation

enum AppPreferenceKey {
    static let syncMode = "syncMode"
}

@MainActor
protocol AppPreferencesProviding: AnyObject {
    var syncMode: SyncMode { get set }
}

@MainActor
protocol AppSettingsSyncing: AnyObject {
    func startIfNeeded(syncMode: SyncMode)
    func stop()
    func deleteCloudSettings() -> Int
}

@MainActor
final class AppPreferences: AppPreferencesProviding {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var syncMode: SyncMode {
        get {
            let rawValue = userDefaults.string(forKey: AppPreferenceKey.syncMode)
            return SyncMode(rawValue: rawValue ?? "") ?? .localOnly
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: AppPreferenceKey.syncMode)
        }
    }
}

enum SyncedAppSettingKey: String, CaseIterable, Sendable {
    case allowHardDelete
    case isDashboardEnabled
    case targetAcresPerHeadDefault
    case usableAcreagePercentDefault
    case recentPastureNames
}

@MainActor
final class AppSettingsSynchronizer: AppSettingsSyncing {
    static let shared = AppSettingsSynchronizer()

    private let userDefaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private let keys: [SyncedAppSettingKey]
    private var observationTasks: [Task<Void, Never>] = []
    private var isApplyingCloudValues = false
    private var isStarted = false

    init(
        userDefaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default,
        keys: [SyncedAppSettingKey] = SyncedAppSettingKey.allCases
    ) {
        self.userDefaults = userDefaults
        self.cloudStore = cloudStore
        self.keys = keys
    }

    isolated deinit {
        stop()
    }

    func startIfNeeded(syncMode: SyncMode) {
        guard syncMode == .iCloud else {
            stop()
            return
        }

        cloudStore.synchronize()
        applyCloudSettingsToLocalDefaults()
        seedMissingCloudSettingsFromLocalDefaults()

        guard !isStarted else { return }
        isStarted = true
        observeChanges()
    }

    func stop() {
        guard isStarted || !observationTasks.isEmpty else { return }

        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        isStarted = false
        isApplyingCloudValues = false
    }

    @discardableResult
    func deleteCloudSettings() -> Int {
        stop()

        let cloudValues = cloudStore.dictionaryRepresentation
        var deletedCount = 0

        for key in keys where cloudValues[key.rawValue] != nil {
            cloudStore.removeObject(forKey: key.rawValue)
            deletedCount += 1
        }

        cloudStore.synchronize()
        return deletedCount
    }

    func applyCloudSettingsToLocalDefaults() {
        isApplyingCloudValues = true
        defer { isApplyingCloudValues = false }

        let cloudValues = cloudStore.dictionaryRepresentation

        for key in keys {
            guard let cloudValue = cloudValues[key.rawValue] else { continue }
            userDefaults.set(cloudValue, forKey: key.rawValue)
        }
    }

    func refreshFromICloudIfStarted() {
        guard isStarted else { return }

        cloudStore.synchronize()
        applyCloudSettingsToLocalDefaults()
    }

    func saveLocalSettingsToICloud() {
        guard isStarted, !isApplyingCloudValues else { return }

        for key in keys {
            guard let localValue = userDefaults.object(forKey: key.rawValue) else { continue }
            cloudStore.set(localValue, forKey: key.rawValue)
        }

        cloudStore.synchronize()
    }

    private func seedMissingCloudSettingsFromLocalDefaults() {
        for key in keys {
            guard cloudStore.object(forKey: key.rawValue) == nil,
                  let localValue = userDefaults.object(forKey: key.rawValue) else {
                continue
            }

            cloudStore.set(localValue, forKey: key.rawValue)
        }

        cloudStore.synchronize()
    }

    private func observeChanges() {
        let localChangesTask = Task { @MainActor [weak self] in
            let changes = NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification
            )
            .map { _ in () }

            for await _ in changes {
                guard !Task.isCancelled else { return }
                self?.saveLocalSettingsToICloud()
            }
        }

        let cloudChangesTask = Task { @MainActor [weak self] in
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

        observationTasks = [localChangesTask, cloudChangesTask]
    }

    private func handleCloudChange(changedKeys: [String]?) {
        guard let changedKeys else {
            applyCloudSettingsToLocalDefaults()
            return
        }

        let syncedKeys = Set(keys.map(\.rawValue))
        guard changedKeys.contains(where: { syncedKeys.contains($0) }) else { return }

        applyCloudSettingsToLocalDefaults()
    }
}
