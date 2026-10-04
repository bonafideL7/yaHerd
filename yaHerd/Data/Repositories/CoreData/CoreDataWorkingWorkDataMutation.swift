@preconcurrency import CoreData
import Foundation

enum CoreDataWorkingWorkDataMutation {
    static func validateReferences(
        input: WorkingQueueItemWorkDataInput,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDAnimal? {
        try WorkingTreatmentPlanRules.validate(input.treatmentEntries)

        guard WorkingWorkDataRules.shouldRecordPregnancyCheck(input.pregnancyCheck),
              let sireID = input.pregnancyCheck?.sireAnimalID
        else {
            return nil
        }

        guard let sire = try lookup.herdOwned(
            CDAnimal.self,
            id: sireID,
            herdID: herdID,
            in: context
        ) else {
            throw WorkingRepositoryError.animalNotFound
        }
        return sire
    }

    static func replace(
        session: CDWorkingSession,
        animal: CDAnimal,
        input: WorkingQueueItemWorkDataInput,
        recordDate: Date,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws {
        let plannedTreatments = try WorkingMapper.plannedTreatments(session)
        try WorkingTreatmentPlanRules.validate(
            input.treatmentEntries,
            against: plannedTreatments
        )
        let sire = try validateReferences(
            input: input,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )

        deleteTreatmentRecords(session: session, animal: animal, in: context)
        for entry in input.treatmentEntries {
            let record = CDWorkingTreatmentRecord(context: context)
            record.id = try CoreDataAnimalMutation.uniqueID(
                for: CDWorkingTreatmentRecord.self,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            record.date = entry.date
            record.treatmentItemID = entry.treatmentItemID
            record.itemNameSnapshot = entry.itemName
            record.given = entry.given
            if let amount = entry.dose.amount {
                record.doseAmount = NSNumber(value: amount)
            } else {
                record.doseAmount = nil
            }
            record.doseUnitRawValue = entry.dose.unit?.rawValue
            record.administrationRouteRawValue = entry.dose.route?.rawValue
            record.animalIDSnapshot = animal.id
            record.herd = herd
            record.animal = animal
            record.session = session
        }

        deletePregnancyChecks(session: session, animal: animal, in: context)
        if WorkingWorkDataRules.shouldRecordPregnancyCheck(input.pregnancyCheck),
           let pregnancyInput = input.pregnancyCheck {
            let check = CDPregnancyCheck(context: context)
            check.id = try CoreDataAnimalMutation.uniqueID(
                for: CDPregnancyCheck.self,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            check.date = pregnancyInput.date
            check.resultRawValue = pregnancyInput.result.rawValue
            check.technician = nil
            if let estimatedDaysPregnant = pregnancyInput.estimatedDaysPregnant {
                check.estimatedDaysPregnant = NSNumber(value: estimatedDaysPregnant)
            } else {
                check.estimatedDaysPregnant = nil
            }
            check.dueDate = pregnancyInput.dueDate
            check.herd = herd
            check.animal = animal
            check.sire = sire
            check.workingSession = session
        }

        deleteHealthRecords(session: session, animal: animal, in: context)

        if input.castrationPerformed {
            try insertGeneratedHealthRecord(
                kind: .castration,
                notes: nil,
                date: recordDate,
                session: session,
                animal: animal,
                herd: herd,
                lookup: lookup,
                in: context
            )
        }

        let observationNotes = WorkingWorkDataRules.normalizedObservationNotes(
            input.observationNotes
        )
        if !observationNotes.isEmpty {
            try insertGeneratedHealthRecord(
                kind: .observation,
                notes: observationNotes,
                date: recordDate,
                session: session,
                animal: animal,
                herd: herd,
                lookup: lookup,
                in: context
            )
        }
    }

    static func deleteAll(
        session: CDWorkingSession,
        animal: CDAnimal,
        in context: NSManagedObjectContext
    ) {
        deleteTreatmentRecords(session: session, animal: animal, in: context)
        deletePregnancyChecks(session: session, animal: animal, in: context)
        deleteHealthRecords(session: session, animal: animal, in: context)
    }

    private static func insertGeneratedHealthRecord(
        kind: WorkingGeneratedHealthRecord,
        notes: String?,
        date: Date,
        session: CDWorkingSession,
        animal: CDAnimal,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws {
        let record = CDHealthRecord(context: context)
        record.id = try CoreDataAnimalMutation.uniqueID(
            for: CDHealthRecord.self,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )
        record.date = date
        record.treatment = kind.treatmentName
        record.notes = notes
        record.herd = herd
        record.animal = animal
        record.workingSession = session
    }

    private static func deleteTreatmentRecords(
        session: CDWorkingSession,
        animal: CDAnimal,
        in context: NSManagedObjectContext
    ) {
        let records = (session.treatmentRecords?.allObjects as? [CDWorkingTreatmentRecord]) ?? []
        for record in records where record.animalIDSnapshot == animal.id {
            context.delete(record)
        }
    }

    private static func deletePregnancyChecks(
        session: CDWorkingSession,
        animal: CDAnimal,
        in context: NSManagedObjectContext
    ) {
        let checks = (session.pregnancyChecks?.allObjects as? [CDPregnancyCheck]) ?? []
        for check in checks where check.animal.id == animal.id {
            context.delete(check)
        }
    }

    private static func deleteHealthRecords(
        session: CDWorkingSession,
        animal: CDAnimal,
        in context: NSManagedObjectContext
    ) {
        let records = (session.healthRecords?.allObjects as? [CDHealthRecord]) ?? []
        for record in records where record.animal.id == animal.id {
            context.delete(record)
        }
    }
}
