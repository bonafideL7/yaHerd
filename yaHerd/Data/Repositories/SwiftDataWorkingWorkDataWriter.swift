import Foundation
import SwiftData

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
            context.insert(record)
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
        context.insert(check)
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
        context.insert(record)
    }

    private func fetchAnimal(id: UUID?) throws -> Animal? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Animal>(predicate: #Predicate<Animal> { animal in animal.publicID == id })
        return try context.fetch(descriptor).first
    }

    private func deleteTreatmentRecords(session: WorkingSession, animal: Animal) throws {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        for record in try context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) where record.session?.persistentModelID == sid && record.animal?.persistentModelID == aid {
            context.delete(record)
        }
    }

    private func deletePregnancyChecks(session: WorkingSession, animal: Animal) throws {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        for check in try context.fetch(FetchDescriptor<PregnancyCheck>()) where check.workingSession?.persistentModelID == sid && check.animal?.persistentModelID == aid {
            context.delete(check)
        }
    }

    private func deleteHealthRecords(session: WorkingSession, animal: Animal, treatment: String? = nil) throws {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        for record in try context.fetch(FetchDescriptor<HealthRecord>()) where record.workingSession?.persistentModelID == sid && record.animal?.persistentModelID == aid {
            if let treatment, record.treatment != treatment { continue }
            context.delete(record)
        }
    }
}
