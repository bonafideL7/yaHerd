import Foundation

struct WorkingTreatmentEntryInput: Hashable {
    var date: Date
    var itemName: String
    var given: Bool
    var quantity: Double?
}

struct WorkingPregnancyCheckInput: Hashable {
    var date: Date
    var result: PregnancyResult
    var estimatedDaysPregnant: Int?
    var dueDate: Date?
    var sireAnimalID: UUID?
}

struct WorkingSessionAnimalEditInput: Hashable {
    var status: WorkingQueueStatus
    var completedAt: Date?
    var destinationPastureID: UUID?
    var treatmentEntries: [WorkingTreatmentEntryInput]
    var pregnancyCheck: WorkingPregnancyCheckInput?
    var castrationPerformed: Bool
    var observationNotes: String
}

enum WorkingRepositoryError: LocalizedError, Equatable {
    case sessionNotFound
    case queueItemNotFound
    case templateNotFound
    case duplicateTemplateName(String)
    case duplicateAnimalCollection
    case animalAlreadyInAnotherSession

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Working session not found."
        case .queueItemNotFound:
            return "Working queue item not found."
        case .templateNotFound:
            return "Working protocol template not found."
        case .duplicateTemplateName(let name):
            return "A working protocol template named \(name) already exists. Names must be unique."
        case .duplicateAnimalCollection:
            return "One or more animals are already in this working session."
        case .animalAlreadyInAnotherSession:
            return "One or more animals are already assigned to a different active working session."
        }
    }
}

protocol WorkingSessionListReader {
    func fetchSessions() throws -> [WorkingSessionSummary]
}

protocol WorkingSessionDetailReader {
    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot?
}

protocol WorkingProtocolTemplateListReader {
    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary]
}

protocol WorkingProtocolTemplateDetailReader {
    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot?
}

protocol WorkingQueueItemEditorReader {
    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot?
}

protocol WorkingSessionCreating {
    @discardableResult
    func createSession(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID
}

protocol WorkingAnimalCollecting {
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws
}

protocol WorkingQueueItemCompleting {
    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) throws
}

protocol WorkingQueueItemEditSaving {
    func saveEdits(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID, input: WorkingSessionAnimalEditInput) throws
}

protocol WorkingQueueItemDataDeleting {
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws
}

protocol WorkingSessionDeleting {
    func deleteSession(id: UUID) throws
}

protocol WorkingDestinationSaving {
    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws
}

protocol WorkingSessionFinishing {
    func finishSession(id: UUID) throws
}

protocol WorkingProtocolTemplateCreating {
    @discardableResult
    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID
}

protocol WorkingProtocolTemplateUpdating {
    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws
}

protocol WorkingProtocolTemplateDeleting {
    func deleteTemplates(ids: [UUID]) throws
}


protocol WorkingSessionsRepository: WorkingSessionListReader, WorkingSessionDeleting {}

protocol WorkingSessionDetailRepository: WorkingSessionDetailReader, WorkingSessionDeleting {}

protocol NewWorkingSessionRepository:
    WorkingProtocolTemplateListReader,
    WorkingProtocolTemplateDetailReader,
    WorkingSessionCreating
{}

protocol WorkingCollectAnimalsRepository:
    WorkingSessionDetailReader,
    WorkingAnimalCollecting
{}

protocol WorkingQueueRepository: WorkingSessionDetailReader {}

protocol WorkingQueueItemEditingRepository:
    WorkingQueueItemEditorReader,
    WorkingQueueItemEditSaving,
    WorkingQueueItemDataDeleting
{}

protocol WorkingChuteRepository:
    WorkingQueueItemEditorReader,
    WorkingQueueItemCompleting
{}

protocol WorkingFinishSessionRepository:
    WorkingSessionDetailReader,
    WorkingDestinationSaving,
    WorkingSessionFinishing
{}

protocol WorkingProtocolTemplatesRepository:
    WorkingProtocolTemplateListReader,
    WorkingProtocolTemplateDeleting
{}

protocol WorkingProtocolTemplateEditorRepository:
    WorkingProtocolTemplateDetailReader,
    WorkingProtocolTemplateUpdating
{}

protocol WorkingRepository:
    WorkingSessionsRepository,
    WorkingSessionDetailRepository,
    NewWorkingSessionRepository,
    WorkingCollectAnimalsRepository,
    WorkingQueueRepository,
    WorkingQueueItemEditingRepository,
    WorkingChuteRepository,
    WorkingFinishSessionRepository,
    WorkingProtocolTemplatesRepository,
    WorkingProtocolTemplateCreating,
    WorkingProtocolTemplateEditorRepository
{}
