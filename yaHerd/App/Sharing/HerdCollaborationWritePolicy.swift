//
//  HerdCollaborationWritePolicy.swift
//  yaHerd
//

import Foundation

enum HerdCollaborationWritePolicyError: LocalizedError, Equatable {
  case recoveryModeReadOnly(reason: SharedDataMutationReason)
  case bridgeConflictRequiresResolution(reason: SharedDataMutationReason)
  case sharingRecoveryPending(reason: SharedDataMutationReason)
  case sharingAccessVerificationRequired(reason: SharedDataMutationReason)
  case ownerSharingStateUnverified(reason: SharedDataMutationReason)
  case participantBridgeUnavailable(reason: SharedDataMutationReason)
  case readOnlySharedHerd(reason: SharedDataMutationReason, permission: HerdSharingAccess.Permission)

  var errorDescription: String? {
    switch self {
    case .recoveryModeReadOnly(let reason):
      "yaHerd is running in read-only recovery mode. The \(reason.displayName) change was blocked because data changes cannot be saved."
    case .bridgeConflictRequiresResolution(let reason):
      "The Herd root exists in both owner and accepted shared bridge stores. yaHerd blocked the local \(reason.displayName) edit until you choose which sharing relationship to keep."
    case .sharingRecoveryPending(let reason):
      "Shared-data recovery is unfinished. yaHerd blocked the local \(reason.displayName) edit until the retained bridge is imported and reconciled."
    case .sharingAccessVerificationRequired(let reason):
      "CloudKit sharing access has not been verified for this launch. yaHerd blocked the local \(reason.displayName) edit until sharing access refreshes successfully."
    case .ownerSharingStateUnverified(let reason):
      "This iCloud account previously owned sharing for this Herd, but the owner bridge is not currently available. yaHerd blocked the local \(reason.displayName) edit until the owner sharing state is recovered or deliberately reset."
    case .participantBridgeUnavailable(let reason):
      "This Herd is known to be an accepted participant copy, but its shared bridge is not currently available. yaHerd blocked the local \(reason.displayName) edit so it cannot create changes with no verified synchronization target."
    case .readOnlySharedHerd(let reason, let permission):
      "This shared herd is \(permission.descriptionForWritePolicy) for the current iCloud account. yaHerd blocked the local \(reason.displayName) edit so it cannot create unsyncable SwiftData changes."
    }
  }
}

@MainActor
final class HerdCollaborationWritePolicy {
  private let dataAccessMode: AppDataAccessMode
  private let mutationGate: HerdDataMutationGate
  private var access: HerdSharingAccess?
  private var requiresVerifiedAccessBeforeWrite: Bool
  private var accessRefreshRequestHandler: ((SharedDataMutationReason) -> Void)?
  private(set) var sharingStateGeneration: UInt64 = 0
  private var lastAccessRefreshRequestedAt: Date?
  private(set) var lastUpdatedAt: Date?
  private(set) var lastBlockedMutationReason: SharedDataMutationReason?
  private(set) var lastAccessRefreshRequestedReason: SharedDataMutationReason?

  init(
    dataAccessMode: AppDataAccessMode = .readWrite,
    mutationGate: HerdDataMutationGate = HerdDataMutationGate(),
    requiresInitialAccessVerification: Bool = false
  ) {
    self.dataAccessMode = dataAccessMode
    self.mutationGate = mutationGate
    requiresVerifiedAccessBeforeWrite = requiresInitialAccessVerification
  }

  var snapshot: HerdCollaborationWritePolicySnapshot {
    HerdCollaborationWritePolicySnapshot(
      dataAccessMode: dataAccessMode,
      access: access,
      requiresVerifiedAccessBeforeWrite: requiresVerifiedAccessBeforeWrite,
      lastUpdatedAt: lastUpdatedAt,
      lastBlockedMutationReason: lastBlockedMutationReason,
      lastAccessRefreshRequestedReason: lastAccessRefreshRequestedReason
    )
  }

  var dataMutationGate: HerdDataMutationGate { mutationGate }

  func update(access: HerdSharingAccess) {
    sharingStateGeneration &+= 1
    self.access = access
    requiresVerifiedAccessBeforeWrite = false
    lastUpdatedAt = .now
    lastAccessRefreshRequestedReason = nil
    if access.allowsLocalMutations { lastBlockedMutationReason = nil }
  }

  func setAccessRefreshRequestHandler(_ handler: @escaping (SharedDataMutationReason) -> Void) {
    accessRefreshRequestHandler = handler
  }

  func clearAccessRefreshRequestHandler() { accessRefreshRequestHandler = nil }

  func clearAccess() {
    clearAccess(requiresVerificationBeforeWrite: requiresVerifiedAccessBeforeWrite)
  }

  /// Used when synchronization or another authoritative access read fails after sharing state may
  /// have changed. Losing the cached access must never turn an unknown recovery state into an
  /// implicit write allow.
  func clearAccessAfterFailedSynchronization() {
    clearAccess(requiresVerificationBeforeWrite: true)
  }

