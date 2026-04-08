import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var snapshot: DashboardSnapshot?
    var errorMessage: String?
    var isPresentingAddAnimal = false
    var isPresentingAddPasture = false
    var isPresentingNewWorkingSession = false

    func load(configuration: DashboardConfiguration, using repository: any DashboardRepository) {
        do {
            snapshot = try LoadDashboardUseCase(repository: repository).execute(configuration: configuration)
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
            try MarkPastureGrazedTodayUseCase(repository: repository).execute(pastureID: pastureID)
            load(configuration: configuration, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pastures(filteredBy filter: DashboardPastureFilter) -> [DashboardPastureItem] {
        guard let snapshot else { return [] }
        return DashboardService().filterPastures(snapshot.pastures, filter: filter)
    }

    func searchResults(
        matching query: String,
        formatter: (DashboardAnimalItem) -> String
    ) -> [DashboardAnimalItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard let snapshot else { return [] }

        return snapshot.searchableAnimals
            .filter { animal in
                animal.displayTagNumber.localizedCaseInsensitiveContains(trimmedQuery)
                    || formatter(animal).localizedCaseInsensitiveContains(trimmedQuery)
            }
            .prefix(10)
            .map { $0 }
    }
}
