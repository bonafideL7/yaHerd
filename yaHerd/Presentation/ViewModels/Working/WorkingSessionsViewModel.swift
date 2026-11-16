import Foundation

@MainActor
final class WorkingSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkingSessionSummary] = []
    @Published var errorMessage: String?

    private var repository: any WorkingSessionsRepository
    private var hasLoaded = false
    private var lastLoadedRevision: UInt64 = 0

    init(repository: any WorkingSessionsRepository) {
        self.repository = repository
    }

    func configure(repository: any WorkingSessionsRepository) {
        self.repository = repository
    }

    func observe(mutationStream: any ApplicationMutationStreaming) async {
        let startingRevision = mutationStream.workingSessionRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if load() {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .workingSessions,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled else { return }
            if load() {
                lastLoadedRevision = revision
            }
        }
    }

    /// A queued delete may not start after the active Herd changes. Once a
    /// repository write begins, it retains its original Herd; only refresh
    /// the list when that same Herd remains active after the write completes.
    @discardableResult
    func deleteSession(
        id: UUID,
        originatingHerdID: UUID,
        currentHerdSelection: any CurrentHerdSelectionReading
    ) async throws -> Bool {
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID else {
            return false
        }

        try await repository.deleteSession(id: id)

        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID else {
            return false
        }

        _ = load()
        return true
    }

    @discardableResult
    func load() -> Bool {
        do {
            sessions = try repository.fetchSessions()
            errorMessage = nil
            hasLoaded = true
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }
}
