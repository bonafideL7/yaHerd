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
    let applicationMutationCenter: ApplicationMutationCenter
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

        let mutationCenter = ApplicationMutationCenter()
        let mutationSyncScheduler = HerdSharingMutationSyncScheduler()
        let mutationPipeline = ApplicationMutationPipeline(
            center: mutationCenter,
            sharingScheduler: mutationSyncScheduler
        )
        let writePolicy = HerdCollaborationWritePolicy(dataAccessMode: dataAccessMode)
        let conflictReviewStore = HerdSharingConflictReviewStore()
        let cloudKitShareAdapter = CloudKitShareAdapter()

        let dashboardReadModel = SwiftDataReadModelActor(modelContainer: context.container)
        let fieldCheckReadModel = SwiftDataReadModelActor(modelContainer: context.container)
        let workingReadModel = SwiftDataReadModelActor(modelContainer: context.container)
        let animalListReadModel = SwiftDataReadModelActor(modelContainer: context.container)

        let synchronizedAnimalRepository = SyncRequestingAnimalRepository(
            base: SwiftDataAnimalRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let animalRepository = ReadModelBackedAnimalRepository(
            base: synchronizedAnimalRepository,
            animalListReadModel: animalListReadModel
        )
        let pastureRepository = SyncRequestingPastureRepository(
            base: SwiftDataPastureRepository(context: context),
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
        let syncDiagnosticsRepository = SwiftDataSyncDiagnosticsRepository(context: context)

        let baseHerdSharingRepository: any HerdSharingRepository
        if dataAccessMode.isRecoveryMode {
            baseHerdSharingRepository = RecoveryModeHerdSharingRepository()
        } else {
            baseHerdSharingRepository = CoreDataHerdSharingRepository(
                context: context,
                shareAdapter: cloudKitShareAdapter
            )
        }
        let herdSharingRepository = MutationPublishingHerdSharingRepository(
            base: baseHerdSharingRepository,
            mutationCenter: mutationCenter
        )

        self.animalFeatureDependencies = AnimalFeatureDependencies(
            repository: animalRepository,
            listReadModel: animalListReadModel,
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
            dashboardReadModel: dashboardReadModel,
            fieldCheckReadModel: fieldCheckReadModel,
            workingReadModel: workingReadModel,
            mutationStream: mutationCenter
        )

        self.tagColorRepository = tagColorRepository
        self.syncDiagnosticsRepository = syncDiagnosticsRepository
        self.herdRepository = herdRepository
        self.herdSharingRepository = herdSharingRepository
        self.applicationMutationCenter = mutationCenter
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
