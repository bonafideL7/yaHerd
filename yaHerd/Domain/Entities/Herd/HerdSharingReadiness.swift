//
//  HerdSharingReadiness.swift
//  yaHerd
//

struct HerdSharingReadiness: Equatable {
    enum State: Equatable {
        case shareRootMissing
        case iCloudSyncRequired
        case sharingAdapterPending
    }

    let state: State
    let title: String
    let message: String

    var shareActionEnabled: Bool {
        false
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

    static let sharingAdapterPending = HerdSharingReadiness(
        state: .sharingAdapterPending,
        title: "CloudKit sharing adapter needed",
        message: "The herd is scoped for collaboration prep. A real CloudKit sharing adapter still needs to create and manage a share for this root herd."
    )
}
