import SwiftData

/// Avoids constructing the Core Data/CloudKit sharing bridge until an iCloud
/// collaboration operation actually needs it. Local-only launches and tests
/// can evaluate collaboration readiness without requiring CloudKit entitlements.
@MainActor
final class DeferredCoreDataHerdSharingRepository: HerdSharingRepository {
    private let repositoryFactory: @MainActor () -> any HerdSharingRepository
    private let creationGuard: any HerdSharingCreationStateGuarding
    private let creationOperationGate = HerdSharingBridgeOperationGate()
    private var resolvedRepository: (any HerdSharingRepository)?

    init(
        context: ModelContext,
        shareAdapter: CloudKitShareAdapter,
        creationGuard: (any HerdSharingCreationStateGuarding)? = nil
    ) {
        repositoryFactory = {
            CoreDataHerdSharingRepository(
                context: context,
                shareAdapter: shareAdapter
            )
        }
        self.creationGuard = creationGuard ?? HerdSharingCreationStateGuard(context: context)
    }

    init(
        repository: any HerdSharingRepository,
        creationGuard: any HerdSharingCreationStateGuarding
    ) {
        repositoryFactory = { repository }
        self.creationGuard = creationGuard
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
        guard let herd else {
            throw HerdSharingActionError.shareRootMissing
        }
        let access = try await repository.fetchSharingAccess(for: herd, storageMode: storageMode)
        return try await creationGuard.evaluate(herd: herd, access: access)
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)

        await creationOperationGate.acquire()
        defer { creationOperationGate.release() }

        let access = try await repository.fetchSharingAccess(for: herd, storageMode: storageMode)
        _ = try await creationGuard.validateNewShare(herd: herd, access: access)
        return try await repository.startSharing(herd: herd, storageMode: storageMode)
    }

    func manageExistingShare(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)

        await creationOperationGate.acquire()
        defer { creationOperationGate.release() }

        let rawAccess = try await repository.fetchSharingAccess(for: herd, storageMode: storageMode)
        let access = try await creationGuard.evaluate(herd: herd, access: rawAccess)

        switch access.creationState {
        case .existingOwnerShare, .unresolvedBridgeRecord:
            break
        case .pendingBridgeOperation:
            throw HerdSharingActionError.sharingOperationPending
        case .notOwnedByCurrentDevice:
            throw HerdSharingActionError.herdOwnershipRequired
        case .conflictingBridgeRecords:
            throw HerdSharingActionError.unresolvedSharingBridge
        case .unknown:
            throw HerdSharingActionError.sharingStateUnavailable
        case .ready, .acceptedParticipantShare:
            throw HerdSharingActionError.shareManagementUnavailable
        }

        // Core Data reuses an existing CKShare for owners. When an interrupted
        // first-share attempt left a private bridge root without a CKShare, this
        // same path resumes that bridge instead of starting from a second root.
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

    private var repository: any HerdSharingRepository {
        if let resolvedRepository { return resolvedRepository }
        let repository = repositoryFactory()
        resolvedRepository = repository
        return repository
    }

    private func requireICloud(_ storageMode: HerdStorageMode) throws {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }
    }
}
