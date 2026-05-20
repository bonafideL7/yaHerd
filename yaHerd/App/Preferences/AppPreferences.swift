//
//  AppPreferences.swift
//  yaHerd
//

import Foundation

protocol AppPreferencesProviding: AnyObject {
    var syncMode: SyncMode { get set }
}

final class AppPreferences: AppPreferencesProviding {
    private enum Keys {
        static let syncMode = "syncMode"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var syncMode: SyncMode {
        get {
            let rawValue = userDefaults.string(forKey: Keys.syncMode)
            return SyncMode(rawValue: rawValue ?? "") ?? .localOnly
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.syncMode)
        }
    }
}

enum SyncedAppSettingKey: String, CaseIterable {
    case allowHardDelete
    case isDashboardEnabled
    case pregCheckIntervalDays
    case treatmentIntervalDays
    case enablePastureOverstockWarnings
    case pastureCapacity
    case targetAcresPerHeadDefault
    case usableAcreagePercentDefault
    case recentPastureNames
}

final class AppSettingsSynchronizer {
    static let shared = AppSettingsSynchronizer()

    private let userDefaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private let keys: [SyncedAppSettingKey]
    private var observerTokens: [NSObjectProtocol] = []
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

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func startIfNeeded(syncMode: SyncMode) {
        guard syncMode == .iCloud else { return }

        cloudStore.synchronize()
        applyCloudSettingsToLocalDefaults()
        seedMissingCloudSettingsFromLocalDefaults()

        guard !isStarted else { return }
        isStarted = true
        observeChanges()
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
        let localToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveLocalSettingsToICloud()
        }

        let cloudToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudChange(notification)
        }

        observerTokens.append(contentsOf: [localToken, cloudToken])
    }

    private func handleCloudChange(_ notification: Notification) {
        guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            applyCloudSettingsToLocalDefaults()
            return
        }

        let syncedKeys = Set(keys.map(\.rawValue))
        guard changedKeys.contains(where: { syncedKeys.contains($0) }) else { return }

        applyCloudSettingsToLocalDefaults()
    }
}
