import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var snapshot: DashboardSnapshot?
    private(set) var hasLoaded = false
    private var isLoading = false
    private var loadCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastLoadedRevision: UInt64 = 0
    private var loadedHerdID: UUID?
    private var loadedSelectionRevision: UInt64?
    var errorMessage: String?
    var isPresentingAddAnimal = false
    var isPresentingAddPasture = false
    var isPresentingNewWorkingSession = false

    func observe(
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading,
        mutationStream: any ApplicationMutationStreaming,
        selection: AppCurrentHerdSelection
    ) async {
        resetIfSelectionChanged(selection)
        guard let originatingHerdID = selection.currentHerdID else { return }
        let originatingSelectionRevision = selection.selectionRevision

        let startingRevision = mutationStream.homeRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if await loadForRevision(
                configuration: configuration,
                using: repository,
                selection: selection,
                originatingHerdID: originatingHerdID,
                originatingSelectionRevision: originatingSelectionRevision
            ) {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .home,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled,
                  isCurrentSelection(
                    selection,
                    herdID: originatingHerdID,
                    revision: originatingSelectionRevision
                  ) else { return }
            if await loadForRevision(
                configuration: configuration,
                using: repository,
                selection: selection,
                originatingHerdID: originatingHerdID,
                originatingSelectionRevision: originatingSelectionRevision
            ) {
                lastLoadedRevision = revision
            }
        }
    }

    func loadIfNeeded(
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading,
        selection: AppCurrentHerdSelection
    ) async {
        resetIfSelectionChanged(selection)
        guard !hasLoaded else { return }
        _ = await load(configuration: configuration, using: repository, selection: selection)
    }

    @discardableResult
    func load(
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading,
        selection: AppCurrentHerdSelection
    ) async -> Bool {
        resetIfSelectionChanged(selection)
        guard let originatingHerdID = selection.currentHerdID,
              !isLoading, !Task.isCancelled else { return false }
        let originatingSelectionRevision = selection.selectionRevision

        isLoading = true
        defer {
            isLoading = false
            let waiters = loadCompletionWaiters
            loadCompletionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        do {
            let loadedSnapshot = try await LoadDashboardUseCase(repository: repository)
                .execute(configuration: configuration)
            try Task.checkCancellation()
            guard isCurrentSelection(
                selection,
                herdID: originatingHerdID,
                revision: originatingSelectionRevision
            ) else { return false }
            snapshot = loadedSnapshot
            errorMessage = nil
            hasLoaded = true
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled,
                  isCurrentSelection(
                    selection,
                    herdID: originatingHerdID,
                    revision: originatingSelectionRevision
                  ) else { return false }
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    func markPastureGrazedToday(
        pastureID: UUID,
        configuration: DashboardConfiguration,
        using repository: any PastureGrazingMarking
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

    private func loadForRevision(
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading,
        selection: AppCurrentHerdSelection,
        originatingHerdID: UUID,
        originatingSelectionRevision: UInt64
    ) async -> Bool {
        while isLoading {
            await waitForCurrentLoad()
            guard !Task.isCancelled,
                  isCurrentSelection(
                    selection,
                    herdID: originatingHerdID,
                    revision: originatingSelectionRevision
                  ) else { return false }
        }

        guard isCurrentSelection(
            selection,
            herdID: originatingHerdID,
            revision: originatingSelectionRevision
        ) else { return false }
        return await load(configuration: configuration, using: repository, selection: selection)
    }

    private func resetIfSelectionChanged(_ selection: AppCurrentHerdSelection) {
        guard loadedHerdID != selection.currentHerdID ||
              loadedSelectionRevision != selection.selectionRevision else { return }
        loadedHerdID = selection.currentHerdID
        loadedSelectionRevision = selection.selectionRevision
        snapshot = nil
        hasLoaded = false
        lastLoadedRevision = 0
        errorMessage = nil
    }

    private func isCurrentSelection(
        _ selection: AppCurrentHerdSelection,
        herdID: UUID,
        revision: UInt64
    ) -> Bool {
        selection.currentHerdID == herdID &&
            selection.selectionRevision == revision
    }

    private func waitForCurrentLoad() async {
        guard isLoading else { return }

        await withCheckedContinuation { continuation in
            if isLoading {
                loadCompletionWaiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
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
