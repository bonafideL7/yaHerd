import Foundation
import Observation

@MainActor
@Observable
final class DashboardPastureListViewModel {
    private(set) var items: [DashboardPastureItem] = []
    var errorMessage: String?

    func load(configuration: DashboardConfiguration, using repository: any DashboardRepository) {
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
        using repository: any DashboardRepository
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
