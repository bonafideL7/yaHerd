import Foundation
import SwiftData

/// Avoids constructing the Core Data/CloudKit sharing bridge until an iCloud
/// collaboration operation actually needs it. Local-only launches and tests
/// can evaluate collaboration readiness without requiring CloudKit entitlements.
@MainActor
final class DeferredCoreDataHerdSharingRepository: HerdSharingRepository,
    HerdSharingVerifiedOwnerShareEstablishmentRecording,
    HerdSharingRetainedOwnerShareCleanupManaging
{
    private let repositoryFactory: @MainActor () -> any HerdSharingRepository
    private let conflictResolverFactory: @MainActor () -> (any HerdSharingBridgeConflictResolving)?
    private let existingOwnerShareManager: @MainActor (HerdSummary, HerdStorageMode) async throws -> HerdSharingActionResult
    private let existingOwnerSharePreparation: @MainActor (HerdSummary) async throws -> Void
    private let newOwnerShareRemoteOwnerShareLookup: @MainActor () async throws -> Bool
    private let unresolvedOwnerShareResumePreflight: @MainActor (UUID) async throws -> Void
    private let ownerSharePreparation: @MainActor (HerdSharingActionResult, UUID) throws -> Void
    private let discardedOwnerShareProvenanceCleanup: @MainActor (UUID) -> Void
    private let discardedAcceptedParticipantProvenanceCleanup: @MainActor (UUID) -> Void
    private let creationGuard: any HerdSharingCreationStateGuarding
    private let localContext: ModelContext?
    private let acceptedShareImportScopeStore: HerdSharingAcceptedShareImportScopeStore
    private let remoteOwnerShareRevalidationStore: HerdSharingRemoteOwnerShareRevalidationStore
    private let sharingOperationGate = HerdSharingBridgeOperationGate()
    private var resolvedRepository: (any HerdSharingRepository)?
    private var resolvedConflictResolver: (any HerdSharingBridgeConflictResolving)?

    init(
        context: ModelContext,
        shareAdapter: CloudKitShareAdapter,
        ownershipRegistry: (any HerdSharingOwnershipRecording)? = nil,
        acceptedParticipantReferenceStore: (any HerdSharingAcceptedParticipantReferenceRecording)? = nil,
        newOwnerShareRemoteVerifier: (any HerdSharingRemoteOwnerShareVerifying)? = nil,
        swiftDataImporterFactory: (@MainActor () -> any HerdSharingImportApplying)? = nil,
        existingOwnerShareReferenceRecorder: @escaping @MainActor (CloudKitSystemShare, UUID) throws -> Void = { _, _ in },
        discardedOwnerShareReferenceCleanup: @escaping @MainActor (UUID) -> Void = { _ in },
        unresolvedOwnerShareResumePreflight: @escaping @MainActor (UUID) async throws -> Void = { _ in },
        ownerSharePreparation: @escaping @MainActor (HerdSharingActionResult, UUID) throws -> Void = { _, _ in }
    ) {
        let journal = HerdSharingBridgeJournal(
            fileURL: HerdSharingCoreDataStore.defaultStoreDirectoryURL()
                .appendingPathComponent("HerdSharingSyncJournal.json")
        )
        let resolvedOwnershipRegistry = ownershipRegistry ?? UserDefaultsHerdSharingOwnershipRegistry()
        let accountOwnershipRegistry = MirroredHerdSharingAccountOwnershipRegistry()
        let resolvedAcceptedParticipantReferenceStore = acceptedParticipantReferenceStore
            ?? UserDefaultsHerdSharingAcceptedParticipantReferenceStore()
        let acceptedShareImportScopeStore = HerdSharingAcceptedShareImportScopeStore(
            participantReferenceStore: resolvedAcceptedParticipantReferenceStore
        )
        let resolvedCreationGuard = HerdSharingCreationStateGuard(
            context: context,
            journal: journal,
            ownershipRegistry: resolvedOwnershipRegistry,
            accountOwnershipRegistry: accountOwnershipRegistry
        )
        let ownerShareRevalidationStore = HerdSharingRemoteOwnerShareRevalidationStore(
            defaults: .standard
        )
        let bundle = DeferredHerdSharingBridgeBundle(
            context: context,
            shareAdapter: shareAdapter,
            journal: journal,
            acceptedParticipantReferenceStore: resolvedAcceptedParticipantReferenceStore,
            acceptedShareImportScopeStore: acceptedShareImportScopeStore,
            acceptedParticipantProvenanceRecorder: { herdPublicID in
                resolvedOwnershipRegistry.recordParticipant(herdPublicID: herdPublicID)
            },
            swiftDataImporterFactory: swiftDataImporterFactory
        )
        let resolvedRemoteOwnerShareVerifier = newOwnerShareRemoteVerifier
            ?? CloudKitHerdSharingRemoteOwnerShareVerifier()
        repositoryFactory = { bundle.repository() }
        conflictResolverFactory = { bundle.conflictResolver() }
        existingOwnerShareManager = { herd, storageMode in
            try await bundle.manageExistingShare(herd: herd, storageMode: storageMode)
        }
        existingOwnerSharePreparation = { herd in
            let systemShare = try await bundle.existingOwnerSystemShare(for: herd)
            try existingOwnerShareReferenceRecorder(systemShare, herd.publicID)
        }
        newOwnerShareRemoteOwnerShareLookup = {
            try await resolvedRemoteOwnerShareVerifier.hasAnyOwnerShareForCurrentAccount()
        }
        discardedOwnerShareProvenanceCleanup = { herdPublicID in
            accountOwnershipRegistry.clearEstablishedOwnerShare(for: herdPublicID)
            ownerShareRevalidationStore.clear(herdPublicID)
            discardedOwnerShareReferenceCleanup(herdPublicID)
        }
        discardedAcceptedParticipantProvenanceCleanup = { herdPublicID in
            resolvedAcceptedParticipantReferenceStore.clearReference(for: herdPublicID)
        }
        self.unresolvedOwnerShareResumePreflight = unresolvedOwnerShareResumePreflight
        self.ownerSharePreparation = ownerSharePreparation
        self.acceptedShareImportScopeStore = acceptedShareImportScopeStore
        remoteOwnerShareRevalidationStore = ownerShareRevalidationStore
        creationGuard = resolvedCreationGuard
        localContext = context
    }

    init(
        repository: any HerdSharingRepository,
        creationGuard: any HerdSharingCreationStateGuarding,
        conflictResolver: (any HerdSharingBridgeConflictResolving)? = nil,
        acceptedShareImportScopeStore: HerdSharingAcceptedShareImportScopeStore? = nil,
        existingOwnerSharePreparation: @escaping @MainActor (HerdSummary) async throws -> Void = { _ in },
        newOwnerShareRemoteOwnerShareLookup: @escaping @MainActor () async throws -> Bool = { false },
        remoteOwnerShareRevalidationStore: HerdSharingRemoteOwnerShareRevalidationStore = HerdSharingRemoteOwnerShareRevalidationStore(),
        discardedOwnerShareProvenanceCleanup: @escaping @MainActor (UUID) -> Void = { _ in },
        discardedAcceptedParticipantProvenanceCleanup: @escaping @MainActor (UUID) -> Void = { _ in },
        unresolvedOwnerShareResumePreflight: @escaping @MainActor (UUID) async throws -> Void = { _ in },
        ownerSharePreparation: @escaping @MainActor (HerdSharingActionResult, UUID) throws -> Void = { _, _ in }
    ) {
        repositoryFactory = { repository }
        conflictResolverFactory = { conflictResolver }
        existingOwnerShareManager = { herd, storageMode in
            try await repository.manageExistingShare(herd: herd, storageMode: storageMode)
        }
        self.existingOwnerSharePreparation = existingOwnerSharePreparation
        self.newOwnerShareRemoteOwnerShareLookup = newOwnerShareRemoteOwnerShareLookup
        self.remoteOwnerShareRevalidationStore = remoteOwnerShareRevalidationStore
        self.discardedOwnerShareProvenanceCleanup = discardedOwnerShareProvenanceCleanup
        self.discardedAcceptedParticipantProvenanceCleanup = discardedAcceptedParticipantProvenanceCleanup
        self.unresolvedOwnerShareResumePreflight = unresolvedOwnerShareResumePreflight
        self.ownerSharePreparation = ownerSharePreparation
        self.acceptedShareImportScopeStore = acceptedShareImportScopeStore
            ?? HerdSharingAcceptedShareImportScopeStore()
        self.creationGuard = creationGuard
        localContext = nil
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
        guard let herd else { throw HerdSharingActionError.shareRootMissing }
        let access = try await repository.fetchSharingAccess(for: herd, storageMode: storageMode)

        // Public-ID repair deliberately probes manifest-planned Herd IDs before the replacement
        // SwiftData Herd exists. Preserve physical bridge observation for that read-only probe,
        // but leave creation authority unknown so every mutation/share path still fails closed.
        if try localHerdIsAbsent(for: herd.publicID) {
            return access.applyingCreationState(.unknown)
        }

        try await prepareExistingOwnerShareIfNeeded(herd: herd, access: access)
        let evaluatedAccess = try await creationGuard.evaluate(herd: herd, access: access)
        if !evaluatedAccess.hasConflictingBridgeRecords,
           try await acceptedShareImportScopeStore.hasPendingScopeForCurrentAccount()
        {
            return evaluatedAccess.applyingCreationState(.pendingBridgeOperation)
        }

        // A positive commit-boundary owner-share lookup is authoritative evidence that this
        // installation must not fall back to writable `.ready` access while its bridge/provenance
        // is still converging. Persist only a local revalidation requirement—not ownership—so the
        // block survives process recreation without leaking an account-specific ownership claim.
        if evaluatedAccess.creationState == .ready,
           remoteOwnerShareRevalidationStore.contains(herd.publicID)
        {
            if try await newOwnerShareRemoteOwnerShareLookup() {
                return evaluatedAccess.applyingCreationState(.ownerBridgeVerificationRequired)
            }
            remoteOwnerShareRevalidationStore.clear(herd.publicID)
        }
        return evaluatedAccess
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }

        let hasPendingAcceptedInvitation = try await acceptedShareImportScopeStore
            .hasPendingScopeForCurrentAccount()
        guard !hasPendingAcceptedInvitation else {
            throw HerdSharingActionError.sharingOperationPending
        }
        let access = try await fetchGuardedAccess(for: herd, storageMode: storageMode)
        _ = try await creationGuard.validateNewShare(herd: herd, access: access)

        // A missing per-Herd owner reference is not evidence that another installation did not
        // already create a CKShare. Verify the current account's private CloudKit zones immediately
        // before the only new-share commit boundary. Persist a revalidation marker before throwing
        // so failed-operation recovery and process recreation cannot republish local `.ready` access.
        if try await newOwnerShareRemoteOwnerShareLookup() {
            try remoteOwnerShareRevalidationStore.record(herd.publicID)
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
        remoteOwnerShareRevalidationStore.clear(herd.publicID)

        let result = try await repository.startSharing(herd: herd, storageMode: storageMode)
        try ownerSharePreparation(result, herd.publicID)
        return result
    }

    func manageExistingShare(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }

        let hasPendingAcceptedInvitation = try await acceptedShareImportScopeStore
            .hasPendingScopeForCurrentAccount()
        guard !hasPendingAcceptedInvitation else {
            throw HerdSharingActionError.sharingOperationPending
        }
        let rawAccess = try await fetchGuardedAccess(for: herd, storageMode: storageMode)
        let access = try await creationGuard.evaluate(herd: herd, access: rawAccess)
        switch access.creationState {
        case .existingOwnerShare:
            let result = try await existingOwnerShareManager(herd, storageMode)
            return result
        case .unresolvedBridgeRecord:
            try await unresolvedOwnerShareResumePreflight(herd.publicID)
            let result = try await repository.startSharing(herd: herd, storageMode: storageMode)
            try ownerSharePreparation(result, herd.publicID)
            return result
        case .pendingBridgeOperation:
            throw HerdSharingActionError.sharingOperationPending
        case .ownershipConfirmationRequired:
            throw HerdSharingActionError.ownershipConfirmationRequired
        case .ownerBridgeVerificationRequired:
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        case .ownerStopCleanupPending:
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        case .notOwnedByCurrentDevice:
            throw HerdSharingActionError.herdOwnershipRequired
        case .conflictingBridgeRecords:
            throw HerdSharingActionError.unresolvedSharingBridge
        case .unknown:
            throw HerdSharingActionError.sharingStateUnavailable
        case .ready, .acceptedParticipantShare:
            throw HerdSharingActionError.shareManagementUnavailable
        }
    }

    func manageRetainedOwnerShareForStopCleanup(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }
        return try await existingOwnerShareManager(herd, storageMode)
    }

    func confirmLocalHerdOwnership(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }

        let rawAccess = try await fetchGuardedAccess(for: herd, storageMode: storageMode)
        let access = try await creationGuard.confirmLocalOwnership(herd: herd, access: rawAccess)
        let nextAction: String
        switch access.creationState {
        case .ready:
            nextAction = "You can now create the owner share."
        case .pendingBridgeOperation:
            nextAction = "Recover the unfinished bridge operation before creating or resuming sharing."
        default:
            nextAction = "You can now resume the existing owner bridge."
        }
        return HerdSharingActionResult(
            title: "Local herd ownership confirmed",
            message: "This installation is now authorized to act as the local owner for this Herd root. \(nextAction)"
        )
    }

    func resetStaleOwnerSharingState(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }

        let rawAccess = try await fetchGuardedAccess(for: herd, storageMode: storageMode)
        let access = try await creationGuard.resetStaleOwnerSharingState(
            herd: herd,
            access: rawAccess
        )
        return HerdSharingActionResult(
            title: "Stale owner sharing reset",
            message: access.creationState == .unresolvedBridgeRecord
                ? "The stale owner-share provenance was reset. Resume the existing owner bridge when ready."
                : "The stale owner-share provenance was reset deliberately. This installation is now authorized to create a new owner share if CloudKit access still shows no existing bridge."
        )
    }

    func detachStaleParticipantState(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }

        let rawAccess = try await fetchGuardedAccess(for: herd, storageMode: storageMode)
        _ = try await creationGuard.detachStaleParticipantState(herd: herd, access: rawAccess)
        return HerdSharingActionResult(
            title: "Stale participation detached",
            message: "The stale participant relationship was detached because no accepted shared bridge is present. Local ownership is still unconfirmed; confirm it separately only if this retained Herd should now become independently owned by this iCloud account."
        )
    }

    func resolveBridgeConflict(
        herd: HerdSummary,
        keeping resolution: HerdSharingBridgeConflictResolution,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }

        let rawAccess = try await fetchGuardedAccess(for: herd, storageMode: storageMode)
        let evaluatedAccess = try await creationGuard.evaluate(herd: herd, access: rawAccess)
        guard evaluatedAccess.creationState == .conflictingBridgeRecords else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Sharing access no longer contains both owner and accepted shared Herd roots. Refresh before resolving the bridge conflict."
            )
        }
        guard let conflictResolver else {
            throw HerdSharingActionError.sharingStoreUnavailable(
                "The Core Data sharing bridge conflict resolver is unavailable."
            )
        }

        try await creationGuard.prepareBridgeConflictResolution(
            herd: herd,
            resolution: resolution,
            access: rawAccess
        )
        let cleanup = discardedOwnerShareProvenanceCleanup
        let acceptedCleanup = discardedAcceptedParticipantProvenanceCleanup
        let retainedAccess = try await conflictResolver.resolveBridgeConflict(
            for: herd,
            keeping: resolution,
            discardedRelationshipDidCommit: {
                switch resolution {
                case .keepAcceptedShare:
                    cleanup(herd.publicID)
                case .keepOwnerShare:
                    acceptedCleanup(herd.publicID)
                }
            }
        )
        try await prepareExistingOwnerShareIfNeeded(herd: herd, access: retainedAccess)
        let finalizedAccess = try await creationGuard.finalizeBridgeConflictResolution(
            herd: herd,
            resolution: resolution,
            access: retainedAccess
        )
        guard finalizedAccess.creationState == .pendingBridgeOperation else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "The retained bridge was not placed into import-first recovery after conflict resolution."
            )
        }

        let retainedDescription = resolution == .keepOwnerShare ? "owner share" : "accepted shared herd"
        return HerdSharingActionResult(
            title: "Bridge conflict resolved",
            message: "Kept the \(retainedDescription) and removed the conflicting bridge relationship. Run the recovery synchronization next; yaHerd will import the retained bridge before any export or sharing management is allowed."
        )
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }
        return try await repository.acceptShareInvitation(invitation, storageMode: storageMode)
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }
        let hasPendingInvitation = try await acceptedShareImportScopeStore
            .hasPendingScopeForCurrentAccount()
        let scopedHerd = hasPendingInvitation ? nil : herd
        return try await repository.importSharedBridgeData(
            herd: scopedHerd,
            storageMode: storageMode
        )
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }
        return try await repository.acceptPreventedSharedDeletes(in: review, storageMode: storageMode)
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }
        return try await repository.restoreLocalFields(selections, in: review, storageMode: storageMode)
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        try requireICloud(storageMode)
        await sharingOperationGate.acquire()
        defer { sharingOperationGate.release() }

        if try await acceptedShareImportScopeStore.hasPendingScopeForCurrentAccount() {
            return try await repository.importSharedBridgeData(
                herd: nil,
                storageMode: storageMode
            )
        }

        guard let herd else {
            return try await repository.syncSharedBridgeData(herd: nil, storageMode: storageMode)
        }
        let rawAccess = try await fetchGuardedAccess(for: herd, storageMode: storageMode)
        switch try await creationGuard.synchronizationDisposition(herd: herd, access: rawAccess) {
        case .fullSync:
            return try await repository.syncSharedBridgeData(herd: herd, storageMode: storageMode)
        case .importOnly:
            return try await repository.importSharedBridgeData(herd: herd, storageMode: storageMode)
        }
    }

    func recordVerifiedOwnerShareEstablished(herdPublicID: UUID) {
        creationGuard.recordOwnerShareEstablished(herdPublicID: herdPublicID)
    }

    private func fetchGuardedAccess(
        for herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingAccess {
        let access = try await repository.fetchSharingAccess(for: herd, storageMode: storageMode)
        try await prepareExistingOwnerShareIfNeeded(herd: herd, access: access)
        return access
    }

    private func prepareExistingOwnerShareIfNeeded(
        herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws {
        guard !access.hasConflictingBridgeRecords,
              access.bridgeLocation == .ownerPrivateStore,
              access.hasActiveSystemShare
        else { return }

        try await existingOwnerSharePreparation(herd)
    }

    private func localHerdIsAbsent(for herdPublicID: UUID) throws -> Bool {
        guard let localContext else { return false }
        var descriptor = FetchDescriptor<Herd>(
            predicate: #Predicate<Herd> { herd in
                herd.publicID == herdPublicID
            }
        )
        descriptor.fetchLimit = 1
        return try localContext.fetch(descriptor).isEmpty
    }

    private var repository: any HerdSharingRepository {
        if let resolvedRepository { return resolvedRepository }
        let repository = repositoryFactory()
        resolvedRepository = repository
        return repository
    }

    private var conflictResolver: (any HerdSharingBridgeConflictResolving)? {
        if let resolvedConflictResolver { return resolvedConflictResolver }
        let resolver = conflictResolverFactory()
        resolvedConflictResolver = resolver
        return resolver
    }

    private func requireICloud(_ storageMode: HerdStorageMode) throws {
        guard storageMode == .iCloud else { throw HerdSharingActionError.iCloudSyncRequired }
    }
}

