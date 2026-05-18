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
