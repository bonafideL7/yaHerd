import Foundation

@MainActor
final class WorkingTreatmentTemplatesViewModel: ObservableObject {
    @Published private(set) var templates: [WorkingTreatmentTemplateSummary] = []
    @Published var errorMessage: String?

    private var repository: any WorkingTreatmentTemplateListReader

    init(repository: any WorkingTreatmentTemplateListReader) {
        self.repository = repository
    }

    func configure(repository: any WorkingTreatmentTemplateListReader) {
        self.repository = repository
    }

    func load() {
        do {
            templates = try repository.fetchTemplates()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func visibleTemplates(
        identity: WorkingQueueEditorHerdIdentity?,
        selection: AppCurrentHerdSelection
    ) -> [WorkingTreatmentTemplateSummary] {
        guard identity?.isCurrent(in: selection) == true else { return [] }
        return templates
    }

    func clear() {
        templates = []
        errorMessage = nil
    }
}

@MainActor
final class WorkingTreatmentTemplateDetailViewModel: ObservableObject {
    @Published private(set) var template: WorkingTreatmentTemplateDetailSnapshot?
    @Published var errorMessage: String?

    private let templateID: UUID
    private var repository: any WorkingTreatmentTemplateDetailReader

    init(templateID: UUID, repository: any WorkingTreatmentTemplateDetailReader) {
        self.templateID = templateID
        self.repository = repository
    }

    func configure(repository: any WorkingTreatmentTemplateDetailReader) {
        self.repository = repository
    }

    func load() {
        do {
            template = try repository.fetchTemplateDetail(id: templateID)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func visibleTemplate(
        identity: WorkingQueueEditorHerdIdentity?,
        selection: AppCurrentHerdSelection
    ) -> WorkingTreatmentTemplateDetailSnapshot? {
        guard identity?.isCurrent(in: selection) == true else { return nil }
        return template
    }

    func clear() {
        template = nil
        errorMessage = nil
    }
}