@MainActor
final class HerdSharingRemoteOwnerShareRevalidationStore {
    private var inMemoryHerdIDs: Set<UUID> = []
    private let defaults: UserDefaults?
    private let keyPrefix: String

    init(
        defaults: UserDefaults? = nil,
        keyPrefix: String = "HerdSharingRemoteOwnerShareRevalidation"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func contains(_ herdPublicID: UUID) -> Bool {
        if inMemoryHerdIDs.contains(herdPublicID) {
            return true
        }
        return defaults?.bool(forKey: key(for: herdPublicID)) ?? false
    }

    func record(_ herdPublicID: UUID) throws {
        inMemoryHerdIDs.insert(herdPublicID)
        guard let defaults else { return }

        defaults.set(true, forKey: key(for: herdPublicID))
        _ = defaults.synchronize()
        guard defaults.bool(forKey: key(for: herdPublicID)) else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "The remote owner-share revalidation requirement could not be persisted locally. New share creation remains blocked for this process."
            )
        }
    }

    func clear(_ herdPublicID: UUID) {
        inMemoryHerdIDs.remove(herdPublicID)
        guard let defaults else { return }

        defaults.removeObject(forKey: key(for: herdPublicID))
        _ = defaults.synchronize()
    }

    private func key(for herdPublicID: UUID) -> String {
        "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
    }
}

