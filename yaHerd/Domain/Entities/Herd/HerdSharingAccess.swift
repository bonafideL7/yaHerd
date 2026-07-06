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

  let bridgeLocation: BridgeLocation
  let permission: Permission
  let participantCount: Int?

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

  static let localOwnerBridgePending = HerdSharingAccess(
    bridgeLocation: .bridgeRecordMissing,
    permission: .owner,
    participantCount: nil
  )

  static func ownerPrivateStore(participantCount: Int?) -> HerdSharingAccess {
    HerdSharingAccess(
      bridgeLocation: .ownerPrivateStore,
      permission: .owner,
      participantCount: participantCount
    )
  }

  static func acceptedSharedStore(
    permission: Permission,
    participantCount: Int?
  ) -> HerdSharingAccess {
    HerdSharingAccess(
      bridgeLocation: .acceptedSharedStore,
      permission: permission,
      participantCount: participantCount
    )
  }
}
