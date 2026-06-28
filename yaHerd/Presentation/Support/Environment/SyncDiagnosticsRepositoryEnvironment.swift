//
//  SyncDiagnosticsRepositoryEnvironment.swift
//  yaHerd
//

import SwiftUI

private struct SyncDiagnosticsRepositoryKey: EnvironmentKey {
    static let defaultValue: (any SyncDiagnosticsRepository)? = nil
}

extension EnvironmentValues {
    var syncDiagnosticsRepository: (any SyncDiagnosticsRepository)? {
        get { self[SyncDiagnosticsRepositoryKey.self] }
        set { self[SyncDiagnosticsRepositoryKey.self] = newValue }
    }
}
