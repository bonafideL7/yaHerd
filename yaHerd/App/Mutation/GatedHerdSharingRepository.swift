/// Applies the shared mutation gate at the repository boundary so no caller can bypass
/// duplicate-ID repair exclusion by invoking a bridge mutation directly.
@MainActor
final class GatedHerdSharingRepository: HerdSharingRepository {
    private let base: any HerdSharingRepository
    private let mutationGate: HerdDataMutationGate

    init(
        base: any HerdSharingRepository,
        mutationGate: HerdDataMutationGate
    ) {
        self.base = base
        self.mutationGate = mutationGate
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
        try await withSynchronizationGate {
            try await base.startSharing(herd: herd, storageMode: storageMode)
        }
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.acceptShareInvitation(invitation, storageMode: storageMode)
        }
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.importSharedBridgeData(herd: herd, storageMode: storageMode)
        }
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.acceptPreventedSharedDeletes(in: review, storageMode: storageMode)
        }
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.restoreLocalFields(selections, in: review, storageMode: storageMode)
        }
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.syncSharedBridgeData(herd: herd, storageMode: storageMode)
        }
    }

    private func withSynchronizationGate<Result>(
        _ operation: () async throws -> Result
    ) async throws -> Result {
        let token = try mutationGate.beginSynchronization()
        defer { mutationGate.endSynchronization(token) }
        return try await operation()
    }
}
