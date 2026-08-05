import Foundation
import Observation

@MainActor
@Observable
final class FieldChecksViewModel {
    private(set) var sessions: [FieldCheckSessionSummary] = []
    private(set) var openFindings: [FieldCheckFindingSnapshot] = []
    var errorMessage: String?
    var hasLoaded = false
    private var isLoading = false
    private var lastLoadedRevision: UInt64 = 0

    var activeSessions: [FieldCheckSessionSummary] {
        sessions.filter { !$0.isCompleted }
    }

    var archivedPastureSessions: [FieldCheckSessionSummary] {
        sessions
            .filter(\.isPastureArchived)
            .sorted { $0.startedAt > $1.startedAt }
    }

    var recentSessions: [FieldCheckSessionSummary] {
        Array(
            sessions
                .filter(\.isCompleted)
                .prefix(12)
        )
    }

    func observe(
        using repository: any FieldCheckOverviewReading,
        mutationStream: any ApplicationMutationStreaming
    ) async {
        let startingRevision = mutationStream.fieldCheckRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if load(using: repository) {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .fieldChecks,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled else { return }
            if load(using: repository) {
                lastLoadedRevision = revision
            }
        }
    }

    func loadIfNeeded(using repository: any FieldCheckOverviewReading) {
        guard !hasLoaded else { return }
        _ = load(using: repository)
    }

    @discardableResult
    func load(using repository: any FieldCheckOverviewReading) -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            sessions = try repository.fetchSessions()
            openFindings = try repository.fetchOpenFindings(limit: 0)
            errorMessage = nil
            hasLoaded = true
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }
}
