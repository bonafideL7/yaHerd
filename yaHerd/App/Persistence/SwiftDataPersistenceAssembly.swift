import Foundation
import SwiftData

@MainActor
final class SwiftDataPersistenceAssembly: PersistenceAssembly {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func makeDependencies(
        tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy,
        dataAccessMode: AppDataAccessMode,
        storageMode: HerdStorageMode
    ) -> AppDependencies {
        let context = modelContainer.mainContext
        let mutationCenter = ApplicationMutationCenter()
        let mutationSyncScheduler = HerdSharingMutationSyncScheduler()
        let mutationPipeline = ApplicationMutationPipeline(
            center: mutationCenter,
            sharingScheduler: mutationSyncScheduler
        )
        let mutationGate = HerdDataMutationGate()
        let participantOwnershipRegistry = MirroredHerdSharingOwnershipRegistry()
        let acceptedParticipantReferenceStore = MirroredHerdSharingAcceptedParticipantReferenceStore()
        let accountOwnershipRegistry = UbiquitousHerdSharingAccountOwnershipRegistry()
        let writePolicy = HerdCollaborationWritePolicy(
            dataAccessMode: dataAccessMode,
            mutationGate: mutationGate,
            requiresInitialAccessVerification: Self.requiresInitialSharingAccessVerification(
                context: context,
                storageMode: storageMode,
                dataAccessMode: dataAccessMode,
                ownershipRegistry: participantOwnershipRegistry,
                acceptedParticipantReferenceStore: acceptedParticipantReferenceStore,
                accountOwnershipRegistry: accountOwnershipRegistry
            )
        )
        let conflictReviewStore = HerdSharingConflictReviewStore()
        let cloudKitShareAdapter = CloudKitShareAdapter()
        let ownerShareReferenceStore = MirroredHerdSharingOwnerShareReferenceStore()
        let observedOwnerShareReferenceStore = HerdSharingObservedOwnerShareReferenceStore()
        let remoteOwnerShareVerifier = CloudKitHerdSharingRemoteOwnerShareVerifier()

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
                        base: SwiftDataHerdSharingActor(modelContainer: self.modelContainer),
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
                                ?? share.owner.userIdentity.userRecordID?.recordName
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
        if storageMode == .iCloud && dataAccessMode.allowsDataMutations {
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
                storageMode: storageMode,
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

        return AppDependencies(
            animalFeatureDependencies: AnimalFeatureDependencies(
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
            ),
            pastureFeatureDependencies: PastureFeatureDependencies(
                pastureRepository: pastureRepository,
                animalMover: animalRepository,
                fieldCheckArchiveWriter: fieldCheckRepository,
                mutationStream: mutationCenter
            ),
            fieldCheckFeatureDependencies: FieldCheckFeatureDependencies(
                repository: fieldCheckRepository,
                animalRepository: animalRepository,
                pastureReferenceReader: pastureRepository,
                mutationStream: mutationCenter
            ),
            workingSessionFeatureDependencies: WorkingSessionFeatureDependencies(
                repository: workingRepository,
                animalSummaryReader: animalRepository,
                pastureReferenceReader: pastureRepository,
                mutationStream: mutationCenter
            ),
            homeFeatureDependencies: HomeFeatureDependencies(
                dashboardReader: dashboardRepository,
                fieldCheckOverviewReader: fieldCheckRepository,
                dashboardQueryReader: dashboardQueryReader,
                homeFieldCheckQueryReader: homeFieldCheckQueryReader,
                homeWorkingQueryReader: homeWorkingQueryReader,
                mutationStream: mutationCenter
            ),
            tagColorRepository: tagColorRepository,
            syncDiagnosticsRepository: syncDiagnosticsRepository,
            publicIDRepairService: publicIDRepairService,
            herdRepository: herdRepository,
            herdSharingRepository: herdSharingRepository,
            applicationMutationCenter: mutationCenter,
            herdSharingMutationSyncScheduler: mutationSyncScheduler,
            herdCollaborationWritePolicy: writePolicy,
            herdDataMutationGate: mutationGate,
            herdSharingConflictReviewStore: conflictReviewStore,
            cloudKitShareAdapter: cloudKitShareAdapter
        )
    }

    private static func requiresInitialSharingAccessVerification(
        context: ModelContext,
        storageMode: HerdStorageMode,
        dataAccessMode: AppDataAccessMode,
        ownershipRegistry: any HerdSharingOwnershipRecording,
        acceptedParticipantReferenceStore: any HerdSharingAcceptedParticipantReferenceRecording,
        accountOwnershipRegistry: any HerdSharingAccountOwnershipRecording
    ) -> Bool {
        guard storageMode == .iCloud, dataAccessMode.allowsDataMutations else { return false }

        guard let herd = try? SwiftDataHerdRepository(context: context).fetchCurrentHerd() else {
            return true
        }

        let localOwnerHistoryKey = "LocalHerdSharingOwnerShareEstablished.\(herd.publicID.uuidString.lowercased())"
        let hasMirroredOwnerHistory = accountOwnershipRegistry.hasEstablishedOwnerShare(for: herd.publicID)
            || UserDefaults.standard.bool(forKey: localOwnerHistoryKey)

        // Owner-account history is the same precedence used by HerdSharingCreationStateGuard for a
        // missing bridge. It is an owner-recovery problem: sharing/export remains guarded, but an
        // older mirrored participant marker must not convert ordinary local field work into a
        // launch-wide CloudKit dependency.
        if hasMirroredOwnerHistory {
            return false
        }

        // Without owner history, durable participant/detachment provenance remains fail-closed.
        switch ownershipRegistry.ownership(for: herd.publicID) {
        case .participant?, .detachedParticipant?:
            return true
        case .owner?, nil:
            break
        }

        if acceptedParticipantReferenceStore.hasConflictingReference(for: herd.publicID)
            || acceptedParticipantReferenceStore.reference(for: herd.publicID) != nil
        {
            return true
        }

        return false
    }
}
