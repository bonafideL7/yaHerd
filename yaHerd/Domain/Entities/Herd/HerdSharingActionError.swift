//
//  HerdSharingActionError.swift
//  yaHerd
//

import Foundation

enum HerdSharingActionError: LocalizedError, Equatable {
    case shareRootMissing
    case iCloudSyncRequired
    case sharingAdapterPending
    case shareInvitationMissing

    var errorDescription: String? {
        switch self {
        case .shareRootMissing:
            "The app could not find a Herd root record to share."
        case .iCloudSyncRequired:
            "Enable iCloud Sync before sharing this herd with other iCloud users."
        case .sharingAdapterPending:
            "CloudKit sharing is not wired to persistent storage yet. Add the sharing adapter before enabling invitations."
        case .shareInvitationMissing:
            "No pending CloudKit share invitation is available to accept."
        }
    }
}
