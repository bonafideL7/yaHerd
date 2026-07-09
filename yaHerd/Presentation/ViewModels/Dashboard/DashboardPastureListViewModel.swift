import Foundation
import Observation

@MainActor
@Observable
final class DashboardPastureListViewModel {
    private(set) var items: [DashboardPastureItem] = []
    private(set) var hasLoaded = false
    private var isLoading = false
    var errorMessage: String?

    func loadIfNeeded(configuration: DashboardConfiguration, using repository: any DashboardRecordReading) {
        guard !hasLoaded else { return }
        load(configuration: configuration, using: repository)
    }

    func load(configuration: DashboardConfiguration, using repository: any DashboardRecordReading) {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            items = try LoadDashboardPastureListUseCase(repository: repository)
                .execute(configuration: configuration)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markPastureGrazedToday(
        pastureID: UUID,
        configuration: DashboardConfiguration,
        using repository: any DashboardReadWriting
    ) {
        do {
            try MarkPastureGrazedTodayUseCase(repository: repository)
                .execute(pastureID: pastureID)
            load(configuration: configuration, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func filteredItems(_ filter: DashboardPastureFilter) -> [DashboardPastureItem] {
        DashboardService().filterPastures(items, filter: filter)
    }
}