@MainActor
private final class DeferredHerdSharingBridgeBundle {
    private let context: ModelContext
    private let shareAdapter: CloudKitShareAdapter
    private let journal: HerdSharingBridgeJournal
    private let acceptedParticipantReferenceStore: any HerdSharingAcceptedParticipantReferenceRecording
    private let acceptedShareImportScopeStore: HerdSharingAcceptedShareImportScopeStore
    private let acceptedParticipantProvenanceRecorder: @MainActor (UUID) -> Void
    private let swiftDataImporterFactory: (@MainActor () -> any HerdSharingImportApplying)?
    private var resolvedStore: HerdSharingCoreDataStore?
    private var resolvedRepository: CoreDataHerdSharingRepository?

    init(
        context: ModelContext,
        shareAdapter: CloudKitShareAdapter,
        journal: HerdSharingBridgeJournal,
        acceptedParticipantReferenceStore: any HerdSharingAcceptedParticipantReferenceRecording,
        acceptedShareImportScopeStore: HerdSharingAcceptedShareImportScopeStore,
        acceptedParticipantProvenanceRecorder: @escaping @MainActor (UUID) -> Void,
        swiftDataImporterFactory: (@MainActor () -> any HerdSharingImportApplying)?
    ) {
        self.context = context
        self.shareAdapter = shareAdapter
        self.journal = journal
        self.acceptedParticipantReferenceStore = acceptedParticipantReferenceStore
        self.acceptedShareImportScopeStore = acceptedShareImportScopeStore
        self.acceptedParticipantProvenanceRecorder = acceptedParticipantProvenanceRecorder
        self.swiftDataImporterFactory = swiftDataImporterFactory
    }

