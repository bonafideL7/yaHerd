import SwiftData

@MainActor
final class AppDependencies {
    let animalRepository: any AnimalRepository
    let pastureRepository: any PastureRepository
    let dashboardRepository: any DashboardRepository
    let workingRepository: any WorkingRepository
    let fieldCheckRepository: any FieldCheckRepository
    let tagColorRepository: any TagColorRepository
    let syncDiagnosticsRepository: any SyncDiagnosticsRepository
    let herdRepository: any HerdRepository
    let herdSharingRepository: any HerdSharingRepository
    let sampleDataSeeder: any SampleDataSeeding
    let herdSharingMutationSyncScheduler: HerdSharingMutationSyncScheduler

    private let context: ModelContext

    init(
        context: ModelContext,
        tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy = .stableSortOrderWins
    ) {
        self.context = context
        let mutationSyncScheduler = HerdSharingMutationSyncScheduler()
        self.herdSharingMutationSyncScheduler = mutationSyncScheduler

        let animalRepository = SwiftDataAnimalRepository(context: context)
        let pastureRepository = SwiftDataPastureRepository(context: context)
        let dashboardRepository = SwiftDataDashboardRepository(context: context)
        let workingRepository = SwiftDataWorkingRepository(context: context)
        let fieldCheckRepository = SwiftDataFieldCheckRepository(context: context)
        let herdRepository = SwiftDataHerdRepository(context: context)
        let tagColorRepository = SwiftDataTagColorRepository(
            context: context,
            duplicateResolutionPolicy: tagColorDuplicateResolutionPolicy
        )
        let sampleDataSeeder = AppSampleDataSeeder(context: context)

        self.animalRepository = SyncRequestingAnimalRepository(
            base: animalRepository,
            scheduler: mutationSyncScheduler
        )
        self.pastureRepository = SyncRequestingPastureRepository(
            base: pastureRepository,
            scheduler: mutationSyncScheduler
        )
        self.dashboardRepository = SyncRequestingDashboardRepository(
            base: dashboardRepository,
            scheduler: mutationSyncScheduler
        )
        self.workingRepository = SyncRequestingWorkingRepository(
            base: workingRepository,
            scheduler: mutationSyncScheduler
        )
        self.fieldCheckRepository = SyncRequestingFieldCheckRepository(
            base: fieldCheckRepository,
            scheduler: mutationSyncScheduler
        )
        self.syncDiagnosticsRepository = SwiftDataSyncDiagnosticsRepository(context: context)
        self.herdRepository = SyncRequestingHerdRepository(
            base: herdRepository,
            scheduler: mutationSyncScheduler
        )
        self.herdSharingRepository = CoreDataHerdSharingRepository(context: context)
        self.tagColorRepository = SyncRequestingTagColorRepository(
            base: tagColorRepository,
            scheduler: mutationSyncScheduler
        )
        self.sampleDataSeeder = SyncRequestingSampleDataSeeder(
            base: sampleDataSeeder,
            scheduler: mutationSyncScheduler
        )
    }

    func seedDefaultsIfNeeded() {
        SampleDataService.seedDefaultsIfNeeded(context: context)
    }
}
