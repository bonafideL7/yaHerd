import Foundation
import Observation

@MainActor
@Observable
final class DashboardAnimalListViewModel {
    private(set) var items: [DashboardAnimalItem] = []
    private(set) var hasLoaded = false
    private var isLoading = false
    var errorMessage: String?

    func loadIfNeeded(
        kind: DashboardAnimalListKind,
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading
    ) async {
        guard !hasLoaded else { return }
        await load(kind: kind, configuration: configuration, using: repository)
    }

    func load(
        kind: DashboardAnimalListKind,
        configuration: DashboardConfiguration,
        using repository: any DashboardQueryReading
    ) async {
        guard !isLoading, !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedItems = try await LoadDashboardAnimalListUseCase(repository: repository)
                .execute(kind: kind, configuration: configuration)
            try Task.checkCancellation()
            items = loadedItems
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
