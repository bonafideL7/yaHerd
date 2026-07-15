//
//  HerdShareToken.swift
//  yaHerd
//

import Foundation

nonisolated struct HerdShareToken: Hashable, Codable, Sendable {
  let rawValue: UUID

  init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}
