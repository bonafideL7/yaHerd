import Foundation

@MainActor
final class WorkingSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkingSessionSummary] = []
    @Published var errorMessage: String?

    private var repository: any WorkingSessionListReader
    private var hasLoaded = false
    private var lastLoadedRevision: UInt64 = 0

    init(repository: any WorkingSessionListReader) {
        self.repository = repository
    }

    func configure(repository: any WorkingSessionListReader) {
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
