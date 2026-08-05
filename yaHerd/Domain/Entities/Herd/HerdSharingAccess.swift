//
//  HerdSharingAccess.swift
//  yaHerd
//

struct HerdSharingAccess: Equatable {
  enum BridgeLocation: Equatable {
    case bridgeRecordMissing
    case ownerPrivateStore
    case acceptedSharedStore
    case conflictingStores
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
    case conflictingBridgeRecords
    case pendingBridgeOperation
    case notOwnedByCurrentDevice

    var allowsNewShare: Bool {
      self == .ready
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
    case .conflictingStores:
      "owner and accepted shared stores"
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

  static func conflictingStores(
    ownerHasActiveSystemShare: Bool,
    participantCount: Int?
  ) -> HerdSharingAccess {
    HerdSharingAccess(
      bridgeLocation: .conflictingStores,
      permission: .unknown,
      participantCount: participantCount,
      hasActiveSystemShare: ownerHasActiveSystemShare,
      creationState: .unknown
    )
  }
}
