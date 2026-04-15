import Foundation

@MainActor
final class NewWorkingSessionViewModel: ObservableObject {
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var templates: [WorkingProtocolTemplateSummary] = []
    @Published var errorMessage: String?

    private var animalRepository: any AnimalRepository
    private var workingRepository: any WorkingRepository

    init(animalRepository: any AnimalRepository, workingRepository: any WorkingRepository) {
        self.animalRepository = animalRepository
        self.workingRepository = workingRepository
    }

    func configure(animalRepository: any AnimalRepository, workingRepository: any WorkingRepository) {
        self.animalRepository = animalRepository
        self.workingRepository = workingRepository
    }

    func load() {
        do {
            pastures = try animalRepository.fetchPastureOptions()
            templates = try workingRepository.fetchTemplates()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func templateDetail(id: UUID) -> WorkingProtocolTemplateDetailSnapshot? {
        try? workingRepository.fetchTemplateDetail(id: id)
    }
}
