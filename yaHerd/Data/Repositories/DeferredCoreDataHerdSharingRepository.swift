import SwiftData

/// Avoids constructing the Core Data/CloudKit sharing bridge until an iCloud
/// collaboration operation actually needs it. Local-only launches and tests
/// can evaluate collaboration readiness without requiring CloudKit entitlements.
@MainActor
final class DeferredCoreDataHerdSharingRepository: HerdSharingRepository {
    private let context: ModelContext
    private let shareAdapter: CloudKitShareAdapter
    private var resolvedRepository: CoreDataHerdSharingRepository?

    init(
        context: ModelContext,
        shareAdapter: CloudKitShareAdapter
    ) {
        self.context = context
        self.shareAdapter = shareAdapter
    }

    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness {
        guard herd != nil else { return .shareRootMissing }
        guard storageMode == .iCloud else { return .iCloudSyncRequired }
        return .sharingAdapterAvailable
    }

    func fetchSharingAccess(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingAccess {
        try requireICloud(storageMode)
        return try await repository.fetchSharingAccess(for: herd, storageMode: storageMode)
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        return try await repository.startSharing(herd: herd, storageMode: storageMode)
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        return try await repository.acceptShareInvitation(invitation, storageMode: storageMode)
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        return try await repository.importSharedBridgeData(herd: herd, storageMode: storageMode)
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        return try await repository.acceptPreventedSharedDeletes(in: review, storageMode: storageMode)
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        return try await repository.restoreLocalFields(
            selections,
            in: review,
            storageMode: storageMode
        )
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        return try await repository.syncSharedBridgeData(herd: herd, storageMode: storageMode)
    }

    private var repository: CoreDataHerdSharingRepository {
        if let resolvedRepository { return resolvedRepository }
        let repository = CoreDataHerdSharingRepository(
            context: context,
            shareAdapter: shareAdapter
        )
        resolvedRepository = repository
        return repository
    }

    private func requireICloud(_ storageMode: HerdStorageMode) throws {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }
    }
}
