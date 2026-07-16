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
    let herdRepository: any HerdRepository
    let herdSharingRepository: any HerdSharingRepository
    let herdSharingMutationSyncScheduler: HerdSharingMutationSyncScheduler
    let herdCollaborationWritePolicy: HerdCollaborationWritePolicy
    let herdSharingConflictReviewStore: HerdSharingConflictReviewStore
    let cloudKitShareAdapter: CloudKitShareAdapter

    private let context: ModelContext
    private let dataAccessMode: AppDataAccessMode

    init(
        context: ModelContext,
        tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy = .stableSortOrderWins,
        dataAccessMode: AppDataAccessMode = .readWrite
    ) {
        self.context = context
        self.dataAccessMode = dataAccessMode

        let mutationSyncScheduler = HerdSharingMutationSyncScheduler()
        let writePolicy = HerdCollaborationWritePolicy(dataAccessMode: dataAccessMode)
        let conflictReviewStore = HerdSharingConflictReviewStore()
        let cloudKitShareAdapter = CloudKitShareAdapter()

        let animalRepository = SyncRequestingAnimalRepository(
            base: SwiftDataAnimalRepository(context: context),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let pastureRepository = SyncRequestingPastureRepository(
            base: SwiftDataPastureRepository(context: context),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let dashboardRepository = SyncRequestingDashboardRepository(
            base: SwiftDataDashboardRepository(context: context),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let workingRepository = SyncRequestingWorkingRepository(
            base: SwiftDataWorkingRepository(context: context),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let fieldCheckRepository = SyncRequestingFieldCheckRepository(
            base: SwiftDataFieldCheckRepository(context: context),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let herdRepository = SyncRequestingHerdRepository(
            base: SwiftDataHerdRepository(context: context),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let tagColorRepository = SyncRequestingTagColorRepository(
            base: SwiftDataTagColorRepository(
                context: context,
                duplicateResolutionPolicy: tagColorDuplicateResolutionPolicy
            ),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let sampleDataSeeder = SyncRequestingSampleDataSeeder(
            base: AppSampleDataSeeder(context: context),
            scheduler: mutationSyncScheduler,
            writePolicy: writePolicy
        )
        let syncDiagnosticsRepository = SwiftDataSyncDiagnosticsRepository(context: context)
        let herdSharingRepository: any HerdSharingRepository
        if dataAccessMode.isRecoveryMode {
            herdSharingRepository = RecoveryModeHerdSharingRepository()
        } else {
            herdSharingRepository = CoreDataHerdSharingRepository(
                context: context,
                shareAdapter: cloudKitShareAdapter
            )
        }

        self.animalFeatureDependencies = AnimalFeatureDependencies(
            repository: animalRepository,
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
            workingProtocolTemplateReader: workingRepository
        )

        self.tagColorRepository = tagColorRepository
        self.syncDiagnosticsRepository = syncDiagnosticsRepository
        self.herdRepository = herdRepository
        self.herdSharingRepository = herdSharingRepository
        self.herdSharingMutationSyncScheduler = mutationSyncScheduler
        self.herdCollaborationWritePolicy = writePolicy
        self.herdSharingConflictReviewStore = conflictReviewStore
        self.cloudKitShareAdapter = cloudKitShareAdapter
    }

    func seedDefaultsIfNeeded() {
        guard dataAccessMode.allowsDataMutations else { return }
        SampleDataService.seedDefaultsIfNeeded(context: context)
    }
}
