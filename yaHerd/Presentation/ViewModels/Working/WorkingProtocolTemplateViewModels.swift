import Foundation

@MainActor
final class WorkingProtocolTemplatesViewModel: ObservableObject {
    @Published private(set) var templates: [WorkingProtocolTemplateSummary] = []
    @Published var errorMessage: String?

    private var repository: any WorkingRepository

    init(repository: any WorkingRepository) {
        self.repository = repository
    }

    func configure(repository: any WorkingRepository) {
        self.repository = repository
    }

    func load() {
        do {
            templates = try repository.fetchTemplates()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class WorkingProtocolTemplateDetailViewModel: ObservableObject {
    @Published private(set) var template: WorkingProtocolTemplateDetailSnapshot?
    @Published var errorMessage: String?

    private let templateID: UUID
    private var repository: any WorkingRepository

    init(templateID: UUID, repository: any WorkingRepository) {
        self.templateID = templateID
        self.repository = repository
    }

    func configure(repository: any WorkingRepository) {
        self.repository = repository
    }

    func load() {
        do {
            template = try repository.fetchTemplateDetail(id: templateID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
