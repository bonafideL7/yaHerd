import SwiftData

final class AppSampleDataSeeder: SampleDataSeeding {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func seedSampleDataIfNeeded() {
        SampleDataService.seedSampleDataIfNeeded(context: context)
    }

    func seedLargeSampleDataIfNeeded() {
        SampleLargeDataService.seedIfNeeded(context: context)
    }
}
