import Foundation

@MainActor
protocol HerdSharingOwnerStopCleanupRecording: AnyObject {
    func isCleanupPending(for herdPublicID: UUID) -> Bool
    func recordCleanupPending(for herdPublicID: UUID) throws
    func clearCleanupPending(for herdPublicID: UUID) throws
}

@MainActor
protocol HerdSharingRetainedOwnerShareCleanupManaging: AnyObject {
    func manageRetainedOwnerShareForStopCleanup(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult
}

@MainActor
final class UserDefaultsHerdSharingOwnerStopCleanupStore:
    HerdSharingOwnerStopCleanupRecording
{
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "herdSharing.ownerStopCleanupPending"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func isCleanupPending(for herdPublicID: UUID) -> Bool {
        defaults.object(forKey: key(for: herdPublicID)) != nil
    }

    func recordCleanupPending(for herdPublicID: UUID) throws {
        let storageKey = key(for: herdPublicID)
        defaults.set(true, forKey: storageKey)
        _ = defaults.synchronize()
        guard defaults.bool(forKey: storageKey) else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Stop Sharing completed remotely, but yaHerd could not persist the required local-cleanup block. Local sharing state remains blocked for this launch."
            )
        }
    }

    func clearCleanupPending(for herdPublicID: UUID) throws {
        let storageKey = key(for: herdPublicID)
        defaults.removeObject(forKey: storageKey)
        _ = defaults.synchronize()
        guard defaults.object(forKey: storageKey) == nil else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "The stopped owner share was purged, but yaHerd could not clear its durable cleanup marker. Local sharing state remains blocked until cleanup is confirmed again."
            )
        }
    }

    private func key(for herdPublicID: UUID) -> String {
        "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
    }
}

@MainActor
final class MutationPublishingHerdSharingRepository: HerdSharingRepository {
    private let base: any HerdSharingRepository
    private let mutationCenter: ApplicationMutationCenter
    private let writePolicy: HerdCollaborationWritePolicy?
    private let herdRepository: (any HerdRepository)?
    private let ownerStopCleanupStore: any HerdSharingOwnerStopCleanupRecording
    private let ownerShareSystemShareResolver: @MainActor (
        HerdSharePresentationRequest
    ) -> CloudKitSystemShare?

    init(
        base: any HerdSharingRepository,
        mutationCenter: ApplicationMutationCenter,
        writePolicy: HerdCollaborationWritePolicy? = nil,
        herdRepository: (any HerdRepository)? = nil,
        ownerStopCleanupStore: any HerdSharingOwnerStopCleanupRecording = UserDefaultsHerdSharingOwnerStopCleanupStore(),
        ownerShareSystemShareResolver: @escaping @MainActor (
            HerdSharePresentationRequest
        ) -> CloudKitSystemShare? = { _ in nil }
    ) {
        self.base = base
        self.mutationCenter = mutationCenter
        self.writePolicy = writePolicy
        self.herdRepository = herdRepository
        self.ownerStopCleanupStore = ownerStopCleanupStore
        self.ownerShareSystemShareResolver = ownerShareSystemShareResolver
    }

    func fetchSharingReadiness(for herd: HerdSummary?, storageMode: HerdStorageMode) -> HerdSharingReadiness {
        base.fetchSharingReadiness(for: herd, storageMode: storageMode)
    }

    func fetchSharingAccess(for herd: HerdSummary?, storageMode: HerdStorageMode) async throws -> HerdSharingAccess {
        let access = try await base.fetchSharingAccess(for: herd, storageMode: storageMode)
        guard let herd else { return access }
        let gatedAccess = try applyingOwnerStopCleanupGate(
            to: access,
            for: herd,
            storageMode: storageMode
        )
        if gatedAccess.creationState == .ownerStopCleanupPending {
            writePolicy?.clearAccessAfterFailedSynchronization()
        }
        return gatedAccess
    }

    func startSharing(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try requireNoPendingOwnerStopCleanup(for: herd, storageMode: storageMode)
        do {
            let result = try await base.startSharing(herd: herd, storageMode: storageMode)
            installOwnerShareStopObserver(
                from: result,
                herdPublicID: herd.publicID,
                storageMode: storageMode
            )
            return result
        } catch {
            await refreshWritePolicyAfterFailedSharedBridgeOperation(
                herd: herd,
                storageMode: storageMode
            )
            throw error
        }
    }

