import Foundation

@MainActor
final class NewWorkingSessionViewModel: ObservableObject {
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var templates: [WorkingProtocolTemplateSummary] = []
    @Published var errorMessage: String?

    private var pastureRepository: any PastureReferenceDataReader
    private var workingRepository: any NewWorkingSessionRepository

    init(pastureRepository: any PastureReferenceDataReader, workingRepository: any NewWorkingSessionRepository) {
        self.pastureRepository = pastureRepository
        self.workingRepository = workingRepository
    }

    func configure(pastureRepository: any PastureReferenceDataReader, workingRepository: any NewWorkingSessionRepository) {
        self.pastureRepository = pastureRepository
        self.workingRepository = workingRepository
    }

    func load() {
        do {
            pastures = try LoadPastureOptionsUseCase(repository: pastureRepository).execute()
            templates = try workingRepository.fetchTemplates()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func templateDetail(id: UUID) -> WorkingProtocolTemplateDetailSnapshot? {
        do {
            return try workingRepository.fetchTemplateDetail(id: id)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return nil
        }
    }
}
