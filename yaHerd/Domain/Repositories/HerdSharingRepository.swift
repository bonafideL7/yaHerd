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

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult

    func importSharedBridgeData(storageMode: HerdStorageMode) async throws -> HerdSharingActionResult
}