    func manageExistingShare(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        do {
            try requireNoPendingOwnerStopCleanup(for: herd, storageMode: storageMode)
            if storageMode == .iCloud {
                let access = try await fetchSharingAccess(for: herd, storageMode: storageMode)
                guard access.creationState != .ownerStopCleanupPending else {
                    writePolicy?.update(access: access)
                    throw HerdSharingActionError.bridgeConsistencyFailed(
                        "The owner share is no longer present in CloudKit. Stop Sharing cleanup must complete before share management can reopen."
                    )
                }
            }
            let result = try await base.manageExistingShare(herd: herd, storageMode: storageMode)
            installOwnerShareStopObserver(
                from: result,
                herdPublicID: herd.publicID,
                storageMode: storageMode
            )
            return result
        } catch {
            await refreshWritePolicyAfterFailedSharedBridgeOperation(
                herd: herd,
                storageMode: storageMode
            )
            throw error
        }
    }

    func confirmLocalHerdOwnership(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try requireNoPendingOwnerStopCleanup(for: herd, storageMode: storageMode)
        return try await base.confirmLocalHerdOwnership(herd: herd, storageMode: storageMode)
    }

    func resetStaleOwnerSharingState(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        if storageMode == .iCloud,
           ownerStopCleanupStore.isCleanupPending(for: herd.publicID)
        {
            return try await retryOwnerStopCleanup(herd: herd, storageMode: storageMode)
        }
        return try await base.resetStaleOwnerSharingState(herd: herd, storageMode: storageMode)
    }

    func detachStaleParticipantState(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try requireNoPendingOwnerStopCleanup(for: herd, storageMode: storageMode)
        return try await base.detachStaleParticipantState(herd: herd, storageMode: storageMode)
    }

    func resolveBridgeConflict(
        herd: HerdSummary,
        keeping resolution: HerdSharingBridgeConflictResolution,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireNoPendingOwnerStopCleanup(for: herd, storageMode: storageMode)
        let result = try await base.resolveBridgeConflict(herd: herd, keeping: resolution, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }

    func acceptShareInvitation(_ invitation: HerdShareInvitation, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try requireNoPendingOwnerStopCleanupForCurrentHerd(storageMode: storageMode)
        do {
            let result = try await base.acceptShareInvitation(invitation, storageMode: storageMode)
            invalidateWritePolicyAfterAcceptedInvitationCommit(storageMode: storageMode)
            mutationCenter.recordSharedStoreImport()
            return result
        } catch {
            if let actionError = error as? HerdSharingActionError {
                switch actionError {
                case .bridgeImportRequiresAccessVerification, .bridgeConsistencyFailed:
                    // Invitation acceptance may commit a durable import/recovery gate before
                    // reporting either error. Never retain writable authority from before that
                    // commit; a later authoritative refresh can restore access if nothing changed.
                    invalidateWritePolicyAfterAcceptedInvitationCommit(storageMode: storageMode)
                default:
                    break
                }
            }
            throw error
        }
    }

    func importSharedBridgeData(herd: HerdSummary?, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        if let herd {
            try requireNoPendingOwnerStopCleanup(for: herd, storageMode: storageMode)
        } else {
            try requireNoPendingOwnerStopCleanupForCurrentHerd(storageMode: storageMode)
        }
        do {
            let result = try await base.importSharedBridgeData(herd: herd, storageMode: storageMode)
            mutationCenter.recordSharedStoreImport()
            return result
        } catch {
            await refreshWritePolicyAfterFailedSharedBridgeOperation(
                herd: herd,
                storageMode: storageMode
            )
            throw error
        }
    }

    func acceptPreventedSharedDeletes(in review: HerdSharingConflictReview, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try requireNoPendingOwnerStopCleanupForCurrentHerd(storageMode: storageMode)
        try validateCanApplyPreventedSharedDeletes()
        let result = try await base.acceptPreventedSharedDeletes(in: review, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireNoPendingOwnerStopCleanupForCurrentHerd(storageMode: storageMode)
        try writePolicy?.validateCanWrite(reason: .herd)
        let result = try await base.restoreLocalFields(selections, in: review, storageMode: storageMode)
        mutationCenter.recordSharedStoreImport()
        return result
    }

    func syncSharedBridgeData(herd: HerdSummary?, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        if let herd {
            try requireNoPendingOwnerStopCleanup(for: herd, storageMode: storageMode)
        } else {
            try requireNoPendingOwnerStopCleanupForCurrentHerd(storageMode: storageMode)
        }
        do {
            let result = try await base.syncSharedBridgeData(herd: herd, storageMode: storageMode)
            mutationCenter.recordSharedStoreImport()
            return result
        } catch {
            await refreshWritePolicyAfterFailedSharedBridgeOperation(
                herd: herd,
                storageMode: storageMode
            )
            throw error
        }
    }

    private func validateCanApplyPreventedSharedDeletes() throws {
        guard let writePolicy else { return }
        do {
            try writePolicy.validateCanWrite(reason: .herd)
        } catch let error as HerdCollaborationWritePolicyError {
            switch error {
            case .readOnlySharedHerd(_, .readOnly):
                // Accepting a prevented shared delete converges local SwiftData to the authoritative
                // shared snapshot; it does not export a participant mutation. A read-only
                // participant must be able to discard its stale local record, while all recovery,
                // conflict, unverified-access, and data-recovery gates remain fail-closed above.
                return
            default:
                throw error
            }
        }
    }

    private func requireNoPendingOwnerStopCleanup(
        for herd: HerdSummary,
        storageMode: HerdStorageMode
    ) throws {
        guard storageMode != .iCloud
            || !ownerStopCleanupStore.isCleanupPending(for: herd.publicID)
        else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Stop Sharing cleanup is still pending for this Herd. Retry cleanup before starting, managing, or synchronizing sharing."
            )
        }
    }

