import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var snapshot: HomeSnapshot?
    private(set) var hasLoaded = false
    private var isLoading = false
    private var loadCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastLoadedRevision: UInt64 = 0
    private var loadedHerdID: UUID?
    private var loadedSelectionRevision: UInt64?
    var errorMessage: String?

    func observe(
        configuration: DashboardConfiguration,
        useCase: LoadHomeUseCase,
        mutationStream: any ApplicationMutationStreaming,
        selection: AppCurrentHerdSelection
    ) async {
        resetIfSelectionChanged(selection)
        guard let originatingHerdID = selection.currentHerdID else { return }
        let originatingSelectionRevision = selection.selectionRevision

        let startingRevision = mutationStream.homeRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if await load(
                configuration: configuration,
                useCase: useCase,
                selection: selection
            ), isCurrentSelection(
                selection,
                herdID: originatingHerdID,
                revision: originatingSelectionRevision
            ) {
                lastLoadedRevision = startingRevision
            }
        }

        guard !Task.isCancelled,
              isCurrentSelection(
                selection,
                herdID: originatingHerdID,
                revision: originatingSelectionRevision
              ) else { return }

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

            if await load(
                configuration: configuration,
                useCase: useCase,
                selection: selection
            ), isCurrentSelection(
                selection,
                herdID: originatingHerdID,
                revision: originatingSelectionRevision
            ) {
                lastLoadedRevision = revision
            }
        }
    }

    @discardableResult
    func load(
        configuration: DashboardConfiguration,
        useCase: LoadHomeUseCase,
        selection: AppCurrentHerdSelection
    ) async -> Bool {
        resetIfSelectionChanged(selection)
        guard let originatingHerdID = selection.currentHerdID,
              !Task.isCancelled else { return false }
        let originatingSelectionRevision = selection.selectionRevision

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

        isLoading = true
        defer {
            isLoading = false
            let waiters = loadCompletionWaiters
            loadCompletionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        do {
            let loadedSnapshot = try await useCase.execute(configuration: configuration)
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
}
