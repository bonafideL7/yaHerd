import Foundation

/// Observes the application mutation stream and forwards only successful local mutations to an
/// optional side effect. Persistence repositories publish application mutations without knowing
/// whether collaboration exists; collaboration can subscribe here without becoming part of the
/// repository save path.
@MainActor
final class ApplicationMutationSyncObserver {
    typealias LocalMutationHandler = @MainActor (SharedDataMutationReason) -> Void

    private var observationTask: Task<Void, Never>?

    init(
        mutationStream: any ApplicationMutationStreaming,
        onLocalMutation: @escaping LocalMutationHandler
    ) {
        let startingSequence = mutationStream.currentSequence

        observationTask = Task { @MainActor in
            for await event in mutationStream.events(after: startingSequence) {
                guard !Task.isCancelled else { return }
                guard case .local(let reason) = event.source else { continue }
                onLocalMutation(reason)
            }
        }
    }

    isolated deinit {
        observationTask?.cancel()
        observationTask = nil
    }
}
