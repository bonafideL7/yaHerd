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
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func markPastureGrazedToday(
        pastureID: UUID,
        configuration: DashboardConfiguration,
        using repository: any DashboardReadWriting
    ) {
        let date = Date.now
        do {
            try MarkPastureGrazedTodayUseCase(repository: repository)
                .execute(pastureID: pastureID, now: date)
            applyPastureGrazedToday(pastureID: pastureID, date: date)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func filteredItems(_ filter: DashboardPastureFilter) -> [DashboardPastureItem] {
        DashboardService().filterPastures(items, filter: filter)
    }

    private func applyPastureGrazedToday(pastureID: UUID, date: Date) {
        items = items.map { pasture in
            guard pasture.id == pastureID else { return pasture }
            return DashboardPastureItem(
                id: pasture.id,
                name: pasture.name,
                activeAnimalCount: pasture.activeAnimalCount,
                metrics: pasture.metrics,
                lastGrazedDate: date,
                restDays: pasture.restDays
            )
        }
    }
}