    private func requireNoPendingOwnerStopCleanupForCurrentHerd(
        storageMode: HerdStorageMode
    ) throws {
        guard storageMode == .iCloud, let herdRepository else { return }
        try requireNoPendingOwnerStopCleanup(
            for: herdRepository.fetchCurrentHerd(),
            storageMode: storageMode
        )
    }

    private func invalidateWritePolicyAfterAcceptedInvitationCommit(
        storageMode: HerdStorageMode
    ) {
        guard storageMode == .iCloud, let writePolicy else { return }
        writePolicy.clearAccessAfterFailedSynchronization()
    }

    private func installOwnerShareStopObserver(
        from result: HerdSharingActionResult,
        herdPublicID: UUID,
        storageMode: HerdStorageMode
    ) {
        guard storageMode == .iCloud,
              let presentation = result.sharePresentation,
              let systemShare = ownerShareSystemShareResolver(presentation)
        else { return }

        systemShare.observeStopSharing { [weak self] event in
            try await self?.handleOwnerShareStopEvent(
                event,
                herdPublicID: herdPublicID,
                storageMode: storageMode
            )
        }
        systemShare.observeStopPreparation { [weak self] in
            try self?.prepareOwnerShareStop(
                herdPublicID: herdPublicID,
                storageMode: storageMode
            )
        }
    }

    private func prepareOwnerShareStop(
        herdPublicID: UUID,
        storageMode: HerdStorageMode
    ) throws {
        guard storageMode == .iCloud else { return }
        writePolicy?.clearAccessAfterFailedSynchronization()
        try ownerStopCleanupStore.recordCleanupPending(for: herdPublicID)
    }

    private func handleOwnerShareStopEvent(
        _ event: CloudKitSystemShare.StopEvent,
        herdPublicID: UUID,
        storageMode: HerdStorageMode
    ) async throws {
        guard storageMode == .iCloud else { return }

        // UICloudSharingController reports stop-sharing after the repository call that opened the
        // controller has already returned. Persist the cleanup gate before touching the local
        // bridge, then invalidate cached writable owner access so no SwiftData mutation can race
        // the asynchronous purge or a later access refresh.
        writePolicy?.clearAccessAfterFailedSynchronization()
        if event == .started {
            try prepareOwnerShareStop(
                herdPublicID: herdPublicID,
                storageMode: storageMode
            )
            return
        }

        do {
            if let herdRepository {
                let currentHerd = try herdRepository.fetchCurrentHerd()
                if currentHerd.publicID == herdPublicID {
                    let access = try await base.fetchSharingAccess(
                        for: currentHerd,
                        storageMode: storageMode
                    )

                    // Do not retire the durable gate until the post-purge access read is also
                    // blocking. A stale writable CKShare must remain recoverable after relaunch.
                    guard !access.allowsLocalMutations else {
                        throw HerdSharingActionError.bridgeConsistencyFailed(
                            "Stop Sharing cleanup returned successfully, but the owner bridge still appears writable. Cleanup remains pending."
                        )
                    }
                    let durableHerd = try herdRepository.fetchCurrentHerd()
                    guard durableHerd.publicID == currentHerd.publicID else {
                        throw HerdSharingActionError.bridgeImportRequiresAccessVerification(
                            "The current Herd changed while stop-sharing access was being verified. The stale access result was discarded."
                        )
                    }
                    try ownerStopCleanupStore.clearCleanupPending(for: herdPublicID)
                    writePolicy?.update(access: access)
                    return
                }
            }

            try ownerStopCleanupStore.clearCleanupPending(for: herdPublicID)
        } catch {
            writePolicy?.clearAccessAfterFailedSynchronization()
            throw error
        }
    }

