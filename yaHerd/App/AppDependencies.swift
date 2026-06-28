import SwiftData
import SwiftUI

@MainActor
final class AppDependencies: ObservableObject {
    let animalRepository: any AnimalRepository
    let pastureRepository: any PastureRepository
    let dashboardRepository: any DashboardRepository
    let workingRepository: any WorkingRepository
    let fieldCheckRepository: any FieldCheckRepository
    let tagColorRepository: any TagColorRepository
    let syncDiagnosticsRepository: any SyncDiagnosticsRepository
    let sampleDataSeeder: any SampleDataSeeding

    private let context: ModelContext

    init(
        context: ModelContext,
        tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy = .stableSortOrderWins
    ) {
        self.context = context
        self.animalRepository = SwiftDataAnimalRepository(context: context)
        self.pastureRepository = SwiftDataPastureRepository(context: context)
        self.dashboardRepository = SwiftDataDashboardRepository(context: context)
        self.workingRepository = SwiftDataWorkingRepository(context: context)
        self.fieldCheckRepository = SwiftDataFieldCheckRepository(context: context)
        self.syncDiagnosticsRepository = SwiftDataSyncDiagnosticsRepository(context: context)
        self.tagColorRepository = SwiftDataTagColorRepository(
            context: context,
            duplicateResolutionPolicy: tagColorDuplicateResolutionPolicy
        )
        self.sampleDataSeeder = AppSampleDataSeeder(context: context)
    }

    func seedDefaultsIfNeeded() {
        SampleDataService.seedDefaultsIfNeeded(context: context)
    }
}
