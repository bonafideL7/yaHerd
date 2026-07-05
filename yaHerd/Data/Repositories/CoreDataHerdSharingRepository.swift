//
//  CoreDataHerdSharingRepository.swift
//  yaHerd
//

import Foundation

@MainActor
final class CoreDataHerdSharingRepository: HerdSharingRepository {
    private let store: HerdSharingCoreDataStore

    init(store: HerdSharingCoreDataStore = HerdSharingCoreDataStore()) {
        self.store = store
    }

    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness {
        guard herd != nil else {
            return .shareRootMissing
        }

        switch storageMode {
        case .localOnly:
            return .iCloudSyncRequired
        case .iCloud:
            return .sharingAdapterAvailable
        }
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }

        let systemShare = try await store.makeSystemShare(for: herd)
        return HerdSharingActionResult(
            title: "Share sheet ready",
            message: "Invite people through the system CloudKit sharing sheet. SwiftData data has not been replaced; Core Data is only mirroring the share root for CloudKit sharing.",
            systemShare: systemShare
        )
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }

        try await store.acceptShareInvitation(metadata: invitation.metadata)
        return HerdSharingActionResult(
            title: "Invitation accepted",
            message: "The shared herd metadata was accepted into the Core Data CloudKit sharing bridge. SwiftData app records remain untouched."
        )
    }
}
