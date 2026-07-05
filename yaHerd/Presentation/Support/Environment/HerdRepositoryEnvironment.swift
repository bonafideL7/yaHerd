//
//  HerdRepositoryEnvironment.swift
//  yaHerd
//

import SwiftUI

private struct HerdRepositoryKey: EnvironmentKey {
    static let defaultValue: (any HerdRepository)? = nil
}

extension EnvironmentValues {
    var herdRepository: (any HerdRepository)? {
        get { self[HerdRepositoryKey.self] }
        set { self[HerdRepositoryKey.self] = newValue }
    }
}
