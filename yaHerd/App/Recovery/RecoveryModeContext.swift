//
//  RecoveryModeContext.swift
//  yaHerd
//

import Foundation
import SwiftUI

struct RecoveryModeContext: Equatable, Sendable {
  let startupError: String
  let enteredAt: Date

  init(
    startupError: String,
    enteredAt: Date = .now
  ) {
    self.startupError = startupError
    self.enteredAt = enteredAt
  }
}

private struct RecoveryModeControllerKey: EnvironmentKey {
  static let defaultValue: RecoveryModeController? = nil
}

extension EnvironmentValues {
  var recoveryModeController: RecoveryModeController? {
    get { self[RecoveryModeControllerKey.self] }
    set { self[RecoveryModeControllerKey.self] = newValue }
  }
}
