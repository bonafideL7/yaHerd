import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var snapshot: HomeSnapshot?
    private(set) var hasLoaded = false
    private var isLoading = false
    var errorMessage: String?

    func loadIfNeeded(configuration: DashboardConfiguration, useCase: LoadHomeUseCase) {
        guard !hasLoaded else { return }
        load(configuration: configuration, useCase: useCase)
    }

    func load(configuration: DashboardConfiguration, useCase: LoadHomeUseCase) {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            snapshot = try useCase.execute(configuration: configuration)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
