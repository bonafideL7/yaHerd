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
        using repository: any DashboardRecordReading
    ) {
        guard !hasLoaded else { return }
        load(kind: kind, configuration: configuration, using: repository)
    }

    func load(
        kind: DashboardAnimalListKind,
        configuration: DashboardConfiguration,
        using repository: any DashboardRecordReading
    ) {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            items = try LoadDashboardAnimalListUseCase(repository: repository)
                .execute(kind: kind, configuration: configuration)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
