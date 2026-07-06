//
//  HerdCollaborationWritePolicy.swift
//  yaHerd
//

import Foundation
import SwiftUI

enum HerdCollaborationWritePolicyError: LocalizedError, Equatable {
  case readOnlySharedHerd(
    reason: SharedDataMutationReason, permission: HerdSharingAccess.Permission)

  var errorDescription: String? {
    switch self {
    case .readOnlySharedHerd(let reason, let permission):
      "This shared herd is \(permission.descriptionForWritePolicy) for the current iCloud account. yaHerd blocked the local \(reason.displayName) edit so it cannot create unsyncable SwiftData changes."
    }
  }
}

final class HerdCollaborationWritePolicy {
  private let lock = NSLock()
  private var access: HerdSharingAccess?
  private(set) var lastUpdatedAt: Date?
  private(set) var lastBlockedMutationReason: SharedDataMutationReason?

  var snapshot: HerdCollaborationWritePolicySnapshot {
    lock.lock()
    defer { lock.unlock() }

    return HerdCollaborationWritePolicySnapshot(
      access: access,
      lastUpdatedAt: lastUpdatedAt,
      lastBlockedMutationReason: lastBlockedMutationReason
    )
  }

  func update(access: HerdSharingAccess) {
    lock.lock()
    self.access = access
    lastUpdatedAt = .now
    if access.allowsLocalMutations {
      lastBlockedMutationReason = nil
    }
    lock.unlock()
  }

  func clearAccess() {
    lock.lock()
    access = nil
    lastUpdatedAt = .now
    lastBlockedMutationReason = nil
    lock.unlock()
  }

  func validateCanWrite(reason: SharedDataMutationReason) throws {
    lock.lock()
    let currentAccess = access
    if currentAccess?.allowsLocalMutations == false {
      lastBlockedMutationReason = reason
    }
    lock.unlock()

    guard let currentAccess, !currentAccess.allowsLocalMutations else { return }
    throw HerdCollaborationWritePolicyError.readOnlySharedHerd(
      reason: reason,
      permission: currentAccess.permission
    )
  }

  @discardableResult
  func canWrite(reason: SharedDataMutationReason) -> Bool {
    do {
      try validateCanWrite(reason: reason)
      return true
    } catch {
      return false
    }
  }
}

struct HerdCollaborationWritePolicySnapshot: Equatable {
  let access: HerdSharingAccess?
  let lastUpdatedAt: Date?
  let lastBlockedMutationReason: SharedDataMutationReason?

  var allowsLocalMutations: Bool {
    access?.allowsLocalMutations ?? true
  }

  var statusDescription: String {
    guard let access else {
      return "No shared-herd write restriction is active."
    }

    if access.allowsLocalMutations {
      return "Local edits are allowed for this \(access.locationDescription) access."
    }

    return
      "Local edits are blocked because this accepted shared herd is \(access.permissionDescription)."
  }
}

extension HerdSharingAccess {
  var allowsLocalMutations: Bool {
    switch bridgeLocation {
    case .bridgeRecordMissing, .ownerPrivateStore:
      true
    case .acceptedSharedStore:
      canExportLocalChangesToBridge
    }
  }
}

extension HerdSharingAccess.Permission {
  fileprivate var descriptionForWritePolicy: String {
    switch self {
    case .owner:
      "owner-accessible"
    case .readWrite:
      "read/write"
    case .readOnly:
      "read-only"
    case .unknown:
      "not writable"
    }
  }
}

private struct HerdCollaborationWritePolicyKey: EnvironmentKey {
  static let defaultValue: HerdCollaborationWritePolicy? = nil
}

extension EnvironmentValues {
  var herdCollaborationWritePolicy: HerdCollaborationWritePolicy? {
    get { self[HerdCollaborationWritePolicyKey.self] }
    set { self[HerdCollaborationWritePolicyKey.self] = newValue }
  }
}
