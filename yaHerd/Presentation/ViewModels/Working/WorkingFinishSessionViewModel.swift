import Foundation

@MainActor
final class WorkingFinishSessionViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var pastures: [PastureOption] = []
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var workingRepository: any WorkingSessionDetailReader
    private var pastureRepository: any PastureReferenceDataReader

    init(sessionID: UUID, workingRepository: any WorkingSessionDetailReader, pastureRepository: any PastureReferenceDataReader) {
        self.sessionID = sessionID
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    func configure(workingRepository: any WorkingSessionDetailReader, pastureRepository: any PastureReferenceDataReader) {
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    func load() {
        do {
            session = try workingRepository.fetchSessionDetail(id: sessionID)
            pastures = try LoadPastureOptionsUseCase(repository: pastureRepository).execute()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
