import Foundation

@MainActor
final class WorkingSessionDetailViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var repository: any WorkingSessionDetailRepository
    private var lastLoadedRevision: UInt64 = 0

    init(sessionID: UUID, repository: any WorkingSessionDetailRepository) {
        self.sessionID = sessionID
        self.repository = repository
    }

    func configure(repository: any WorkingSessionDetailRepository) {
        self.repository = repository
    }

    func observe(
        mutationStream: any ApplicationMutationStreaming,
        mayContinue: @escaping @MainActor () -> Bool = { true },
        didLoad: @MainActor () -> Void = {}
    ) async {
        guard !Task.isCancelled, mayContinue() else { return }

        let startingRevision = mutationStream.workingSessionRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            guard mayContinue() else { return }
            if load() {
                lastLoadedRevision = startingRevision
                didLoad()
            }
        }

        for await revision in mutationStream.revisions(
            for: .workingSessions,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled, mayContinue() else { return }
            if load() {
                lastLoadedRevision = revision
                didLoad()
            }
        }
    }

    @discardableResult
    func load() -> Bool {
        do {
            session = try PerformanceLog.measure("WorkingSession.open") {
                try repository.fetchSessionDetail(id: sessionID)
            }
            errorMessage = nil
            hasLoaded = true
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            // A failed read cannot establish that an absent session was deleted.
            // Keep an earlier complete snapshot when one is already available.
            hasLoaded = session != nil
            return false
        }
    }

    /// Ignore a queued command or completion after the originating Herd
    /// changes. A write already started remains scoped to its original Herd.
    @discardableResult
    func reopenSession(
        originatingHerdID: UUID,
        currentHerdSelection: any CurrentHerdSelectionReading,
        selectionIsUnchanged: @MainActor () -> Bool
    ) async -> Bool {
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              selectionIsUnchanged() else {
            return false
        }

        do {
            try await repository.reopenSession(id: sessionID)
            guard !Task.isCancelled,
                  currentHerdSelection.currentHerdID == originatingHerdID,
                  selectionIsUnchanged() else {
                return false
            }
            return load()
        } catch {
            guard !Task.isCancelled,
                  currentHerdSelection.currentHerdID == originatingHerdID,
                  selectionIsUnchanged() else {
                return false
            }
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }
}
