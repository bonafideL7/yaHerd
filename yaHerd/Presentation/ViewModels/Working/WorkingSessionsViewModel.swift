import Foundation

@MainActor
final class WorkingSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkingSessionSummary] = []
    @Published var errorMessage: String?

    private var repository: any WorkingSessionsRepository
    private var hasLoaded = false
    private var lastLoadedRevision: UInt64 = 0
    private var herdSelection: AppCurrentHerdSelection?
    private var selectedHerdID: UUID?
    private var selectedSelectionRevision: UInt64?
    private var hasConfiguredSelection = false

    var isCurrentHerdSelection: Bool {
        guard hasConfiguredSelection else { return true }
        guard let herdSelection else { return false }
        return selectedHerdID == herdSelection.currentHerdID
            && selectedSelectionRevision == herdSelection.selectionRevision
    }

    init(repository: any WorkingSessionsRepository) {
        self.repository = repository
    }

    func configure(repository: any WorkingSessionsRepository) {
        self.repository = repository
    }

    /// A retained list cannot reuse another Herd's sessions or mutation revision.
    func configure(selection: AppCurrentHerdSelection) {
        let changed = !hasConfiguredSelection
            || herdSelection !== selection
            || selectedHerdID != selection.currentHerdID
            || selectedSelectionRevision != selection.selectionRevision
        herdSelection = selection
        selectedHerdID = selection.currentHerdID
        selectedSelectionRevision = selection.selectionRevision
        hasConfiguredSelection = true

        if changed {
            sessions = []
            errorMessage = nil
            hasLoaded = false
            lastLoadedRevision = 0
        }
    }

    func observe(mutationStream: any ApplicationMutationStreaming) async {
        let originatingHerdID = selectedHerdID
        let originatingRevision = selectedSelectionRevision
        guard !Task.isCancelled,
              isCurrentObserver(herdID: originatingHerdID, revision: originatingRevision) else {
            return
        }

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
            guard !Task.isCancelled,
                  isCurrentObserver(herdID: originatingHerdID, revision: originatingRevision) else {
                return
            }
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
        originatingSelectionRevision: UInt64,
        currentHerdSelection: AppCurrentHerdSelection
    ) async throws -> Bool {
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              currentHerdSelection.selectionRevision == originatingSelectionRevision else {
            return false
        }

        try await repository.deleteSession(id: id)

        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              currentHerdSelection.selectionRevision == originatingSelectionRevision else {
            return false
        }

        _ = load()
        return true
    }

    @discardableResult
    func load() -> Bool {
        guard !Task.isCancelled,
              !hasConfiguredSelection || (selectedHerdID != nil && isCurrentHerdSelection) else {
            return false
        }
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

    private func isCurrentObserver(herdID: UUID?, revision: UInt64?) -> Bool {
        !hasConfiguredSelection || (
            herdID != nil
            && selectedHerdID == herdID
            && selectedSelectionRevision == revision
            && isCurrentHerdSelection
        )
    }
}
