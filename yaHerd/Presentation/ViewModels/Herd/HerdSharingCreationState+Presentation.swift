//
//  HerdSharingCreationState+Presentation.swift
//  yaHerd
//

extension HerdSharingAccess.CreationState {
  var primaryActionTitle: String {
    switch self {
    case .ready:
      "Share Herd"
    case .existingOwnerShare:
      "Manage Herd Sharing"
    case .acceptedParticipantShare:
      "Sync Shared Herd"
    case .unresolvedBridgeRecord:
      "Resume Herd Sharing"
    case .conflictingBridgeRecords:
      "Resolve Bridge Conflict"
    case .pendingBridgeOperation:
      "Resolve Sharing State"
    case .notOwnedByCurrentDevice:
      "Sharing Unavailable"
    case .unknown:
      "Checking Sharing State"
    }
  }
}
