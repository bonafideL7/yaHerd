import Foundation

@MainActor
final class WorkingFinishSessionViewModel: ObservableObject {
    @Published private(set) var session: WorkingSessionDetailSnapshot?
    @Published private(set) var pastures: [PastureOption] = []
    @Published var errorMessage: String?

    private let sessionID: UUID
    private var workingRepository: any WorkingRepository
    private var animalRepository: any AnimalRepository

    init(sessionID: UUID, workingRepository: any WorkingRepository, animalRepository: any AnimalRepository) {
        self.sessionID = sessionID
        self.workingRepository = workingRepository
        self.animalRepository = animalRepository
    }

    func configure(workingRepository: any WorkingRepository, animalRepository: any AnimalRepository) {
        self.workingRepository = workingRepository
        self.animalRepository = animalRepository
    }

    func load() {
        do {
            session = try workingRepository.fetchSessionDetail(id: sessionID)
            pastures = try animalRepository.fetchPastureOptions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
