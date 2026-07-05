//
//  HerdSharingRepository.swift
//  yaHerd
//

@MainActor
protocol HerdSharingRepository: AnyObject {
    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness
}
