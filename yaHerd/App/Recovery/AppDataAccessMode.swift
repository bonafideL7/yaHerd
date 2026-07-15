//
//  AppDataAccessMode.swift
//  yaHerd
//

import SwiftUI

enum AppDataAccessMode: Equatable, Sendable {
  case readWrite
  case recoveryReadOnly

  var allowsDataMutations: Bool {
    self == .readWrite
  }

  var isRecoveryMode: Bool {
    self == .recoveryReadOnly
  }
}

private struct AppDataAccessModeKey: EnvironmentKey {
  static let defaultValue = AppDataAccessMode.readWrite
}

extension EnvironmentValues {
  var appDataAccessMode: AppDataAccessMode {
    get { self[AppDataAccessModeKey.self] }
    set { self[AppDataAccessModeKey.self] = newValue }
  }
}

private struct DisableWhenDataReadOnlyModifier: ViewModifier {
  @Environment(\.appDataAccessMode) private var dataAccessMode

  func body(content: Content) -> some View {
    content
      .disabled(!dataAccessMode.allowsDataMutations)
      .opacity(dataAccessMode.allowsDataMutations ? 1 : 0.45)
  }
}

extension View {
  func disabledWhenDataReadOnly() -> some View {
    modifier(DisableWhenDataReadOnlyModifier())
  }
}
