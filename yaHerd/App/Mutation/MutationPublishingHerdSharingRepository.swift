@MainActor
final class MutationPublishingHerdSharingRepository: HerdSharingRepository {
    private let base: any HerdSharingRepository
    private let mutationCenter: ApplicationMutationCenter

    init(
        base: any HerdSharingRepository,
        mutationCenter: ApplicationMutationCenter
    ) {
        self.base = base
        self.mutationCenter = mutationCenter
    }

    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness {
        base.fetchSharingReadiness(for: herd, storageMode: storageMode)
    }

    func fetchSharingAccess(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingAccess {
        try await base.fetchSharingAccess(for: herd, storageMode: storageMode)
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await base.startSharing(herd: herd, storageMode: storageMode)
    }

    func manageExistingShare(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await base.manageExistingShare(herd: herd, storageMode: storageMode)
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        let result = try await base.acceptShareInvitation(invitation, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        let result = try await base.importSharedBridgeData(herd: herd, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        let result = try await base.acceptPreventedSharedDeletes(in: review, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        let result = try await base.restoreLocalFields(selections, in: review, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        let result = try await base.syncSharedBridgeData(herd: herd, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }
}
