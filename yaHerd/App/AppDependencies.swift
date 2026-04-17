import SwiftData
import SwiftUI

@MainActor
final class AppDependencies: ObservableObject {
    let animalRepository: any AnimalRepository
    let pastureRepository: any PastureRepository
    let dashboardRepository: any DashboardRepository
    let workingRepository: any WorkingRepository
    let fieldCheckRepository: any FieldCheckRepository

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        self.animalRepository = SwiftDataAnimalRepository(context: context)
        self.pastureRepository = SwiftDataPastureRepository(context: context)
        self.dashboardRepository = SwiftDataDashboardRepository(context: context)
        self.workingRepository = SwiftDataWorkingRepository(context: context)
        self.fieldCheckRepository = SwiftDataFieldCheckRepository(context: context)
    }

    func seedSampleDataIfNeeded() {
        SampleDataService.seedSampleDataIfNeeded(context: context)
    }

    func seedDefaultsIfNeeded() {
        SampleDataService.seedDefaultsIfNeeded(context: context)
    }
}
