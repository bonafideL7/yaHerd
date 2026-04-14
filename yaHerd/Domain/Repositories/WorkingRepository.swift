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

protocol WorkingRepository {
    @discardableResult
    func createSession(date: Date, sourcePasture: Pasture?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> WorkingSession
    func collectAnimals(session: WorkingSession, animals: [Animal]) throws
    func complete(queueItem: WorkingQueueItem, in session: WorkingSession, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws
    func saveEdits(for queueItem: WorkingQueueItem, in session: WorkingSession, input: WorkingSessionAnimalEditInput) throws
    func deleteWorkData(for queueItem: WorkingQueueItem, in session: WorkingSession) throws
    func deleteSession(_ session: WorkingSession) throws
    func finishSession(_ session: WorkingSession) throws
    @discardableResult
    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> WorkingProtocolTemplate
    func updateTemplate(_ template: WorkingProtocolTemplate, name: String, items: [WorkingProtocolItem]) throws
    func deleteTemplates(_ templates: [WorkingProtocolTemplate]) throws
}
