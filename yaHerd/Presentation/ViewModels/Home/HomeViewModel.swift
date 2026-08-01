import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var snapshot: HomeSnapshot?
    private(set) var hasLoaded = false
    private var isLoading = false
    private var lastAppliedMutationSequence: UInt64 = 0
    var errorMessage: String?

    func observe(
        configuration: DashboardConfiguration,
        useCase: LoadHomeUseCase,
        mutationStream: any ApplicationMutationStreaming
    ) async {
        let startingSequence = mutationStream.currentSequence
        if !hasLoaded || lastAppliedMutationSequence < startingSequence {
            if await load(configuration: configuration, useCase: useCase) {
                lastAppliedMutationSequence = startingSequence
            }
        }

        for await event in mutationStream.events(after: startingSequence) {
            guard !Task.isCancelled else { return }
            guard event.affectedAreas.contains(.home) else { continue }

            if await load(configuration: configuration, useCase: useCase) {
                lastAppliedMutationSequence = event.sequence
            }
        }
    }

    @discardableResult
    func load(
        configuration: DashboardConfiguration,
        useCase: LoadHomeUseCase
    ) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            snapshot = try await useCase.execute(configuration: configuration)
            errorMessage = nil
            hasLoaded = true
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }
}
