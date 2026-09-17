//
//  AppLaunchDiagnostics.swift
//  yaHerd
//

import Foundation

enum AppLaunchStorageMode: String {
    case local
    case recovery
    case unavailable

    var displayName: String {
        switch self {
        case .local:
            "Local"
        case .recovery:
            "Recovery Mode"
        case .unavailable:
            "Storage Unavailable"
        }
    }
}

struct AppLaunchDiagnosticsSnapshot: Equatable {
    let actualStorageMode: AppLaunchStorageMode
    let startupError: String?
}

enum AppLaunchDiagnostics {
    private enum Keys {
        static let actualStorageMode = "diagnostics.actualStorageMode"
        static let startupError = "diagnostics.startupError"
    }

    static func record(
        actualStorageMode: AppLaunchStorageMode,
        startupError: String? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(actualStorageMode.rawValue, forKey: Keys.actualStorageMode)

        if let startupError {
            userDefaults.set(startupError, forKey: Keys.startupError)
        } else {
            userDefaults.removeObject(forKey: Keys.startupError)
        }
    }

    static func snapshot(userDefaults: UserDefaults = .standard) -> AppLaunchDiagnosticsSnapshot {
        let actualRawValue = userDefaults.string(forKey: Keys.actualStorageMode)
        let actualStorageMode = AppLaunchStorageMode(rawValue: actualRawValue ?? "") ?? .local
        let startupError = userDefaults.string(forKey: Keys.startupError)

        return AppLaunchDiagnosticsSnapshot(
            actualStorageMode: actualStorageMode,
            startupError: startupError
        )
    }
}
