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
    case cloudKitSharingFailed(String)

    var errorDescription: String? {
        switch self {
        case .shareRootMissing:
            "The app could not find a Herd root record to share."
        case .iCloudSyncRequired:
            "Enable iCloud Sync before sharing this herd with other iCloud users."
        case .shareInvitationMissing:
            "No pending CloudKit share invitation is available to accept."
        case let .sharingStoreUnavailable(message):
            "The CloudKit sharing store is unavailable. \(message)"
        case let .cloudKitSharingFailed(message):
            "CloudKit sharing failed. \(message)"
        }
    }
}
