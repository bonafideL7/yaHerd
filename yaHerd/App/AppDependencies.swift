import Foundation

@MainActor
final class AppDependencies {
    let animalFeatureDependencies: AnimalFeatureDependencies
    let pastureFeatureDependencies: PastureFeatureDependencies
    let fieldCheckFeatureDependencies: FieldCheckFeatureDependencies
    let workingSessionFeatureDependencies: WorkingSessionFeatureDependencies
    let homeFeatureDependencies: HomeFeatureDependencies

    let tagColorRepository: any TagColorRepository
    let syncDiagnosticsRepository: any SyncDiagnosticsRepository
    let publicIDRepairService: any PublicIDRepairService
    let herdRepository: any HerdRepository
    let herdSharingRepository: any HerdSharingRepository
    let applicationMutationCenter: ApplicationMutationCenter
    let herdSharingMutationSyncScheduler: HerdSharingMutationSyncScheduler
    let herdCollaborationWritePolicy: HerdCollaborationWritePolicy
    let herdDataMutationGate: HerdDataMutationGate
    let herdSharingConflictReviewStore: HerdSharingConflictReviewStore
    let cloudKitShareAdapter: CloudKitShareAdapter

    init(
        animalFeatureDependencies: AnimalFeatureDependencies,
        pastureFeatureDependencies: PastureFeatureDependencies,
        fieldCheckFeatureDependencies: FieldCheckFeatureDependencies,
        workingSessionFeatureDependencies: WorkingSessionFeatureDependencies,
        homeFeatureDependencies: HomeFeatureDependencies,
        tagColorRepository: any TagColorRepository,
        syncDiagnosticsRepository: any SyncDiagnosticsRepository,
        publicIDRepairService: any PublicIDRepairService,
        herdRepository: any HerdRepository,
        herdSharingRepository: any HerdSharingRepository,
        applicationMutationCenter: ApplicationMutationCenter,
        herdSharingMutationSyncScheduler: HerdSharingMutationSyncScheduler,
        herdCollaborationWritePolicy: HerdCollaborationWritePolicy,
        herdDataMutationGate: HerdDataMutationGate,
        herdSharingConflictReviewStore: HerdSharingConflictReviewStore,
        cloudKitShareAdapter: CloudKitShareAdapter
    ) {
        self.animalFeatureDependencies = animalFeatureDependencies
        self.pastureFeatureDependencies = pastureFeatureDependencies
        self.fieldCheckFeatureDependencies = fieldCheckFeatureDependencies
        self.workingSessionFeatureDependencies = workingSessionFeatureDependencies
        self.homeFeatureDependencies = homeFeatureDependencies
        self.tagColorRepository = tagColorRepository
        self.syncDiagnosticsRepository = syncDiagnosticsRepository
        self.publicIDRepairService = publicIDRepairService
        self.herdRepository = herdRepository
        self.herdSharingRepository = herdSharingRepository
        self.applicationMutationCenter = applicationMutationCenter
        self.herdSharingMutationSyncScheduler = herdSharingMutationSyncScheduler
        self.herdCollaborationWritePolicy = herdCollaborationWritePolicy
        self.herdDataMutationGate = herdDataMutationGate
        self.herdSharingConflictReviewStore = herdSharingConflictReviewStore
        self.cloudKitShareAdapter = cloudKitShareAdapter
    }
}

@MainActor
final class HerdSharingObservedOwnerShareReferenceStore {
    private var references: [UUID: HerdSharingRemoteOwnerShareReference] = [:]

    func reference(for herdPublicID: UUID) -> HerdSharingRemoteOwnerShareReference? {
        references[herdPublicID]
    }

    func record(
        _ reference: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID
    ) {
        references[herdPublicID] = reference
    }

    func clearReference(for herdPublicID: UUID) {
        references.removeValue(forKey: herdPublicID)
    }
}

@MainActor
enum HerdSharingExistingOwnerShareBackfill {
    static func recordObservedReference(
        _ observed: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID,
        referenceStore: any HerdSharingOwnerShareReferenceRecording
    ) throws {
        guard observed.hasVerifiableLocator,
              observed.shareOwnerAccountRecordName != nil
        else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "The existing owner share did not expose both an originating iCloud account identity and a verifiable CloudKit URL or record-zone identity. Owner-share provenance was not committed."
            )
        }

        let existing: HerdSharingRemoteOwnerShareReference?
        do {
            existing = try referenceStore.recoverableReference(for: herdPublicID)
        } catch let error as HerdSharingActionError {
            guard case .bridgeConsistencyFailed = error,
                  referenceStore.hasBackedUpUnusableReference(for: herdPublicID)
            else {
                throw error
            }
            try referenceStore.recordRecoverably(observed, for: herdPublicID)
            return
        }

        if let existing,
           sameExactIdentity(existing, observed),
           existing.shareURL != nil,
           observed.shareURL == nil
        {
            // The saved URL is a stronger locator than a provisional observation of the same exact
            // CKShare. Preserve it rather than downgrading provenance during an access refresh.
            return
        }

        try referenceStore.recordRecoverably(observed, for: herdPublicID)
    }

    static func sameExactIdentity(
        _ lhs: HerdSharingRemoteOwnerShareReference,
        _ rhs: HerdSharingRemoteOwnerShareReference
    ) -> Bool {
        lhs.shareIdentifier == rhs.shareIdentifier
            && lhs.shareRecordZoneName == rhs.shareRecordZoneName
            && lhs.shareRecordOwnerName == rhs.shareRecordOwnerName
            && lhs.shareOwnerAccountRecordName == rhs.shareOwnerAccountRecordName
    }
}
