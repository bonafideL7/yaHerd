import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var snapshot: HomeSnapshot?
    private(set) var hasLoaded = false
    private var isLoading = false
    private var lastLoadedRevision: UInt64 = 0
    var errorMessage: String?

    func observe(
        configuration: DashboardConfiguration,
        useCase: LoadHomeUseCase,
        mutationStream: any ApplicationMutationStreaming
    ) async {
        let startingRevision = mutationStream.homeRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if await load(configuration: configuration, useCase: useCase) {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .home,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled else { return }

            if await load(configuration: configuration, useCase: useCase) {
                lastLoadedRevision = revision
            }
        }
    }

    @discardableResult
    func load(
        configuration: DashboardConfiguration,
        useCase: LoadHomeUseCase
    ) async -> Bool {
        guard !isLoading, !Task.isCancelled else { return false }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let loadedSnapshot = try await useCase.execute(configuration: configuration)
            try Task.checkCancellation()
            snapshot = loadedSnapshot
            errorMessage = nil
            hasLoaded = true
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }
}
