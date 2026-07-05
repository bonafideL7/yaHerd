//
//  HerdSharingReadiness.swift
//  yaHerd
//

struct HerdSharingReadiness: Equatable {
    enum State: Equatable {
        case shareRootMissing
        case iCloudSyncRequired
        case sharingAdapterAvailable
    }

    let state: State
    let title: String
    let message: String

    var shareActionEnabled: Bool {
        state == .sharingAdapterAvailable
    }

    static let shareRootMissing = HerdSharingReadiness(
        state: .shareRootMissing,
        title: "Share root missing",
        message: "The app could not find a Herd root record to share."
    )

    static let iCloudSyncRequired = HerdSharingReadiness(
        state: .iCloudSyncRequired,
        title: "iCloud Sync required",
        message: "Enable iCloud Sync before exposing a share action. Local-only stores cannot invite other iCloud users."
    )

    static let sharingAdapterAvailable = HerdSharingReadiness(
        state: .sharingAdapterAvailable,
        title: "CloudKit sharing bridge ready",
        message: "SwiftData remains the app data store. Core Data is loaded only as the CloudKit sharing bridge for the Herd share root."
    )
}
