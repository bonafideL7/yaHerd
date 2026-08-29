//
//  HerdSharingAccess.swift
//  yaHerd
//

enum HerdSharingBridgeConflictResolution: String, Equatable, Sendable {
  case keepOwnerShare
  case keepAcceptedShare

  var retainedLocation: HerdSharingAccess.BridgeLocation {
    switch self {
    case .keepOwnerShare: .ownerPrivateStore
    case .keepAcceptedShare: .acceptedSharedStore
    }
  }
}

struct HerdSharingAccess: Equatable {
  enum BridgeLocation: Equatable {
    case bridgeRecordMissing
    case ownerPrivateStore
    case acceptedSharedStore

    var journalDescription: String {
      switch self {
      case .bridgeRecordMissing: "no bridge record yet"
      case .ownerPrivateStore: "owner private store"
      case .acceptedSharedStore: "accepted shared store"
      }
    }
  }

  enum Permission: Equatable, Sendable {
    case owner
    case readWrite
    case readOnly
    case unknown
  }

  enum CreationState: Equatable {
    case unknown
    case ready
    case existingOwnerShare
    case acceptedParticipantShare
    case unresolvedBridgeRecord
    case conflictingBridgeRecords
    case pendingBridgeOperation
    case ownerStopCleanupPending
    case ownershipConfirmationRequired
    case ownerBridgeVerificationRequired
    case notOwnedByCurrentDevice

    var allowsNewShare: Bool {
      self == .ready
    }

    var primaryActionTitle: String {
      switch self {
      case .ready: "Share Herd"
      case .existingOwnerShare: "Manage Herd Sharing"
      case .acceptedParticipantShare: "Sync Shared Herd"
      case .unresolvedBridgeRecord: "Resume Herd Sharing"
      case .conflictingBridgeRecords: "Resolve Bridge Conflict"
      case .pendingBridgeOperation: "Resolve Sharing State"
      case .ownerStopCleanupPending: "Retry Stop Sharing Cleanup"
      case .ownershipConfirmationRequired: "Confirm Local Ownership"
      case .ownerBridgeVerificationRequired: "Resolve Owner Sharing State"
      case .notOwnedByCurrentDevice: "Detach Stale Shared Herd"
      case .unknown: "Checking Sharing State"
      }
    }
  }

  let bridgeLocation: BridgeLocation
  let permission: Permission
  let participantCount: Int?
  let hasActiveSystemShare: Bool
  let hasConflictingBridgeRecords: Bool
  let creationState: CreationState

  private init(
    bridgeLocation: BridgeLocation,
    permission: Permission,
    participantCount: Int?,
    hasActiveSystemShare: Bool,
    hasConflictingBridgeRecords: Bool,
    creationState: CreationState
  ) {
    self.bridgeLocation = bridgeLocation
    self.permission = permission
    self.participantCount = participantCount
    self.hasActiveSystemShare = hasActiveSystemShare
    self.hasConflictingBridgeRecords = hasConflictingBridgeRecords
    self.creationState = creationState
  }

  var canExportLocalChangesToBridge: Bool {
    guard !hasConflictingBridgeRecords else { return false }
    return switch permission {
    case .owner, .readWrite:
      true
    case .readOnly, .unknown:
      false
    }
  }

  var locationDescription: String {
    if hasConflictingBridgeRecords {
      return "owner and accepted shared stores"
    }
    return bridgeLocation.journalDescription
  }

  var permissionDescription: String {
    switch permission {
    case .owner:
      "owner"
    case .readWrite:
      "read/write"
    case .readOnly:
      "read-only"
    case .unknown:
      "unknown"
    }
  }

  var participantDescription: String {
    guard let participantCount else { return "unknown participants" }
    return participantCount == 1 ? "1 participant" : "\(participantCount) participants"
  }

  func applyingCreationState(_ creationState: CreationState) -> HerdSharingAccess {
    HerdSharingAccess(
      bridgeLocation: bridgeLocation,
      permission: permission,
      participantCount: participantCount,
      hasActiveSystemShare: hasActiveSystemShare,
      hasConflictingBridgeRecords: hasConflictingBridgeRecords,
      creationState: creationState
    )
  }

  static let localOwnerBridgePending = HerdSharingAccess(
    bridgeLocation: .bridgeRecordMissing,
    permission: .owner,
    participantCount: nil,
    hasActiveSystemShare: false,
    hasConflictingBridgeRecords: false,
    creationState: .unknown
  )

  static func ownerPrivateStore(
    participantCount: Int?,
    hasActiveSystemShare: Bool = true
  ) -> HerdSharingAccess {
    HerdSharingAccess(
      bridgeLocation: .ownerPrivateStore,
      permission: .owner,
      participantCount: participantCount,
      hasActiveSystemShare: hasActiveSystemShare,
      hasConflictingBridgeRecords: false,
      creationState: .unknown
    )
  }

  static func acceptedSharedStore(
    permission: Permission,
    participantCount: Int?
  ) -> HerdSharingAccess {
    HerdSharingAccess(
      bridgeLocation: .acceptedSharedStore,
      permission: permission,
      participantCount: participantCount,
      hasActiveSystemShare: false,
      hasConflictingBridgeRecords: false,
      creationState: .unknown
    )
  }

  static func conflictingStores(
    ownerHasActiveSystemShare: Bool,
    participantCount: Int?
  ) -> HerdSharingAccess {
    HerdSharingAccess(
      bridgeLocation: .bridgeRecordMissing,
      permission: .unknown,
      participantCount: participantCount,
      hasActiveSystemShare: ownerHasActiveSystemShare,
      hasConflictingBridgeRecords: true,
      creationState: .unknown
    )
  }
}
