import Foundation

@MainActor
final class WorkingQueueItemEditorViewModel: ObservableObject {
    @Published private(set) var snapshot: WorkingQueueItemEditorSnapshot?
    @Published private(set) var pastures: [PastureOption] = []
    @Published var errorMessage: String?

    private let sessionID: UUID
    private let queueItemID: UUID
    private var workingRepository: any WorkingRepository
    private var pastureRepository: any PastureReferenceDataReader

    init(sessionID: UUID, queueItemID: UUID, workingRepository: any WorkingRepository, pastureRepository: any PastureReferenceDataReader) {
        self.sessionID = sessionID
        self.queueItemID = queueItemID
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    func configure(workingRepository: any WorkingRepository, pastureRepository: any PastureReferenceDataReader) {
        self.workingRepository = workingRepository
        self.pastureRepository = pastureRepository
    }

    func load() {
        do {
            snapshot = try workingRepository.fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID)
            pastures = try LoadPastureOptionsUseCase(repository: pastureRepository).execute()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
