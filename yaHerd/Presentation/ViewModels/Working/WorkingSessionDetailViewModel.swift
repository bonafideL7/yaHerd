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
        didLoad: @MainActor () -> Void = {}
    ) async {
        let startingRevision = mutationStream.workingSessionRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if load() {
                lastLoadedRevision = startingRevision
                didLoad()
            }
        }

        for await revision in mutationStream.revisions(
            for: .workingSessions,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled else { return }
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
            hasLoaded = true
            return false
        }
    }

    func reopenSession() {
        do {
            try repository.reopenSession(id: sessionID)
            load()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
