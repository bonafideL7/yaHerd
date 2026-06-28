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
