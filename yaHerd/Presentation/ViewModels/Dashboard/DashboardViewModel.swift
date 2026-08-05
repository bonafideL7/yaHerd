import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var snapshot: DashboardSnapshot?
    private(set) var hasLoaded = false
    private var isLoading = false
    private var lastLoadedRevision: UInt64 = 0
    var errorMessage: String?
    var isPresentingAddAnimal = false
    var isPresentingAddPasture = false
    var isPresentingNewWorkingSession = false

    func observe(
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading,
        mutationStream: any ApplicationMutationStreaming
    ) async {
        let startingRevision = mutationStream.homeRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if await load(configuration: configuration, using: repository) {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .home,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled else { return }
            if await load(configuration: configuration, using: repository) {
                lastLoadedRevision = revision
            }
        }
    }

    func loadIfNeeded(
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading
    ) async {
        guard !hasLoaded else { return }
        _ = await load(configuration: configuration, using: repository)
    }

    @discardableResult
    func load(
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading
    ) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            snapshot = try await LoadDashboardUseCase(repository: repository)
                .execute(configuration: configuration)
            errorMessage = nil
            hasLoaded = true
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    func markPastureGrazedToday(
        pastureID: UUID,
        configuration: DashboardConfiguration,
        using repository: any DashboardReadWriting
    ) {
        let date = Date.now
        do {
            try repository.markPastureGrazedToday(id: pastureID, on: date)
            applyPastureGrazedToday(pastureID: pastureID, date: date)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
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

    private func applyPastureGrazedToday(pastureID: UUID, date: Date) {
        guard let snapshot else { return }

        let updatedPastures = snapshot.pastures.map { pasture in
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

        let updatedOverview = DashboardOverview(
            activeAnimalCount: snapshot.overview.activeAnimalCount,
            workingPenCount: snapshot.overview.workingPenCount,
            unassignedAnimalCount: snapshot.overview.unassignedAnimalCount,
            pastureCount: snapshot.overview.pastureCount,
            underutilizedPastureCount: updatedPastures.filter(\.isUnderutilized).count,
            rotationReadyPastureCount: updatedPastures.filter(\.isRotationReady).count
        )

        self.snapshot = DashboardSnapshot(
            activeSession: snapshot.activeSession,
            alerts: snapshot.alerts,
            overview: updatedOverview,
            analytics: snapshot.analytics,
            searchableAnimals: snapshot.searchableAnimals,
            pastures: updatedPastures
        )
    }
}
