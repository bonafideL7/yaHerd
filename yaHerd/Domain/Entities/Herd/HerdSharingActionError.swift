//
//  HerdSharingActionError.swift
//  yaHerd
//

import Foundation

enum HerdSharingActionError: LocalizedError, Equatable {
  case shareRootMissing
  case iCloudSyncRequired
  case shareInvitationMissing
  case sharingStoreUnavailable(String)
  case readOnlyShareCannotWrite
  case cloudKitSharingFailed(String)
  case bridgeImportFailed(String)
  case bridgeConsistencyFailed(String)

  var errorDescription: String? {
    switch self {
    case .shareRootMissing:
      "The app could not find a Herd root record to share."
    case .iCloudSyncRequired:
      "Enable iCloud Sync before sharing this herd with other iCloud users."
    case .shareInvitationMissing:
      "No pending CloudKit share invitation is available to accept."
    case .sharingStoreUnavailable(let message):
      "The CloudKit sharing store is unavailable. \(message)"
    case .readOnlyShareCannotWrite:
      "This CloudKit share is read-only for the current iCloud account. yaHerd can import shared changes, but it cannot export local edits to the shared herd."
    case .cloudKitSharingFailed(let message):
      "CloudKit sharing failed. \(message)"
    case .bridgeImportFailed(let message):
      "Shared herd import failed. \(message)"
    case .bridgeConsistencyFailed(let message):
      "Shared herd consistency check failed. \(message)"
    }
  }
}
