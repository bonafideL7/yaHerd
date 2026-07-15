import Foundation
import SwiftData

@MainActor
struct SwiftDataWorkingWorkDataWriter {
    let context: ModelContext

    func replaceWorkData(session: WorkingSession, animal: Animal, input: WorkingQueueItemWorkDataInput, recordDate: Date) throws {
        try replaceTreatmentRecords(session: session, animal: animal, entries: input.treatmentEntries)
        try replacePregnancyCheck(session: session, animal: animal, input: input.pregnancyCheck)
        try replaceGeneratedHealthRecord(
            session: session,
            animal: animal,
            kind: .castration,
            shouldInsert: input.castrationPerformed,
            notes: nil,
            date: recordDate
        )

        let observationNotes = WorkingWorkDataRules.normalizedObservationNotes(input.observationNotes)
        try replaceGeneratedHealthRecord(
            session: session,
            animal: animal,
            kind: .observation,
            shouldInsert: !observationNotes.isEmpty,
            notes: observationNotes,
            date: recordDate
        )
    }

    func deleteAllWorkData(session: WorkingSession, animal: Animal) throws {
        try deleteTreatmentRecords(session: session, animal: animal)
        try deletePregnancyChecks(session: session, animal: animal)
        try deleteHealthRecords(session: session, animal: animal)
    }

    private func replaceTreatmentRecords(session: WorkingSession, animal: Animal, entries: [WorkingTreatmentEntryInput]) throws {
        try deleteTreatmentRecords(session: session, animal: animal)
        for entry in entries {
            let record = WorkingTreatmentRecord(
                date: entry.date,
                itemName: entry.itemName,
                given: entry.given,
                quantity: entry.quantity,
                animal: animal,
                session: session
            )
            try context.insertIntoDefaultHerd(record)
        }
    }

    private func replacePregnancyCheck(session: WorkingSession, animal: Animal, input: WorkingPregnancyCheckInput?) throws {
        try deletePregnancyChecks(session: session, animal: animal)
        guard WorkingWorkDataRules.shouldRecordPregnancyCheck(input), let input else { return }

        let check = PregnancyCheck(
            date: input.date,
            result: input.result,
            technician: nil,
            estimatedDaysPregnant: input.estimatedDaysPregnant,
            dueDate: input.dueDate,
            sireAnimal: try fetchAnimal(id: input.sireAnimalID),
            workingSession: session,
            animal: animal
        )
        try context.insertIntoDefaultHerd(check)
    }

    private func replaceGeneratedHealthRecord(
        session: WorkingSession,
        animal: Animal,
        kind: WorkingGeneratedHealthRecord,
        shouldInsert: Bool,
        notes: String?,
        date: Date
    ) throws {
        try deleteHealthRecords(session: session, animal: animal, treatment: kind.treatmentName)
        guard shouldInsert else { return }

        let record = HealthRecord(
            date: date,
            treatment: kind.treatmentName,
            notes: notes,
            workingSession: session,
            animal: animal
        )
        try context.insertIntoDefaultHerd(record)
    }

    private func fetchAnimal(id: UUID?) throws -> Animal? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Animal>(predicate: #Predicate<Animal> { animal in animal.publicID == id })
        return try context.fetch(descriptor).first
    }

    private func deleteTreatmentRecords(session: WorkingSession, animal: Animal) throws {
        let sessionID = session.publicID
        let animalID = animal.publicID
        let descriptor = FetchDescriptor<WorkingTreatmentRecord>(
            predicate: #Predicate<WorkingTreatmentRecord> { record in
                record.session?.publicID == sessionID && record.animal?.publicID == animalID
            }
        )
        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
    }

    private func deletePregnancyChecks(session: WorkingSession, animal: Animal) throws {
        let sessionID = session.publicID
        let animalID = animal.publicID
        let descriptor = FetchDescriptor<PregnancyCheck>(
            predicate: #Predicate<PregnancyCheck> { check in
                check.workingSession?.publicID == sessionID && check.animal?.publicID == animalID
            }
        )
        for check in try context.fetch(descriptor) {
            context.delete(check)
        }
    }

    private func deleteHealthRecords(session: WorkingSession, animal: Animal, treatment: String? = nil) throws {
        let sessionID = session.publicID
        let animalID = animal.publicID
        let descriptor: FetchDescriptor<HealthRecord>
        if let treatment {
            descriptor = FetchDescriptor<HealthRecord>(
                predicate: #Predicate<HealthRecord> { record in
                    record.workingSession?.publicID == sessionID
                        && record.animal?.publicID == animalID
                        && record.treatment == treatment
                }
            )
        } else {
            descriptor = FetchDescriptor<HealthRecord>(
                predicate: #Predicate<HealthRecord> { record in
                    record.workingSession?.publicID == sessionID && record.animal?.publicID == animalID
                }
            )
        }

        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
    }
}
