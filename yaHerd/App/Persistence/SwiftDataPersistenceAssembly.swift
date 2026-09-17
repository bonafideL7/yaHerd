import SwiftData

@MainActor
final class SwiftDataPersistenceAssembly: PersistenceAssembly {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func makeDependencies(
        dataAccessMode: AppDataAccessMode
    ) -> AppDependencies {
        let context = modelContainer.mainContext
        let mutationCenter = ApplicationMutationCenter()
        let mutationPipeline = ApplicationMutationPipeline(center: mutationCenter)
        let writePolicy = LocalDataWritePolicy(dataAccessMode: dataAccessMode)

        // Each read model actor owns its own ModelContext. Separate actors allow
        // independent home queries to run concurrently instead of serializing on
        // the main context or on one shared actor executor.
        let dashboardQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)
        let homeFieldCheckQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)
        let homeWorkingQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)
        let animalListQueryReader = SwiftDataReadModelActor(modelContainer: modelContainer)

        let animalRepository = MutationPublishingAnimalRepository(
            base: SwiftDataAnimalRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let animalListRepository = BackgroundQueryingAnimalListRepository(
            base: animalRepository,
            queryReader: animalListQueryReader
        )
        let pastureRepository = MutationPublishingPastureRepository(
            base: SwiftDataPastureRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let dashboardRepository = MutationPublishingDashboardRepository(
            base: SwiftDataDashboardRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let workingRepository = MutationPublishingWorkingRepository(
            base: SwiftDataWorkingRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let fieldCheckRepository = MutationPublishingFieldCheckRepository(
            base: SwiftDataFieldCheckRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let herdRepository = MutationPublishingHerdRepository(
            base: SwiftDataHerdRepository(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let tagColorRepository = MutationPublishingTagColorRepository(
            base: SwiftDataTagColorRepository(
                context: context,
                duplicateResolutionPolicy: .stableSortOrderWins
            ),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
        )
        let sampleDataSeeder = MutationPublishingSampleDataSeeder(
            base: AppSampleDataSeeder(context: context),
            mutationRecorder: mutationPipeline,
            writePolicy: writePolicy
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
            herdRepository: herdRepository,
            applicationMutationCenter: mutationCenter
        )
    }
}
