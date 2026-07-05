//
//  SwiftDataHerdSharingRepository.swift
//  yaHerd
//

@MainActor
final class SwiftDataHerdSharingRepository: HerdSharingRepository {
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
            return .sharingAdapterPending
        }
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        switch storageMode {
        case .localOnly:
            throw HerdSharingActionError.iCloudSyncRequired
        case .iCloud:
            throw HerdSharingActionError.sharingAdapterPending
        }
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitationSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        switch storageMode {
        case .localOnly:
            throw HerdSharingActionError.iCloudSyncRequired
        case .iCloud:
            throw HerdSharingActionError.sharingAdapterPending
        }
    }
}
