import Foundation

struct WorkingQueueItemWorkDataInput: Hashable {
    var treatmentEntries: [WorkingTreatmentEntryInput]
    var pregnancyCheck: WorkingPregnancyCheckInput?
    var castrationPerformed: Bool
    var observationNotes: String

    init(
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        castrationPerformed: Bool,
        observationNotes: String
    ) {
        self.treatmentEntries = treatmentEntries
        self.pregnancyCheck = pregnancyCheck
        self.castrationPerformed = castrationPerformed
        self.observationNotes = observationNotes
    }
}

extension WorkingSessionAnimalEditInput {
    var workData: WorkingQueueItemWorkDataInput {
        WorkingQueueItemWorkDataInput(
            treatmentEntries: treatmentEntries,
            pregnancyCheck: pregnancyCheck,
            castrationPerformed: castrationPerformed,
            observationNotes: observationNotes
        )
    }
}
