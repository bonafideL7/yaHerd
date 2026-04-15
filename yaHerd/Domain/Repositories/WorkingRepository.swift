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

enum WorkingRepositoryError: LocalizedError {
    case sessionNotFound
    case queueItemNotFound
    case templateNotFound
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
        case .duplicateAnimalCollection:
            return "One or more animals are already in this working session."
        case .animalAlreadyInAnotherSession:
            return "One or more animals are already assigned to a different active working session."
        }
    }
}

protocol WorkingRepository {
    func fetchSessions() throws -> [WorkingSessionSummary]
    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot?
    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary]
    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot?
    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot?
    @discardableResult
    func createSession(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws
    func complete(queueItemID: UUID, inSessionID sessionID: UUID, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws
    func saveEdits(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID, input: WorkingSessionAnimalEditInput) throws
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws
    func deleteSession(id: UUID) throws
    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws
    func finishSession(id: UUID) throws
    @discardableResult
    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID
    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws
    func deleteTemplates(ids: [UUID]) throws
}