    func repository() -> any HerdSharingRepository {
        if let resolvedRepository { return resolvedRepository }
        let repository = CoreDataHerdSharingRepository(
            context: context,
            store: store(),
            swiftDataImporter: swiftDataImporterFactory?(),
            shareAdapter: shareAdapter
        )
        resolvedRepository = repository
        return repository
    }

    func existingOwnerSystemShare(for herd: HerdSummary) async throws -> CloudKitSystemShare {
        try await store().existingOwnerSystemShare(for: herd)
    }

    func manageExistingShare(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }
        let systemShare = try await existingOwnerSystemShare(for: herd)
        return HerdSharingActionResult(
            title: "Manage herd sharing",
            message: "Opened Apple's CloudKit sharing controls for the existing owner share without exporting local data first.",
            sharePresentation: shareAdapter.registerSystemShare(systemShare)
        )
    }

    func conflictResolver() -> any HerdSharingBridgeConflictResolving { store() }

    private func store() -> HerdSharingCoreDataStore {
        if let resolvedStore { return resolvedStore }
        let store = HerdSharingCoreDataStore(
            journal: journal,
            acceptedParticipantProvenanceRecorder: acceptedParticipantProvenanceRecorder,
            acceptedParticipantReferenceStore: acceptedParticipantReferenceStore,
            acceptedShareImportScopeStore: acceptedShareImportScopeStore
        )
        resolvedStore = store
        return store
    }
}

