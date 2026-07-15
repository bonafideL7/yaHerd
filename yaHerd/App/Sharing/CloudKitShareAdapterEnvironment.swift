//
//  CloudKitShareAdapterEnvironment.swift
//  yaHerd
//

import SwiftUI

private struct CloudKitShareAdapterKey: EnvironmentKey {
  static let defaultValue: CloudKitShareAdapter? = nil
}

extension EnvironmentValues {
  var cloudKitShareAdapter: CloudKitShareAdapter? {
    get { self[CloudKitShareAdapterKey.self] }
    set { self[CloudKitShareAdapterKey.self] = newValue }
  }
}
