import Foundation

/// Applies the shared mutation gate at the repository boundary so no caller can bypass
/// duplicate-ID repair exclusion by invoking a bridge mutation directly. Owner and stale-participant
/// recovery additionally require authoritative CloudKit verification before local state changes.
@MainActor
final class GatedHerdSharingRepository: HerdSharingRepository,
    HerdSharingRetainedOwnerShareCleanupManaging
{
    private let base: any HerdSharingRepository
    private let mutationGate: HerdDataMutationGate
    private let ownerShareReferenceStore: any HerdSharingOwnerShareReferenceRecording
    private let remoteOwnerShareVerifier: any HerdSharingRemoteOwnerShareVerifying
    private let acceptedParticipantReferenceStore: any HerdSharingAcceptedParticipantReferenceRecording
    private let remoteAcceptedParticipantVerifier: any HerdSharingRemoteAcceptedParticipantVerifying
    private let observedOwnerShareReferenceProvider: @MainActor (UUID) -> HerdSharingRemoteOwnerShareReference?
    private var pendingNewOwnerShareReferences: [UUID: HerdSharingRemoteOwnerShareReference] = [:]
    private let savedOwnerShareObserverInstaller: @MainActor (
        HerdSharePresentationRequest,
        HerdSharingSavedOwnerShareReferenceRecorder
    ) -> Bool

    init(
        base: any HerdSharingRepository,
        mutationGate: HerdDataMutationGate,
        ownerShareReferenceStore: any HerdSharingOwnerShareReferenceRecording = MirroredHerdSharingOwnerShareReferenceStore(),
        remoteOwnerShareVerifier: any HerdSharingRemoteOwnerShareVerifying = CloudKitHerdSharingRemoteOwnerShareVerifier(),
        acceptedParticipantReferenceStore: any HerdSharingAcceptedParticipantReferenceRecording = UserDefaultsHerdSharingAcceptedParticipantReferenceStore(),
        remoteAcceptedParticipantVerifier: any HerdSharingRemoteAcceptedParticipantVerifying = CloudKitHerdSharingRemoteAcceptedParticipantVerifier(),
        observedOwnerShareReferenceProvider: @escaping @MainActor (UUID) -> HerdSharingRemoteOwnerShareReference? = { _ in nil },
        savedOwnerShareObserverInstaller: @escaping @MainActor (
            HerdSharePresentationRequest,
            HerdSharingSavedOwnerShareReferenceRecorder
        ) -> Bool = { _, _ in false }
    ) {
        self.base = base
        self.mutationGate = mutationGate
        self.ownerShareReferenceStore = ownerShareReferenceStore
        self.remoteOwnerShareVerifier = remoteOwnerShareVerifier
        self.acceptedParticipantReferenceStore = acceptedParticipantReferenceStore
        self.remoteAcceptedParticipantVerifier = remoteAcceptedParticipantVerifier
        self.observedOwnerShareReferenceProvider = observedOwnerShareReferenceProvider
        self.savedOwnerShareObserverInstaller = savedOwnerShareObserverInstaller
    }

    func fetchSharingReadiness(for herd: HerdSummary?, storageMode: HerdStorageMode) -> HerdSharingReadiness {
        base.fetchSharingReadiness(for: herd, storageMode: storageMode)
    }

    func fetchSharingAccess(for herd: HerdSummary?, storageMode: HerdStorageMode) async throws -> HerdSharingAccess {
        let access = try await base.fetchSharingAccess(for: herd, storageMode: storageMode)
        guard let herd else { return access }
        guard storageMode == .iCloud,
              !access.hasConflictingBridgeRecords,
              access.bridgeLocation == .ownerPrivateStore,
              access.hasActiveSystemShare
        else {
            pendingNewOwnerShareReferences.removeValue(forKey: herd.publicID)
            return access
        }

        let (reference, remoteStatus) = try await verifiedActiveOwnerShareReference(
            herdPublicID: herd.publicID
        )

        switch remoteStatus {
        case .present:
            pendingNewOwnerShareReferences.removeValue(forKey: herd.publicID)
            recordVerifiedOwnerShareEstablished(herdPublicID: herd.publicID)
            return access
        case .absent:
            if reference.shareURL == nil,
               pendingNewOwnerShareReferences[herd.publicID] == reference
            {
                // A newly created CKShare can exist in the local bridge before the system share
                // sheet saves it remotely. Trust only that exact account-scoped provisional
                // reference; a saved URL, changed reference, or changed access lifecycle removes
                // this narrow exception and restores authoritative remote verification.
                return access
            }
            pendingNewOwnerShareReferences.removeValue(forKey: herd.publicID)
            return access.applyingCreationState(.ownerStopCleanupPending)
        }
    }

    func startSharing(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            if storageMode == .iCloud {
                try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
                    for: herd.publicID,
                    referenceStore: ownerShareReferenceStore,
                    remoteVerifier: remoteOwnerShareVerifier,
                    allowMissingReference: true
                )
            }

            let result = try await base.startSharing(herd: herd, storageMode: storageMode)
            configureOwnerShareReferenceRecording(from: result, herdPublicID: herd.publicID)
            try await verifyAndRecordOwnerShareEstablished(
                herdPublicID: herd.publicID,
                allowProvisionalAbsence: true
            )
            return result
        }
    }

    func manageExistingShare(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            let access = try await fetchSharingAccess(for: herd, storageMode: storageMode)
            guard access.creationState != .ownerStopCleanupPending else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The owner share is no longer present in CloudKit. Stop Sharing cleanup must complete before share management can reopen."
                )
            }
            let result = try await base.manageExistingShare(herd: herd, storageMode: storageMode)
            configureOwnerShareReferenceRecording(from: result, herdPublicID: herd.publicID)
            if result.sharePresentation != nil {
                try await verifyAndRecordOwnerShareEstablished(
                    herdPublicID: herd.publicID,
                    allowProvisionalAbsence: true
                )
            }
            return result
        }
    }

    func manageRetainedOwnerShareForStopCleanup(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            guard let cleanupManager = base as? any HerdSharingRetainedOwnerShareCleanupManaging else {
                throw HerdSharingActionError.shareManagementUnavailable
            }
            return try await cleanupManager.manageRetainedOwnerShareForStopCleanup(
                herd: herd,
                storageMode: storageMode
            )
        }
    }

    func confirmLocalHerdOwnership(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            _ = try await fetchSharingAccess(for: herd, storageMode: storageMode)
            return try await base.confirmLocalHerdOwnership(herd: herd, storageMode: storageMode)
        }
    }

    func resetStaleOwnerSharingState(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            if storageMode == .iCloud {
                try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
                    for: herd.publicID,
                    referenceStore: ownerShareReferenceStore,
                    remoteVerifier: remoteOwnerShareVerifier
                )
            }

            return try await base.resetStaleOwnerSharingState(
                herd: herd,
                storageMode: storageMode
            )
        }
    }

    func detachStaleParticipantState(herd: HerdSummary, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            if storageMode == .iCloud {
                try await HerdSharingAcceptedParticipantProvenance.verifyRecordedShareIsAbsent(
                    for: herd.publicID,
                    referenceStore: acceptedParticipantReferenceStore,
                    remoteVerifier: remoteAcceptedParticipantVerifier
                )
            }

            let result = try await base.detachStaleParticipantState(
                herd: herd,
                storageMode: storageMode
            )
            acceptedParticipantReferenceStore.clearReference(for: herd.publicID)
            return result
        }
    }

    func resolveBridgeConflict(
        herd: HerdSummary,
        keeping resolution: HerdSharingBridgeConflictResolution,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            if storageMode == .iCloud, resolution == .keepOwnerShare {
                try await verifyAndRecordOwnerShareEstablished(
                    herdPublicID: herd.publicID,
                    allowProvisionalAbsence: false
                )
            }
            let result = try await base.resolveBridgeConflict(
                herd: herd,
                keeping: resolution,
                storageMode: storageMode
            )
            if resolution == .keepAcceptedShare {
                ownerShareReferenceStore.clearReference(for: herd.publicID)
            }
            return result
        }
    }

    func acceptShareInvitation(_ invitation: HerdShareInvitation, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.acceptShareInvitation(invitation, storageMode: storageMode)
        }
    }

    func importSharedBridgeData(herd: HerdSummary?, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.importSharedBridgeData(herd: herd, storageMode: storageMode)
        }
    }

    func acceptPreventedSharedDeletes(in review: HerdSharingConflictReview, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
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

    func syncSharedBridgeData(herd: HerdSummary?, storageMode: HerdStorageMode) async throws -> HerdSharingActionResult {
        try await withSynchronizationGate {
            try await base.syncSharedBridgeData(herd: herd, storageMode: storageMode)
        }
    }

    private func verifiedActiveOwnerShareReference(
        herdPublicID: UUID
    ) async throws -> (HerdSharingRemoteOwnerShareReference, HerdSharingRemoteOwnerShareStatus) {
        if let observedReference = observedOwnerShareReferenceProvider(herdPublicID) {
            guard observedReference.hasVerifiableLocator,
                  observedReference.shareOwnerAccountRecordName != nil
            else {
                throw HerdSharingActionError.ownerBridgeVerificationRequired
            }

            // The Deferred layer observes Core Data's local CKShare before this outer repository
            // verifies the currently signed-in account. Treat that observation as ephemeral only:
            // verify it first, then require it to remain unchanged across the await, and only then
            // backfill durable UserDefaults/KVS provenance.
            let remoteStatus = try await remoteOwnerShareVerifier.status(for: observedReference)
            guard observedOwnerShareReferenceProvider(herdPublicID) == observedReference else {
                throw HerdSharingActionError.ownerBridgeVerificationRequired
            }
            try HerdSharingExistingOwnerShareBackfill.recordObservedReference(
                observedReference,
                for: herdPublicID,
                referenceStore: ownerShareReferenceStore
            )
            guard let durableReference = try ownerShareReferenceStore.recoverableReference(
                for: herdPublicID
            ), HerdSharingExistingOwnerShareBackfill.sameExactIdentity(
                durableReference,
                observedReference
            ) else {
                throw HerdSharingActionError.ownerBridgeVerificationRequired
            }
            return (durableReference, remoteStatus)
        }

        guard let reference = try ownerShareReferenceStore.recoverableReference(
            for: herdPublicID
        ), reference.hasVerifiableLocator else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
        let remoteStatus = try await remoteOwnerShareVerifier.status(for: reference)
        guard try ownerShareReferenceStore.recoverableReference(
            for: herdPublicID
        ) == reference else {
            pendingNewOwnerShareReferences.removeValue(forKey: herdPublicID)
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
        return (reference, remoteStatus)
    }

    private func configureOwnerShareReferenceRecording(
        from result: HerdSharingActionResult,
        herdPublicID: UUID
    ) {
        guard let presentation = result.sharePresentation else {
            ownerShareReferenceStore.clearReference(for: herdPublicID)
            return
        }

        let recorder = HerdSharingSavedOwnerShareReferenceRecorder(
            referenceStore: ownerShareReferenceStore,
            herdPublicID: herdPublicID,
            presentation: presentation
        )
        let observesSavedShare = savedOwnerShareObserverInstaller(presentation, recorder)

        if HerdSharingOwnerShareProvenance.recordPresentationReferenceIfVerifiable(
            presentation,
            herdPublicID: herdPublicID,
            referenceStore: ownerShareReferenceStore
        ) {
            return
        }

        if !observesSavedShare {
            ownerShareReferenceStore.clearReference(for: herdPublicID)
        }
    }

    private func verifyAndRecordOwnerShareEstablished(
        herdPublicID: UUID,
        allowProvisionalAbsence: Bool
    ) async throws {
        guard let reference = try ownerShareReferenceStore.recoverableReference(
            for: herdPublicID
        ), reference.hasVerifiableLocator else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }

        let remoteStatus = try await remoteOwnerShareVerifier.status(for: reference)
        guard try ownerShareReferenceStore.recoverableReference(
            for: herdPublicID
        ) == reference else {
            pendingNewOwnerShareReferences.removeValue(forKey: herdPublicID)
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }

        switch remoteStatus {
        case .present:
            pendingNewOwnerShareReferences.removeValue(forKey: herdPublicID)
        case .absent:
            guard allowProvisionalAbsence, reference.shareURL == nil else {
                pendingNewOwnerShareReferences.removeValue(forKey: herdPublicID)
                throw HerdSharingActionError.ownerBridgeVerificationRequired
            }
            pendingNewOwnerShareReferences[herdPublicID] = reference
        }
        recordVerifiedOwnerShareEstablished(herdPublicID: herdPublicID)
    }

    private func recordVerifiedOwnerShareEstablished(herdPublicID: UUID) {
        let recorder = base as? any HerdSharingVerifiedOwnerShareEstablishmentRecording
        recorder?.recordVerifiedOwnerShareEstablished(herdPublicID: herdPublicID)
    }

    private func withSynchronizationGate<Result>(_ operation: () async throws -> Result) async throws -> Result {
        let token = try mutationGate.beginSynchronization()
        defer { mutationGate.endSynchronization(token) }
        return try await operation()
    }
}
