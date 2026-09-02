import Foundation
import SwiftData

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

    private let context: ModelContext
    private let dataAccessMode: AppDataAccessMode

    convenience init(
        context: ModelContext,
        tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy = .stableSortOrderWins,
        dataAccessMode: AppDataAccessMode = .readWrite,
        storageMode: HerdStorageMode? = nil
    ) {
        self.init(
            modelContainer: context.container,
            tagColorDuplicateResolutionPolicy: tagColorDuplicateResolutionPolicy,
            dataAccessMode: dataAccessMode,
            storageMode: storageMode
        )
    }

    init(
        modelContainer: ModelContainer,
        tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy = .stableSortOrderWins,
        dataAccessMode: AppDataAccessMode = .readWrite,
        storageMode: HerdStorageMode? = nil
    ) {
        let context = modelContainer.mainContext
        self.context = context
        self.dataAccessMode = dataAccessMode
        let resolvedStorageMode = storageMode ?? Self.inferredStorageMode(
            dataAccessMode: dataAccessMode
        )

        let mutationCenter = ApplicationMutationCenter()
        let mutationSyncScheduler = HerdSharingMutationSyncScheduler()
        let mutationPipeline = ApplicationMutationPipeline(
            center: mutationCenter,
            sharingScheduler: mutationSyncScheduler
        )
        let mutationGate = HerdDataMutationGate()
        let writePolicy = HerdCollaborationWritePolicy(
            dataAccessMode: dataAccessMode,
            mutationGate: mutationGate,
            requiresInitialAccessVerification: resolvedStorageMode == .iCloud
                && dataAccessMode.allowsDataMutations
        )
        let conflictReviewStore = HerdSharingConflictReviewStore()
        let cloudKitShareAdapter = CloudKitShareAdapter()
        let ownerShareReferenceStore = MirroredHerdSharingOwnerShareReferenceStore()
        let observedOwnerShareReferenceStore = HerdSharingObservedOwnerShareReferenceStore()
        let remoteOwnerShareVerifier = CloudKitHerdSharingRemoteOwnerShareVerifier()
        let participantOwnershipRegistry = MirroredHerdSharingOwnershipRegistry()
        let acceptedParticipantReferenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore()

        // Each read model actor owns its own ModelContext. Separate actors allow
        // independent home queries to run concurrently instead of serializing on
        // the main context or on one shared actor executor.
        let dashboardQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)
        let homeFieldCheckQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)
        let homeWorkingQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)
        let animalListQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)

        let animalRepository = SyncRequestingAnimalRepository(
            base: SwiftDataAnimalRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let animalListRepository = BackgroundQueryingAnimalListRepository(
            base: animalRepository,
            queryReader: animalListQueryReader
        )
        let pastureRepository = SyncRequestingPastureRepository(
            base: SwiftDataPastureRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let dashboardRepository = SyncRequestingDashboardRepository(
            base: SwiftDataDashboardRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let workingRepository = SyncRequestingWorkingRepository(
            base: SwiftDataWorkingRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let fieldCheckRepository = SyncRequestingFieldCheckRepository(
            base: SwiftDataFieldCheckRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let herdRepository = SyncRequestingHerdRepository(
            base: SwiftDataHerdRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let tagColorRepository = SyncRequestingTagColorRepository(
            base: SwiftDataTagColorRepository(
                context: context,
                duplicateResolutionPolicy: tagColorDuplicateResolutionPolicy
            ),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let sampleDataSeeder = SyncRequestingSampleDataSeeder(
            base: AppSampleDataSeeder(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )

        let baseHerdSharingRepository: any HerdSharingRepository
        if dataAccessMode.isRecoveryMode {
            baseHerdSharingRepository = RecoveryModeHerdSharingRepository()
        } else {
            baseHerdSharingRepository = DeferredCoreDataHerdSharingRepository(
                context: context,
                shareAdapter: cloudKitShareAdapter,
                ownershipRegistry: participantOwnershipRegistry,
                acceptedParticipantReferenceStore: acceptedParticipantReferenceStore,
                newOwnerShareRemoteVerifier: remoteOwnerShareVerifier,
                swiftDataImporterFactory: {
                    MutationPublishingHerdSharingImporter(
                        base: SwiftDataHerdSharingActor(modelContainer: modelContainer),
                        mutationCenter: mutationCenter
                    )
                },
                existingOwnerShareReferenceRecorder: { systemShare, herdPublicID in
                    let share = systemShare.share
                    let zoneID = share.recordID.zoneID
                    observedOwnerShareReferenceStore.record(
                        HerdSharingRemoteOwnerShareReference(
                            shareURL: share.url,
                            shareIdentifier: share.recordID.recordName,
                            shareRecordZoneName: zoneID.zoneName,
                            shareRecordOwnerName: zoneID.ownerName,
                            shareOwnerAccountRecordName: share.currentUserParticipant?.userIdentity.userRecordID?.recordName
                        ),
                        for: herdPublicID
                    )
                },
                discardedOwnerShareReferenceCleanup: { herdPublicID in
                    ownerShareReferenceStore.clearReference(for: herdPublicID)
                    observedOwnerShareReferenceStore.clearReference(for: herdPublicID)
                },
                unresolvedOwnerShareResumePreflight: { herdPublicID in
                    try await HerdSharingOwnerShareProvenance.verifyRecordedShareIsAbsent(
                        for: herdPublicID,
                        referenceStore: ownerShareReferenceStore,
                        remoteVerifier: remoteOwnerShareVerifier
                    )
                },
                ownerSharePreparation: { result, herdPublicID in
                    guard let presentation = result.sharePresentation,
                          HerdSharingOwnerShareProvenance.recordPresentationReferenceIfVerifiable(
                            presentation,
                            herdPublicID: herdPublicID,
                            referenceStore: ownerShareReferenceStore
                          )
                    else {
                        throw HerdSharingActionError.bridgeConsistencyFailed(
                            "Owner-share creation did not expose an exact CloudKit URL or record-zone identity. The owner-share provenance marker was not committed."
                        )
                    }
                }
            )
        }
        let gatedHerdSharingRepository = GatedHerdSharingRepository(
            base: baseHerdSharingRepository,
            mutationGate: mutationGate,
            ownerShareReferenceStore: ownerShareReferenceStore,
            remoteOwnerShareVerifier: remoteOwnerShareVerifier,
            acceptedParticipantReferenceStore: acceptedParticipantReferenceStore,
            observedOwnerShareReferenceProvider: { herdPublicID in
                observedOwnerShareReferenceStore.reference(for: herdPublicID)
            },
            savedOwnerShareObserverInstaller: { request, recorder in
                guard let systemShare = cloudKitShareAdapter.systemShare(for: request) else {
                    return false
                }
                systemShare.observePersistedShare { shareURL, shareIdentifier in
                    recorder.record(
                        shareURL: shareURL,
                        shareIdentifier: shareIdentifier
                    )
                }
                return true
            }
        )
        let herdSharingRepository = MutationPublishingHerdSharingRepository(
            base: gatedHerdSharingRepository,
            mutationCenter: mutationCenter,
            writePolicy: writePolicy,
            herdRepository: herdRepository,
            ownerShareSystemShareResolver: { request in
                cloudKitShareAdapter.systemShare(for: request)
            }
        )

        let bridgeCoordinator: any PublicIDRepairBridgeCoordinating
        if resolvedStorageMode == .iCloud && dataAccessMode.allowsDataMutations {
            // Repair preparation must observe the physical Core Data bridge without requiring a
            // unique/healthy SwiftData Herd graph first. Reuse this repair-specific store for both
            // read-only access observation and ownership-safe convergence so both phases inspect
            // the same bridge state. Mutation authority is fetched independently through the
            // normal guarded sharing repository immediately before repair can change either graph.
            let publicIDRepairBridgeStore = HerdSharingCoreDataStore()
            let publicIDRepairObservationRepository = PublicIDRepairBridgeObservationRepository(
                accessReader: publicIDRepairBridgeStore
            )
            let publicIDRepairImporter = MutationPublishingHerdSharingImporter(
                base: SwiftDataHerdSharingActor(modelContainer: modelContainer),
                mutationCenter: mutationCenter
            )
            bridgeCoordinator = DefaultPublicIDRepairBridgeCoordinator(
                herdInventory: SwiftDataPublicIDRepairHerdInventory(
                    modelContainer: modelContainer
                ),
                sharingRepository: publicIDRepairObservationRepository,
                mutationAuthorityRepository: herdSharingRepository,
                storageMode: resolvedStorageMode,
                exporter: SwiftDataPublicIDRepairBridgeExporter(
                    modelContainer: modelContainer,
                    exportReader: publicIDRepairImporter,
                    importer: publicIDRepairImporter,
                    bridgeStore: PublicIDRepairOwnershipSafeBridgeStore(
                        base: publicIDRepairBridgeStore
                    )
                )
            )
        } else {
            bridgeCoordinator = LocalOnlyPublicIDRepairBridgeCoordinator()
        }
        let basePublicIDRepairWorker = SwiftDataPublicIDRepairService(
            modelContainer: modelContainer
        )
        let publicIDRepairWorker = MutationPublishingPublicIDRepairTransactionalService(
            base: basePublicIDRepairWorker,
            mutationCenter: mutationCenter
        )
        let publicIDRepairService = CoordinatedPublicIDRepairService(
            worker: publicIDRepairWorker,
            mutationGate: mutationGate,
            bridgeCoordinator: bridgeCoordinator
        )
        let syncDiagnosticsRepository = SwiftDataSyncDiagnosticsRepository(
            context: context,
            publicIDRepairService: publicIDRepairService
        )

        self.animalFeatureDependencies = AnimalFeatureDependencies(
            listRepository: animalListRepository,
            listQueryReader: animalListQueryReader,
            editorRepository: animalRepository,
            detailRepository: animalRepository,
            timelineReader: animalRepository,
            parentOptionReader: animalRepository,
            healthRecordAdder: animalRepository,
            pregnancyCheckAdder: animalRepository,
            pastureReferenceReader: pastureRepository,
            sampleDataSeeder: sampleDataSeeder,
            mutationStream: mutationCenter
        )
        self.pastureFeatureDependencies = PastureFeatureDependencies(
            pastureRepository: pastureRepository,
            animalMover: animalRepository,
            fieldCheckArchiveWriter: fieldCheckRepository,
            mutationStream: mutationCenter
        )
        self.fieldCheckFeatureDependencies = FieldCheckFeatureDependencies(
            repository: fieldCheckRepository,
            animalRepository: animalRepository,
            pastureReferenceReader: pastureRepository,
            mutationStream: mutationCenter
        )
        self.workingSessionFeatureDependencies = WorkingSessionFeatureDependencies(
            repository: workingRepository,
            animalSummaryReader: animalRepository,
            pastureReferenceReader: pastureRepository,
            mutationStream: mutationCenter
        )
        self.homeFeatureDependencies = HomeFeatureDependencies(
            dashboardReader: dashboardRepository,
            fieldCheckOverviewReader: fieldCheckRepository,
            dashboardQueryReader: dashboardQueryReader,
            homeFieldCheckQueryReader: homeFieldCheckQueryReader,
            homeWorkingQueryReader: homeWorkingQueryReader,
            mutationStream: mutationCenter
        )

        self.tagColorRepository = tagColorRepository
        self.syncDiagnosticsRepository = syncDiagnosticsRepository
        self.publicIDRepairService = publicIDRepairService
        self.herdRepository = herdRepository
        self.herdSharingRepository = herdSharingRepository
        self.applicationMutationCenter = mutationCenter
        self.herdSharingMutationSyncScheduler = mutationSyncScheduler
        self.herdCollaborationWritePolicy = writePolicy
        self.herdDataMutationGate = mutationGate
        self.herdSharingConflictReviewStore = conflictReviewStore
        self.cloudKitShareAdapter = cloudKitShareAdapter
    }

    func seedDefaultsIfNeeded() {
        guard dataAccessMode.allowsDataMutations else { return }
        SampleDataService.seedDefaultsIfNeeded(context: context)
    }

    private static func inferredStorageMode(
        dataAccessMode: AppDataAccessMode
    ) -> HerdStorageMode {
        guard dataAccessMode.allowsDataMutations else { return .localOnly }
        return AppLaunchDiagnostics.snapshot().actualStorageMode == .iCloud
            ? .iCloud
            : .localOnly
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