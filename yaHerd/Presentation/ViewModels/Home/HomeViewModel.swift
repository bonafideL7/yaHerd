import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var snapshot: HomeSnapshot?
    var errorMessage: String?

    func load(configuration: DashboardConfiguration, useCase: LoadHomeUseCase) {
        do {
            snapshot = try useCase.execute(configuration: configuration)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
