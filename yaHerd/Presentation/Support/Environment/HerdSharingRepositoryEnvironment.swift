//
//  HerdSharingRepositoryEnvironment.swift
//  yaHerd
//

import SwiftUI

private struct HerdSharingRepositoryKey: EnvironmentKey {
    static let defaultValue: (any HerdSharingRepository)? = nil
}

extension EnvironmentValues {
    var herdSharingRepository: (any HerdSharingRepository)? {
        get { self[HerdSharingRepositoryKey.self] }
        set { self[HerdSharingRepositoryKey.self] = newValue }
    }
}
