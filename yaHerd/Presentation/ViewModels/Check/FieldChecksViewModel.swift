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
    private var loadTask: Task<Void, Never>?

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
        loadTask?.cancel()

        if let provider = repository as? any FieldCheckOverviewReadModelProviding {
            let readModel = provider.fieldCheckOverviewReadModel
            loadTask = Task { @MainActor [weak self] in
                await self?.load(using: readModel)
            }
            return
        }

        loadSynchronously(using: repository)
    }

    private func load(using readModel: any HomeFieldCheckReadModel) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            async let loadedSessions = readModel.fetchRecentSessions(limit: 250)
            async let loadedFindings = readModel.fetchOpenFindings(limit: 100)
            sessions = try await loadedSessions
            openFindings = try await loadedFindings
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private func loadSynchronously(using repository: any FieldCheckOverviewReading) {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            sessions = try repository.fetchSessions()
            openFindings = try repository.fetchOpenFindings(limit: 100)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
