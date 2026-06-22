import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var snapshot: HomeSnapshot?
    var errorMessage: String?

    func load(
        configuration: DashboardConfiguration,
        dashboardRepository: any DashboardRepository,
        fieldCheckRepository: any FieldCheckRepository,
        workingRepository: any WorkingRepository
    ) {
        do {
            snapshot = try LoadHomeUseCase(
                dashboardRepository: dashboardRepository,
                fieldCheckRepository: fieldCheckRepository,
                workingRepository: workingRepository
            ).execute(configuration: configuration)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
