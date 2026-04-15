import Foundation

@MainActor
final class WorkingQueueItemEditorViewModel: ObservableObject {
    @Published private(set) var snapshot: WorkingQueueItemEditorSnapshot?
    @Published private(set) var pastures: [PastureOption] = []
    @Published var errorMessage: String?

    private let sessionID: UUID
    private let queueItemID: UUID
    private var workingRepository: any WorkingRepository
    private var animalRepository: any AnimalRepository

    init(sessionID: UUID, queueItemID: UUID, workingRepository: any WorkingRepository, animalRepository: any AnimalRepository) {
        self.sessionID = sessionID
        self.queueItemID = queueItemID
        self.workingRepository = workingRepository
        self.animalRepository = animalRepository
    }

    func configure(workingRepository: any WorkingRepository, animalRepository: any AnimalRepository) {
        self.workingRepository = workingRepository
        self.animalRepository = animalRepository
    }

    func load() {
        do {
            snapshot = try workingRepository.fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID)
            pastures = try animalRepository.fetchPastureOptions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
