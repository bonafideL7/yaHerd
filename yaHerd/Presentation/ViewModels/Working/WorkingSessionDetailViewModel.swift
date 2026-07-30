import Foundation

@MainActor
final class WorkingSessionDetailViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var repository: any WorkingSessionDetailRepository

    init(sessionID: UUID, repository: any WorkingSessionDetailRepository) {
        self.sessionID = sessionID
        self.repository = repository
    }

    func configure(repository: any WorkingSessionDetailRepository) {
        self.repository = repository
    }

    func load() {
        do {
            session = try PerformanceLog.measure("WorkingSessionDetailViewModel.load") {
                try repository.fetchSessionDetail(id: sessionID)
            }
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
        hasLoaded = true
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
