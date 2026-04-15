import Foundation

@MainActor
final class WorkingSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkingSessionSummary] = []
    @Published var errorMessage: String?

    private var repository: any WorkingRepository

    init(repository: any WorkingRepository) {
        self.repository = repository
    }

    func configure(repository: any WorkingRepository) {
        self.repository = repository
    }

    func load() {
        do {
            sessions = try repository.fetchSessions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
