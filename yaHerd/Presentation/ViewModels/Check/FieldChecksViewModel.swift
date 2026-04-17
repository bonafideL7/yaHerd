import Foundation
import Observation

@MainActor
@Observable
final class FieldChecksViewModel {
    private(set) var sessions: [FieldCheckSessionSummary] = []
    private(set) var openFindings: [FieldCheckFindingSnapshot] = []
    var errorMessage: String?
    var hasLoaded = false

    var activeSessions: [FieldCheckSessionSummary] {
        sessions.filter { !$0.isCompleted }
    }

    var recentSessions: [FieldCheckSessionSummary] {
        Array(sessions.prefix(12))
    }

    func load(using repository: any FieldCheckRepository) {
        defer { hasLoaded = true }

        do {
            sessions = try LoadFieldChecksUseCase(repository: repository).execute()
            openFindings = try repository.fetchOpenFindings(limit: 10)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
