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
}
