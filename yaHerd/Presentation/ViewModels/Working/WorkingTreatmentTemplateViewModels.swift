import Foundation

@MainActor
final class WorkingTreatmentTemplatesViewModel: ObservableObject {
    @Published private(set) var templates: [WorkingTreatmentTemplateSummary] = []
    @Published var errorMessage: String?
    @Published private(set) var hasLoaded = false

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
            hasLoaded = true
            errorMessage = nil
        } catch {
            // Retain the last complete snapshot for recovery, but never expose
            // it to a screen while the current read remains unavailable.
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func visibleTemplates(
        identity: WorkingQueueEditorHerdIdentity?,
        selection: AppCurrentHerdSelection
    ) -> [WorkingTreatmentTemplateSummary] {
        guard identity?.isCurrent(in: selection) == true,
              hasLoaded,
              errorMessage == nil else { return [] }
        return templates
    }

    func clear() {
        templates = []
        hasLoaded = false
        errorMessage = nil
    }
}

@MainActor
final class WorkingTreatmentTemplateDetailViewModel: ObservableObject {
    @Published private(set) var template: WorkingTreatmentTemplateDetailSnapshot?
    @Published var errorMessage: String?
    @Published private(set) var hasLoaded = false

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
            hasLoaded = true
            errorMessage = nil
        } catch {
            // Failed imports are not evidence that a template was deleted.
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func visibleTemplate(
        identity: WorkingQueueEditorHerdIdentity?,
        selection: AppCurrentHerdSelection
    ) -> WorkingTreatmentTemplateDetailSnapshot? {
        guard identity?.isCurrent(in: selection) == true,
              hasLoaded,
              errorMessage == nil else { return nil }
        return template
    }

    func clear() {
        template = nil
        hasLoaded = false
        errorMessage = nil
    }
}