@MainActor
private final class MirroredHerdSharingAccountOwnershipRegistry: HerdSharingAccountOwnershipRecording {
    private let ubiquitous: UbiquitousHerdSharingAccountOwnershipRegistry
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        ubiquitous: UbiquitousHerdSharingAccountOwnershipRegistry = UbiquitousHerdSharingAccountOwnershipRegistry(),
        defaults: UserDefaults = .standard,
        keyPrefix: String = "LocalHerdSharingOwnerShareEstablished"
    ) {
        self.ubiquitous = ubiquitous
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func hasEstablishedOwnerShare(for herdPublicID: UUID) -> Bool {
        ubiquitous.hasEstablishedOwnerShare(for: herdPublicID)
            || defaults.bool(forKey: key(for: herdPublicID))
    }

    func recordEstablishedOwnerShare(for herdPublicID: UUID) {
        ubiquitous.recordEstablishedOwnerShare(for: herdPublicID)
        defaults.set(true, forKey: key(for: herdPublicID))
    }

    func clearEstablishedOwnerShare(for herdPublicID: UUID) {
        ubiquitous.clearEstablishedOwnerShare(for: herdPublicID)
        defaults.removeObject(forKey: key(for: herdPublicID))
    }

    private func key(for herdPublicID: UUID) -> String {
        "\(keyPrefix).\(herdPublicID.uuidString.lowercased())"
    }
}
