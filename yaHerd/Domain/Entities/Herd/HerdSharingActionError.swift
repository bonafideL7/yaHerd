//
//  HerdSharingActionError.swift
//  yaHerd
//

import Foundation

enum HerdSharingActionError: LocalizedError, Equatable {
  case shareRootMissing
  case recoveryModeReadOnly
  case iCloudSyncRequired
  case shareInvitationMissing
  case shareAlreadyExists
  case acceptedParticipantShareCannotReshare
  case unresolvedSharingBridge
  case sharingOperationPending
  case ownershipConfirmationRequired
  case ownerBridgeVerificationRequired
  case herdOwnershipRequired
  case sharingStateUnavailable
  case shareManagementUnavailable
  case sharingStoreUnavailable(String)
  case readOnlyShareCannotWrite
  case cloudKitSharingFailed(String)
  case bridgeImportFailed(String)
  case bridgeImportRequiresAccessVerification(String)
  case bridgeConsistencyFailed(String)

  var errorDescription: String? {
    switch self {
    case .shareRootMissing:
      "No Herd share root exists yet. Create or restore the Herd before using CloudKit sharing."
    case .recoveryModeReadOnly:
      "CloudKit collaboration is disabled while yaHerd is running in read-only recovery mode."
    case .iCloudSyncRequired:
      "Enable iCloud Sync before sharing this herd with other iCloud users."
    case .shareInvitationMissing:
      "No pending CloudKit share invitation is available to accept."
    case .shareAlreadyExists:
      "This herd already has an active owner share. Open sharing management instead of creating another share."
    case .acceptedParticipantShareCannotReshare:
      "This herd was accepted from another owner. Synchronize the accepted share instead of creating a second share."
    case .unresolvedSharingBridge:
      "A sharing bridge record exists without a valid owner share. Synchronize or repair the bridge before creating a share."
    case .sharingOperationPending:
      "A previous sharing import, export, or reconciliation operation is unfinished. Resolve it before creating or managing a share."
    case .ownershipConfirmationRequired:
      "This installation has not yet been confirmed as the local owner for this Herd root. Confirm ownership before creating or resuming an owner share. A deliberately detached stale participant copy also requires this separate confirmation before it can become independently owned."
    case .ownerBridgeVerificationRequired:
      "This iCloud account or restored Herd may already have owner-sharing history, but the owner bridge is not currently available on this installation. Refresh CloudKit sharing first, or deliberately reset the stale owner-sharing state only after confirming no owner share remains."
    case .herdOwnershipRequired:
      "This Herd is known to be an accepted participant copy and cannot be reshared as a new owner herd until that stale participation is deliberately detached."
    case .sharingStateUnavailable:
      "The repository could not verify the current sharing state. Refresh access before trying again."
    case .shareManagementUnavailable:
      "An active owner share was not available to manage. Refresh sharing access and try again."
    case .sharingStoreUnavailable(let message):
      "The CloudKit sharing store is unavailable. \(message)"
    case .readOnlyShareCannotWrite:
      "This accepted CloudKit share is read-only. Local edits cannot be exported to the shared herd."
    case .cloudKitSharingFailed(let message):
      "CloudKit sharing failed. \(message)"
    case .bridgeImportFailed(let message):
      "Shared herd import failed. \(message)"
    case .bridgeImportRequiresAccessVerification(let message):
      "Shared herd import failed after sharing access may have changed. Verify CloudKit sharing access before making more local edits. \(message)"
    case .bridgeConsistencyFailed(let message):
      "The sharing bridge is inconsistent. \(message)"
    }
  }
}
