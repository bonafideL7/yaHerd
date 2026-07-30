import Foundation

@MainActor
final class WorkingSessionDetailViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var readModel: (any WorkingSessionDetailReadModel)?
    private var repository: any WorkingSessionDetailRepository
    private var loadTask: Task<Void, Never>?

    init(sessionID: UUID, repository: any WorkingSessionDetailRepository) {
        self.sessionID = sessionID
        self.repository = repository
        if let provider = repository as? any WorkingSessionDetailReadModelProviding {
            self.readModel = provider.workingSessionDetailReadModel
        }
    }

    deinit {
        loadTask?.cancel()
    }

    func configure(repository: any WorkingSessionDetailRepository) {
        self.repository = repository
        if let provider = repository as? any WorkingSessionDetailReadModelProviding {
            readModel = provider.workingSessionDetailReadModel
        }
    }

    func configure(
        readModel: any WorkingSessionDetailReadModel,
        repository: any WorkingSessionDetailRepository
    ) {
        self.readModel = readModel
        self.repository = repository
    }

    func load() {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            await self?.performLoad()
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

    private func performLoad() async {
        guard let readModel else {
            errorMessage = "Working session detail read model has not been configured."
            hasLoaded = true
            return
        }

        do {
            session = try await readModel.fetchSessionDetail(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
        hasLoaded = true
    }
}