  func clearAccessAfterFailedSynchronization(ifGenerationIsStill generation: UInt64) {
    guard sharingStateGeneration == generation else { return }
    clearAccessAfterFailedSynchronization()
  }

  private func clearAccess(requiresVerificationBeforeWrite: Bool) {
    sharingStateGeneration &+= 1
    access = nil
    requiresVerifiedAccessBeforeWrite = requiresVerificationBeforeWrite
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

    if currentAccess?.allowsLocalMutations == false || requiresVerifiedAccessBeforeWrite {
      lastBlockedMutationReason = reason
    }
    refreshRequestHandler?(reason)

    if currentAccess == nil, requiresVerifiedAccessBeforeWrite {
      throw HerdCollaborationWritePolicyError.sharingAccessVerificationRequired(reason: reason)
    }

    guard let currentAccess, !currentAccess.allowsLocalMutations else { return }
    if currentAccess.hasConflictingBridgeRecords {
      throw HerdCollaborationWritePolicyError.bridgeConflictRequiresResolution(reason: reason)
    }
    if currentAccess.creationState == .pendingBridgeOperation {
      throw HerdCollaborationWritePolicyError.sharingRecoveryPending(reason: reason)
    }
    if currentAccess.creationState == .ownerStopCleanupPending {
      throw HerdCollaborationWritePolicyError.ownerSharingStateUnverified(reason: reason)
    }
    if currentAccess.creationState == .ownerBridgeVerificationRequired {
      throw HerdCollaborationWritePolicyError.ownerSharingStateUnverified(reason: reason)
    }
    if currentAccess.creationState == .notOwnedByCurrentDevice {
      throw HerdCollaborationWritePolicyError.participantBridgeUnavailable(reason: reason)
    }
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
    { return nil }
    lastAccessRefreshRequestedAt = now
    lastAccessRefreshRequestedReason = reason
    return accessRefreshRequestHandler
  }
}

struct HerdCollaborationWritePolicySnapshot: Equatable {
  let dataAccessMode: AppDataAccessMode
  let access: HerdSharingAccess?
  let requiresVerifiedAccessBeforeWrite: Bool
  let lastUpdatedAt: Date?
  let lastBlockedMutationReason: SharedDataMutationReason?
  let lastAccessRefreshRequestedReason: SharedDataMutationReason?

  var allowsLocalMutations: Bool {
    dataAccessMode.allowsDataMutations
      && !requiresVerifiedAccessBeforeWrite
      && (access?.allowsLocalMutations ?? true)
  }

  var statusDescription: String {
    if dataAccessMode.isRecoveryMode {
      return "Local edits are blocked because yaHerd is running in read-only recovery mode. Data changes cannot be saved."
    }
    guard let access else {
      if requiresVerifiedAccessBeforeWrite {
        return "Local edits are blocked until CloudKit sharing access is verified successfully."
      }
      if let lastAccessRefreshRequestedReason {
        return "Sharing access has not been loaded yet. yaHerd requested a CloudKit access refresh before the last \(lastAccessRefreshRequestedReason.displayName) edit attempt."
      }
      return "No shared-herd write restriction is active."
    }
    if access.hasConflictingBridgeRecords {
      return "Local edits are blocked because the Herd root exists in both owner and accepted shared bridge stores. Resolve the bridge conflict first."
    }
    if access.creationState == .pendingBridgeOperation {
      return "Local edits are blocked until the pending shared-data import or reconciliation is recovered."
    }
    if access.creationState == .ownerStopCleanupPending {
      return "Local edits are blocked because Stop Sharing finished remotely but the local owner bridge still requires cleanup."
    }
    if access.creationState == .ownerBridgeVerificationRequired {
      return "Local edits are blocked because this iCloud account previously established owner sharing but the owner bridge is not currently available."
    }
    if access.creationState == .notOwnedByCurrentDevice {
      return "Local edits are blocked because this Herd is known to be an accepted participant copy but its shared bridge is not currently available."
    }
    if access.allowsLocalMutations {
      return "Local edits are allowed for this \(access.locationDescription) access."
    }
    return "Local edits are blocked because this accepted shared herd is \(access.permissionDescription)."
  }
}

extension HerdSharingAccess {
  var allowsLocalMutations: Bool {
    guard !hasConflictingBridgeRecords,
      creationState != .pendingBridgeOperation,
      creationState != .ownerStopCleanupPending,
      creationState != .ownerBridgeVerificationRequired,
      creationState != .notOwnedByCurrentDevice
    else { return false }
    return switch bridgeLocation {
    case .bridgeRecordMissing, .ownerPrivateStore: true
    case .acceptedSharedStore: canExportLocalChangesToBridge
    }
  }
}

extension HerdSharingAccess.Permission {
  fileprivate var descriptionForWritePolicy: String {
    switch self {
    case .owner: "owner-accessible"
    case .readWrite: "read/write"
    case .readOnly: "read-only"
    case .unknown: "not writable"
    }
  }
}
