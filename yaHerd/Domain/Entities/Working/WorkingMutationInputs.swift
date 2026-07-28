import Foundation

struct WorkingSessionStartInput: Hashable {
    var date: Date
    var sourcePastureID: UUID
    var treatmentTemplateName: String?
    var plannedTreatments: [WorkingTreatmentPlanItem]

    /// `nil` includes every eligible animal in the source pasture.
    /// A non-nil value includes only the supplied animal IDs.
    var animalIDs: [UUID]?
}

struct WorkingTagReplacementInput: Hashable {
    var number: String
    var colorID: UUID?
}

struct WorkingTreatmentEntryInput: Hashable {
    var date: Date
    var treatmentItemID: UUID
    var itemName: String
    var given: Bool
    var dose: WorkingTreatmentDose

    init(
        date: Date,
        treatmentItemID: UUID,
        itemName: String,
        given: Bool,
        dose: WorkingTreatmentDose
    ) {
        self.date = date
        self.treatmentItemID = treatmentItemID
        self.itemName = itemName
        self.given = given
        self.dose = dose
    }

    /// Transitional V1 source compatibility. New code passes stable item identity and dose.
    init(
        date: Date,
        itemName: String,
        given: Bool,
        quantity: Double?
    ) {
        self.init(
            date: date,
            treatmentItemID: UUID(),
            itemName: itemName,
            given: given,
            dose: WorkingTreatmentDose(amount: quantity)
        )
    }
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
