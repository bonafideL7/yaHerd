import Foundation

@MainActor
final class NewWorkingSessionViewModel: ObservableObject {
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var templates: [WorkingProtocolTemplateSummary] = []
    @Published var errorMessage: String?

    private var pastureRepository: any PastureReferenceDataReader
    private var workingRepository: any WorkingRepository

    init(pastureRepository: any PastureReferenceDataReader, workingRepository: any WorkingRepository) {
        self.pastureRepository = pastureRepository
        self.workingRepository = workingRepository
    }

    func configure(pastureRepository: any PastureReferenceDataReader, workingRepository: any WorkingRepository) {
        self.pastureRepository = pastureRepository
        self.workingRepository = workingRepository
    }

    func load() {
        do {
            pastures = try LoadPastureOptionsUseCase(repository: pastureRepository).execute()
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
