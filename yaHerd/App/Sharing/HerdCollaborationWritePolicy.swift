//
//  HerdCollaborationWritePolicy.swift
//  yaHerd
//

import Foundation

enum HerdCollaborationWritePolicyError: LocalizedError, Equatable {
  case recoveryModeReadOnly(reason: SharedDataMutationReason)
  case readOnlySharedHerd(
    reason: SharedDataMutationReason, permission: HerdSharingAccess.Permission)

  var errorDescription: String? {
    switch self {
    case .recoveryModeReadOnly(let reason):
      "yaHerd is running in read-only recovery mode. The \(reason.displayName) change was blocked because data changes cannot be saved."
    case .readOnlySharedHerd(let reason, let permission):
      "This shared herd is \(permission.descriptionForWritePolicy) for the current iCloud account. yaHerd blocked the local \(reason.displayName) edit so it cannot create unsyncable SwiftData changes."
    }
  }
}

/// Main-actor policy for repository mutations backed by the app's main `ModelContext`.
///
/// Validation must remain synchronous so a repository can reject a mutation before touching
/// SwiftData. Main-actor isolation provides the required actor serialization without a lock or an
/// unsafe sendability declaration.
@MainActor
final class HerdCollaborationWritePolicy {
  private let dataAccessMode: AppDataAccessMode
  private let mutationGate: HerdDataMutationGate
  private var access: HerdSharingAccess?
  private var accessRefreshRequestHandler: ((SharedDataMutationReason) -> Void)?
  private var lastAccessRefreshRequestedAt: Date?
  private(set) var lastUpdatedAt: Date?
  private(set) var lastBlockedMutationReason: SharedDataMutationReason?
  private(set) var lastAccessRefreshRequestedReason: SharedDataMutationReason?

  init(
    dataAccessMode: AppDataAccessMode = .readWrite,
    mutationGate: HerdDataMutationGate = HerdDataMutationGate()
  ) {
    self.dataAccessMode = dataAccessMode
    self.mutationGate = mutationGate
  }

  var snapshot: HerdCollaborationWritePolicySnapshot {
    HerdCollaborationWritePolicySnapshot(
      dataAccessMode: dataAccessMode,
      access: access,
      lastUpdatedAt: lastUpdatedAt,
      lastBlockedMutationReason: lastBlockedMutationReason,
      lastAccessRefreshRequestedReason: lastAccessRefreshRequestedReason
    )
  }

  func update(access: HerdSharingAccess) {
    self.access = access
    lastUpdatedAt = .now
    lastAccessRefreshRequestedReason = nil
    if access.allowsLocalMutations {
      lastBlockedMutationReason = nil
    }
  }

  func setAccessRefreshRequestHandler(_ handler: @escaping (SharedDataMutationReason) -> Void) {
    accessRefreshRequestHandler = handler
  }

  func clearAccessRefreshRequestHandler() {
    accessRefreshRequestHandler = nil
  }

  func clearAccess() {
    access = nil
    lastUpdatedAt = .now
    lastBlockedMutationReason = nil
    lastAccessRefreshRequestedReason = nil
  }

  func validateCanWrite(reason: SharedDataMutationReason) throws {
    try mutationGate.validateLocalMutationAllowed(reason: reason)

    guard dataAccessMode.allowsDataMutations else {
      lastBlockedMutationReason = reason
      throw HerdCollaborationWritePolicyError.recoveryModeReadOnly(reason: reason)
    }

    let currentAccess = access
    let refreshRequestHandler: ((SharedDataMutationReason) -> Void)?
    if currentAccess == nil {
      refreshRequestHandler = accessRefreshRequestHandlerIfNeeded(for: reason)
    } else {
      refreshRequestHandler = nil
    }

    if currentAccess?.allowsLocalMutations == false {
      lastBlockedMutationReason = reason
    }

    refreshRequestHandler?(reason)

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

  private func accessRefreshRequestHandlerIfNeeded(
    for reason: SharedDataMutationReason
  ) -> ((SharedDataMutationReason) -> Void)? {
    let now = Date.now
    if let lastAccessRefreshRequestedAt,
      now.timeIntervalSince(lastAccessRefreshRequestedAt) < 10
    {
      return nil
    }

    lastAccessRefreshRequestedAt = now
    lastAccessRefreshRequestedReason = reason
    return accessRefreshRequestHandler
  }
}

struct HerdCollaborationWritePolicySnapshot: Equatable {
  let dataAccessMode: AppDataAccessMode
  let access: HerdSharingAccess?
  let lastUpdatedAt: Date?
  let lastBlockedMutationReason: SharedDataMutationReason?
  let lastAccessRefreshRequestedReason: SharedDataMutationReason?

  var allowsLocalMutations: Bool {
    dataAccessMode.allowsDataMutations && (access?.allowsLocalMutations ?? true)
  }

  var statusDescription: String {
    if dataAccessMode.isRecoveryMode {
      return "Local edits are blocked because yaHerd is running in read-only recovery mode. Data changes cannot be saved."
    }

    guard let access else {
      if let lastAccessRefreshRequestedReason {
        return "Sharing access has not been loaded yet. yaHerd requested a CloudKit access "
          + "refresh before the last \(lastAccessRefreshRequestedReason.displayName) edit attempt."
      }
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
