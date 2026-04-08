import Foundation
import Observation

@MainActor
@Observable
final class DashboardAnimalListViewModel {
    private(set) var items: [DashboardAnimalItem] = []
    var errorMessage: String?

    func load(
        kind: DashboardAnimalListKind,
        configuration: DashboardConfiguration,
        using repository: any DashboardRepository
    ) {
        do {
            items = try LoadDashboardAnimalListUseCase(repository: repository)
                .execute(kind: kind, configuration: configuration)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
