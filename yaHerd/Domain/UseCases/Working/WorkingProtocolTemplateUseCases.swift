import Foundation

struct CreateWorkingProtocolTemplateUseCase {
    let repository: any WorkingRepository

    func execute(name: String, items: [WorkingProtocolItem]) throws -> UUID {
        try repository.createTemplate(name: name, items: items)
    }
}

struct UpdateWorkingProtocolTemplateUseCase {
    let repository: any WorkingRepository

    func execute(templateID: UUID, name: String, items: [WorkingProtocolItem]) throws {
        try repository.updateTemplate(id: templateID, name: name, items: items)
    }
}

struct DeleteWorkingProtocolTemplatesUseCase {
    let repository: any WorkingRepository

    func execute(_ templateIDs: [UUID]) throws {
        try repository.deleteTemplates(ids: templateIDs)
    }
}
