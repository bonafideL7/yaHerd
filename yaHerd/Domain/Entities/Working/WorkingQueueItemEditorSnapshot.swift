import Foundation

struct WorkingTreatmentRecordSnapshot: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let treatmentItemID: UUID
    let itemName: String
    let given: Bool
    let dose: WorkingTreatmentDose

    init(
        id: UUID,
        date: Date,
        treatmentItemID: UUID,
        itemName: String,
        given: Bool,
        dose: WorkingTreatmentDose
    ) {
        self.id = id
        self.date = date
        self.treatmentItemID = treatmentItemID
        self.itemName = itemName
        self.given = given
        self.dose = dose
    }
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
    let sessionStatus: WorkingSessionStatus
    let sessionSourcePastureName: String?
    let plannedTreatments: [WorkingTreatmentPlanItem]
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
