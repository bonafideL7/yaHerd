import Foundation

@MainActor
final class WorkingFinishSessionViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var hasLoadedPastureOptions = false
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var workingRepository: any WorkingSessionDetailReader
    private var pastureRepository: any PastureReferenceDataReader

    init(sessionID: UUID, workingRepository: any WorkingSessionDetailReader, pastureRepository: any PastureReferenceDataReader) {
        self.sessionID = sessionID
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    var needsPastureOptionsRetry: Bool {
        session != nil && !hasLoadedPastureOptions
    }

    func configure(workingRepository: any WorkingSessionDetailReader, pastureRepository: any PastureReferenceDataReader) {
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    func load() {
        do {
            session = try workingRepository.fetchSessionDetail(id: sessionID)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return
        }

        loadPastureOptions()
    }

    func retryPastureOptions() {
        guard session != nil else {
            load()
            return
        }

        loadPastureOptions()
    }

    private func loadPastureOptions() {
        do {
            pastures = try pastureRepository.fetchPastureOptions()
            hasLoadedPastureOptions = true
            errorMessage = nil
        } catch {
            hasLoadedPastureOptions = false
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}