    private func retryOwnerStopCleanup(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        let access = try await base.fetchSharingAccess(for: herd, storageMode: storageMode)

        if access.bridgeLocation == .ownerPrivateStore, access.hasActiveSystemShare {
            guard let cleanupManager = base as? any HerdSharingRetainedOwnerShareCleanupManaging else {
                throw HerdSharingActionError.shareManagementUnavailable
            }
            let result = try await cleanupManager.manageRetainedOwnerShareForStopCleanup(
                herd: herd,
                storageMode: storageMode
            )
            guard let presentation = result.sharePresentation,
                  let systemShare = ownerShareSystemShareResolver(presentation)
            else {
                throw HerdSharingActionError.shareManagementUnavailable
            }
            try await systemShare.stopSharing()
            try ownerStopCleanupStore.clearCleanupPending(for: herd.publicID)
            writePolicy?.clearAccessAfterFailedSynchronization()
            return HerdSharingActionResult(
                title: "Stop Sharing cleanup completed",
                message: "The stopped owner share was purged from the local sharing bridge. Refresh CloudKit access before resetting any remaining stale owner provenance."
            )
        }

        if access.bridgeLocation == .bridgeRecordMissing, !access.hasActiveSystemShare {
            let result = try await base.resetStaleOwnerSharingState(
                herd: herd,
                storageMode: storageMode
            )
            try ownerStopCleanupStore.clearCleanupPending(for: herd.publicID)
            writePolicy?.clearAccessAfterFailedSynchronization()
            return result
        }

        throw HerdSharingActionError.bridgeConsistencyFailed(
            "Stop Sharing cleanup can be retried only while the stopped owner bridge is still present or after CloudKit verifies that it is absent."
        )
    }

    private func refreshWritePolicyAfterFailedSharedBridgeOperation(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async {
        guard storageMode == .iCloud, let writePolicy else { return }

        // A failed bridge operation may already have committed sharing state or replaced the
        // current Herd before throwing. Block writes before any recovery read so stale
        // pre-operation access can never remain writable while durable state is re-established.
        writePolicy.clearAccessAfterFailedSynchronization()

        do {
            let accessHerd: HerdSummary
            let canPublishWritableAccess: Bool
            if let herdRepository {
                accessHerd = try herdRepository.fetchCurrentHerd()
                canPublishWritableAccess = true
            } else if let herd {
                // Test/support constructions that do not supply a durable Herd repository may use
                // the caller's snapshot only to publish a blocking access state. A writable result
                // is not authoritative because the failed operation could have replaced the Herd.
                accessHerd = herd
                canPublishWritableAccess = false
            } else {
                return
            }

            let fetchedAccess = try await base.fetchSharingAccess(
                for: accessHerd,
                storageMode: storageMode
            )
            let access = try applyingOwnerStopCleanupGate(
                to: fetchedAccess,
                for: accessHerd,
                storageMode: storageMode
            )
            if let herdRepository {
                let durableHerd = try herdRepository.fetchCurrentHerd()
                guard durableHerd.publicID == accessHerd.publicID else { return }
            }
            guard canPublishWritableAccess || !access.allowsLocalMutations else { return }
            writePolicy.update(access: access)
        } catch {
            // The policy was invalidated before the refresh began. Keep it verification-required
            // when the durable Herd or authoritative sharing access cannot be re-read.
            writePolicy.clearAccessAfterFailedSynchronization()
        }
    }

    private func applyingOwnerStopCleanupGate(
        to access: HerdSharingAccess,
        for herd: HerdSummary,
        storageMode: HerdStorageMode
    ) throws -> HerdSharingAccess {
        guard storageMode == .iCloud else { return access }
        if access.creationState == .ownerStopCleanupPending {
            try ownerStopCleanupStore.recordCleanupPending(for: herd.publicID)
            return access
        }
        guard ownerStopCleanupStore.isCleanupPending(for: herd.publicID) else {
            return access
        }
        return access.applyingCreationState(.ownerStopCleanupPending)
    }
}
