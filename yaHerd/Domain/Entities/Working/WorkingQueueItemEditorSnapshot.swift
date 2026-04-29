import Foundation

struct WorkingTreatmentRecordSnapshot: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let itemName: String
    let given: Bool
    let quantity: Double?
}

struct WorkingPregnancyCheckSnapshot: Hashable {
    let date: Date
    let result: PregnancyResult
    let estimatedDaysPregnant: Int?
    let dueDate: Date?
    let sire: AnimalParentOption?
}

struct WorkingQueueItemEditorSnapshot: Identifiable, Hashable {
    let id: UUID
    let sessionID: UUID
    let sessionDate: Date
    let sessionSourcePastureName: String?
    let protocolItems: [WorkingProtocolItem]
    let status: WorkingQueueStatus
    let completedAt: Date?
    let collectedFromPastureName: String?
    let destinationPastureID: UUID?
    let animalID: UUID?
    let animalDisplayTagNumber: String?
    let animalDisplayTagColorID: UUID?
    let animalDamDisplayTagNumber: String?
    let animalDamDisplayTagColorID: UUID?
    let animalSex: Sex
    let animalAgeInMonths: Int
    let treatmentRecords: [WorkingTreatmentRecordSnapshot]
    let pregnancyCheck: WorkingPregnancyCheckSnapshot?
    let castrationPerformedInSession: Bool
    let observationNotes: String
}
