import Foundation

@MainActor
final class WorkingSessionDetailViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var repository: any WorkingSessionDetailReader

    init(sessionID: UUID, repository: any WorkingSessionDetailReader) {
        self.sessionID = sessionID
        self.repository = repository
    }

    func configure(repository: any WorkingSessionDetailReader) {
        self.repository = repository
    }

    func load() {
        do {
            session = try repository.fetchSessionDetail(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
