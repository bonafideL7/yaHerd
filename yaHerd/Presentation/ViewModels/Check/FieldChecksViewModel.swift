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

    func loadIfNeeded(using repository: any FieldCheckOverviewReading) {
        guard !hasLoaded else { return }
        load(using: repository)
    }

    func load(using repository: any FieldCheckOverviewReading) {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            sessions = try LoadFieldChecksUseCase(repository: repository).execute()
            openFindings = try repository.fetchOpenFindings(limit: 0)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
