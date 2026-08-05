//
//  HerdSharingAccess.swift
//  yaHerd
//

struct HerdSharingAccess: Equatable {
  enum BridgeLocation: Equatable {
    case bridgeRecordMissing
    case ownerPrivateStore
    case acceptedSharedStore
  }

  enum Permission: Equatable {
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
    case pendingBridgeOperation
    case notOwnedByCurrentDevice

    var allowsNewShare: Bool {
      self == .ready
    }

    var primaryActionTitle: String {
      switch self {
      case .unknown:
        "Checking Sharing State"
      case .ready:
        "Share Herd"
      case .existingOwnerShare:
        "Manage Herd Sharing"
      case .acceptedParticipantShare:
        "Sync Shared Herd"
      case .unresolvedBridgeRecord, .pendingBridgeOperation:
        "Resolve Sharing State"
      case .notOwnedByCurrentDevice:
        "Sharing Unavailable"
      }
    }

    var primaryActionSystemImage: String {
      switch self {
      case .unknown:
        "hourglass"
      case .ready:
        "square.and.arrow.up"
      case .existingOwnerShare:
        "person.2.badge.gearshape"
      case .acceptedParticipantShare:
        "arrow.triangle.2.circlepath.icloud"
      case .unresolvedBridgeRecord, .pendingBridgeOperation:
        "arrow.triangle.2.circlepath.icloud"
      case .notOwnedByCurrentDevice:
        "person.crop.circle.badge.exclamationmark"
      }
    }

    var message: String {
      switch self {
      case .unknown:
        "Refresh sharing access before creating or managing a CloudKit share."
      case .ready:
        "No existing share, participant bridge, unresolved bridge record, or pending bridge operation was found. This device owns the local herd data and can create a new share."
      case .existingOwnerShare:
        "This herd already has an owner CloudKit share. Open sharing management instead of creating another share."
      case .acceptedParticipantShare:
        "This device participates in an accepted CloudKit share. Synchronize the shared herd instead of creating a second share."
      case .unresolvedBridgeRecord:
        "A bridge record exists without a valid owner share. Synchronize or repair the bridge before attempting to create a share."
      case .pendingBridgeOperation:
        "A previous bridge import, export, or reconciliation operation is unfinished. Resolve it before creating a share."
      case .notOwnedByCurrentDevice:
        "This device cannot prove ownership of the local herd root. It cannot create a CloudKit share for data owned by another device or participant."
      }
    }
  }

  let bridgeLocation: BridgeLocation
  let permission: Permission
  let participantCount: Int?
  let hasActiveSystemShare: Bool
  let creationState: CreationState

  private init(
    bridgeLocation: BridgeLocation,
    permission: Permission,
    participantCount: Int?,
    hasActiveSystemShare: Bool,
    creationState: CreationState
  ) {
    self.bridgeLocation = bridgeLocation
    self.permission = permission
    self.participantCount = participantCount
    self.hasActiveSystemShare = hasActiveSystemShare
    self.creationState = creationState
  }

  var canExportLocalChangesToBridge: Bool {
    switch permission {
    case .owner, .readWrite:
      true
    case .readOnly, .unknown:
      false
    }
  }

  var locationDescription: String {
    switch bridgeLocation {
    case .bridgeRecordMissing:
      "no bridge record yet"
    case .ownerPrivateStore:
      "owner private store"
    case .acceptedSharedStore:
      "accepted shared store"
    }
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
      creationState: creationState
    )
  }

  static let localOwnerBridgePending = HerdSharingAccess(
    bridgeLocation: .bridgeRecordMissing,
    permission: .owner,
    participantCount: nil,
    hasActiveSystemShare: false,
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
      creationState: .unknown
    )
  }
}
