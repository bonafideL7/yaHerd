//
//  AppLaunchDiagnostics.swift
//  yaHerd
//

import Foundation

enum AppLaunchStorageMode: String {
    case localOnly
    case iCloud
    case recovery

    var displayName: String {
        switch self {
        case .localOnly:
            "Local Only"
        case .iCloud:
            "iCloud Sync"
        case .recovery:
            "Recovery Mode"
        }
    }
}

struct AppLaunchDiagnosticsSnapshot: Equatable {
    let requestedSyncMode: SyncMode
    let actualStorageMode: AppLaunchStorageMode
    let cloudKitOpened: Bool
    let startupError: String?
}

enum AppLaunchDiagnostics {
    private enum Keys {
        static let requestedSyncMode = "diagnostics.requestedSyncMode"
        static let actualStorageMode = "diagnostics.actualStorageMode"
        static let cloudKitOpened = "diagnostics.cloudKitOpened"
        static let startupError = "diagnostics.startupError"
    }

    static func record(
        requestedSyncMode: SyncMode,
        actualStorageMode: AppLaunchStorageMode,
        cloudKitOpened: Bool,
        startupError: String? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(requestedSyncMode.rawValue, forKey: Keys.requestedSyncMode)
        userDefaults.set(actualStorageMode.rawValue, forKey: Keys.actualStorageMode)
        userDefaults.set(cloudKitOpened, forKey: Keys.cloudKitOpened)

        if let startupError {
            userDefaults.set(startupError, forKey: Keys.startupError)
        } else {
            userDefaults.removeObject(forKey: Keys.startupError)
        }
    }

    static func snapshot(userDefaults: UserDefaults = .standard) -> AppLaunchDiagnosticsSnapshot {
        let requestedRawValue = userDefaults.string(forKey: Keys.requestedSyncMode)
        let actualRawValue = userDefaults.string(forKey: Keys.actualStorageMode)

        let requestedSyncMode = SyncMode(rawValue: requestedRawValue ?? "") ?? .localOnly
        let actualStorageMode = AppLaunchStorageMode(rawValue: actualRawValue ?? "") ?? .localOnly
        let cloudKitOpened = userDefaults.bool(forKey: Keys.cloudKitOpened)
        let startupError = userDefaults.string(forKey: Keys.startupError)

        return AppLaunchDiagnosticsSnapshot(
            requestedSyncMode: requestedSyncMode,
            actualStorageMode: actualStorageMode,
            cloudKitOpened: cloudKitOpened,
            startupError: startupError
        )
    }
}
