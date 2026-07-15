import Foundation

@MainActor
struct CreateWorkingProtocolTemplateUseCase {
    let repository: any WorkingProtocolTemplateCreating

    func execute(name: String, items: [WorkingProtocolItem]) throws -> UUID {
        try repository.createTemplate(name: name, items: items)
    }
}

@MainActor
struct UpdateWorkingProtocolTemplateUseCase {
    let repository: any WorkingProtocolTemplateUpdating

    func execute(templateID: UUID, name: String, items: [WorkingProtocolItem]) throws {
        try repository.updateTemplate(id: templateID, name: name, items: items)
    }
}

@MainActor
struct DeleteWorkingProtocolTemplatesUseCase {
    let repository: any WorkingProtocolTemplateDeleting

    func execute(_ templateIDs: [UUID]) throws {
        try repository.deleteTemplates(ids: templateIDs)
    }
}
