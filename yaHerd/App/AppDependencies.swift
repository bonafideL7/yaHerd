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
            mutationGate: mutationGate
        )
        let conflictReviewStore = HerdSharingConflictReviewStore()
        let cloudKitShareAdapter = CloudKitShareAdapter()

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
                shareAdapter: cloudKitShareAdapter
            )
        }
        let gatedHerdSharingRepository = GatedHerdSharingRepository(
            base: baseHerdSharingRepository,
            mutationGate: mutationGate
        )
        let herdSharingRepository = MutationPublishingHerdSharingRepository(
            base: gatedHerdSharingRepository,
            mutationCenter: mutationCenter
        )

        let bridgeCoordinator: any PublicIDRepairBridgeCoordinating
        if resolvedStorageMode == .iCloud && dataAccessMode.allowsDataMutations {
            bridgeCoordinator = DefaultPublicIDRepairBridgeCoordinator(
                herdInventory: SwiftDataPublicIDRepairHerdInventory(
                    modelContainer: modelContainer
                ),
                sharingRepository: baseHerdSharingRepository,
                storageMode: resolvedStorageMode,
                exporter: SwiftDataPublicIDRepairBridgeExporter(
                    modelContainer: modelContainer
                )
            )
        } else {
            bridgeCoordinator = LocalOnlyPublicIDRepairBridgeCoordinator()
        }
        let publicIDRepairWorker = SwiftDataPublicIDRepairService(
            modelContainer: modelContainer
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
            sampleDataSeeder: sampleDataSeeder
        )
        self.pastureFeatureDependencies = PastureFeatureDependencies(
            pastureRepository: pastureRepository,
            animalMover: animalRepository,
            fieldCheckArchiveWriter: fieldCheckRepository
        )
        self.fieldCheckFeatureDependencies = FieldCheckFeatureDependencies(
            repository: fieldCheckRepository,
            animalRepository: animalRepository,
            pastureReferenceReader: pastureRepository
        )
        self.workingSessionFeatureDependencies = WorkingSessionFeatureDependencies(
            repository: workingRepository,
            animalSummaryReader: animalRepository,
            pastureReferenceReader: pastureRepository
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
