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
    self.herdSharingMutationSyncScheduler = mutationSyncScheduler
    self.herdCollaborationWritePolicy = writePolicy
    self.herdSharingConflictReviewStore = conflictReviewStore
    self.cloudKitShareAdapter = cloudKitShareAdapter

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
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
    self.pastureRepository = SyncRequestingPastureRepository(
      base: pastureRepository,
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
    self.dashboardRepository = SyncRequestingDashboardRepository(
      base: dashboardRepository,
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
    self.workingRepository = SyncRequestingWorkingRepository(
      base: workingRepository,
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
    self.fieldCheckRepository = SyncRequestingFieldCheckRepository(
      base: fieldCheckRepository,
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
    self.syncDiagnosticsRepository = SwiftDataSyncDiagnosticsRepository(context: context)
    self.herdRepository = SyncRequestingHerdRepository(
      base: herdRepository,
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
    if dataAccessMode.isRecoveryMode {
      self.herdSharingRepository = RecoveryModeHerdSharingRepository()
    } else {
      self.herdSharingRepository = CoreDataHerdSharingRepository(
        context: context,
        shareAdapter: cloudKitShareAdapter
      )
    }
    self.tagColorRepository = SyncRequestingTagColorRepository(
      base: tagColorRepository,
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
    self.sampleDataSeeder = SyncRequestingSampleDataSeeder(
      base: sampleDataSeeder,
      scheduler: mutationSyncScheduler,
      writePolicy: writePolicy
    )
  }

  func seedDefaultsIfNeeded() {
    guard dataAccessMode.allowsDataMutations else { return }
    SampleDataService.seedDefaultsIfNeeded(context: context)
  }
}
