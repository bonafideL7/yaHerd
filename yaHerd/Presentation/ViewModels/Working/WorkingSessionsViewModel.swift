import Foundation

@MainActor
final class WorkingSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkingSessionSummary] = []
    @Published var errorMessage: String?

    private var readModel: (any WorkingSessionListReadModel)?
    private var repository: any WorkingSessionListReader
    private var loadTask: Task<Void, Never>?

    init(repository: any WorkingSessionListReader) {
        self.repository = repository
        if let provider = repository as? any WorkingSessionListReadModelProviding {
            readModel = provider.workingSessionListReadModel
        }
    }

    deinit {
        loadTask?.cancel()
    }

    func configure(repository: any WorkingSessionListReader) {
        self.repository = repository
        if let provider = repository as? any WorkingSessionListReadModelProviding {
            readModel = provider.workingSessionListReadModel
        }
    }

    func load() {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            await self?.performLoad()
        }
    }

    private func performLoad() async {
        guard let readModel else {
            errorMessage = "Working session history read model has not been configured."
            return
        }

        do {
            sessions = try await readModel.fetchWorkingSessions(limit: 250)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
