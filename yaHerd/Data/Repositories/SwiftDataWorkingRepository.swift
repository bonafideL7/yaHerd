import Foundation
import SwiftData

struct SwiftDataWorkingRepository: WorkingRepository {
    let context: ModelContext

    func createSession(date: Date, sourcePasture: Pasture?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> WorkingSession {
        let session = WorkingSession(date: date, status: .active, sourcePasture: sourcePasture, protocolName: protocolName, protocolItems: protocolItems)
        context.insert(session)
        try context.save()
        return session
    }

    func collectAnimals(session: WorkingSession, animals: [Animal]) throws {
        let startOrder = (session.queueItems.map(\.queueOrder).max() ?? -1) + 1
        var order = startOrder
        let source = session.sourcePasture

        for animal in animals.sorted(by: { $0.tagNumber < $1.tagNumber }) {
            animal.pasture = nil
            animal.location = .workingPen
            animal.activeWorkingSession = session

            let item = WorkingQueueItem(
                queueOrder: order,
                status: .queued,
                collectedFromPasture: source,
                destinationPasture: nil,
                workNotes: nil,
                animal: animal,
                session: session
            )
            context.insert(item)
            session.queueItems.append(item)
            order += 1
        }

        try context.save()
    }

    func complete(queueItem: WorkingQueueItem, in session: WorkingSession, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws {
        guard let animal = queueItem.animal else { return }

        queueItem.status = .done
        queueItem.completedAt = .now

        try deleteTreatmentRecords(session: session, animal: animal)
        for entry in treatmentEntries {
            let record = WorkingTreatmentRecord(date: entry.date, itemName: entry.itemName, given: entry.given, quantity: entry.quantity, animal: animal, session: session)
            context.insert(record)
        }

        try deletePregnancyChecks(session: session, animal: animal)
        if let pregnancyCheck, pregnancyCheck.result == .open || pregnancyCheck.result == .pregnant {
            let check = PregnancyCheck(
                date: pregnancyCheck.date,
                result: pregnancyCheck.result,
                technician: nil,
                estimatedDaysPregnant: pregnancyCheck.estimatedDaysPregnant,
                dueDate: pregnancyCheck.dueDate,
                sireAnimal: try fetchAnimal(id: pregnancyCheck.sireAnimalID),
                workingSession: session,
                animal: animal
            )
            context.insert(check)
        }

        try deleteHealthRecords(session: session, animal: animal, treatment: "Castration")
        if markCastrated {
            let record = HealthRecord(date: .now, treatment: "Castration", notes: nil, workingSession: session, animal: animal)
            context.insert(record)
        }

        try deleteHealthRecords(session: session, animal: animal, treatment: "Observation")
        let trimmedNotes = observationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            let record = HealthRecord(date: .now, treatment: "Observation", notes: trimmedNotes, workingSession: session, animal: animal)
            context.insert(record)
        }

        try context.save()
    }

    func saveEdits(for queueItem: WorkingQueueItem, in session: WorkingSession, input: WorkingSessionAnimalEditInput) throws {
        guard let animal = queueItem.animal else { return }

        queueItem.status = input.status
        queueItem.completedAt = input.status == .done ? (input.completedAt ?? .now) : nil
        queueItem.destinationPasture = try fetchPasture(id: input.destinationPastureID)

        try deleteTreatmentRecords(session: session, animal: animal)
        for entry in input.treatmentEntries {
            let record = WorkingTreatmentRecord(date: entry.date, itemName: entry.itemName, given: entry.given, quantity: entry.quantity, animal: animal, session: session)
            context.insert(record)
        }

        try deletePregnancyChecks(session: session, animal: animal)
        if let pregnancyCheck = input.pregnancyCheck,
           pregnancyCheck.result == .open || pregnancyCheck.result == .pregnant {
            let check = PregnancyCheck(
                date: pregnancyCheck.date,
                result: pregnancyCheck.result,
                technician: nil,
                estimatedDaysPregnant: pregnancyCheck.estimatedDaysPregnant,
                dueDate: pregnancyCheck.dueDate,
                sireAnimal: try fetchAnimal(id: pregnancyCheck.sireAnimalID),
                workingSession: session,
                animal: animal
            )
            context.insert(check)
        }

        try deleteHealthRecords(session: session, animal: animal, treatment: "Castration")
        if input.castrationPerformed {
            let record = HealthRecord(date: .now, treatment: "Castration", notes: nil, workingSession: session, animal: animal)
            context.insert(record)
        }

        try deleteHealthRecords(session: session, animal: animal, treatment: "Observation")
        let trimmedNotes = input.observationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            let record = HealthRecord(date: .now, treatment: "Observation", notes: trimmedNotes, workingSession: session, animal: animal)
            context.insert(record)
        }

        try context.save()
    }

    func deleteWorkData(for queueItem: WorkingQueueItem, in session: WorkingSession) throws {
        guard let animal = queueItem.animal else { return }
        try deleteTreatmentRecords(session: session, animal: animal)
        try deletePregnancyChecks(session: session, animal: animal)
        try deleteHealthRecords(session: session, animal: animal)
        queueItem.status = .queued
        queueItem.completedAt = nil
        try context.save()
    }

    func deleteSession(_ session: WorkingSession) throws {
        for item in session.queueItems {
            guard let animal = item.animal else { continue }
            if animal.activeWorkingSession?.persistentModelID == session.persistentModelID || animal.location == .workingPen {
                let destination = item.collectedFromPasture ?? session.sourcePasture
                animal.pasture = destination
                animal.location = .pasture
                animal.activeWorkingSession = nil
            }
        }

        try deleteSessionLinkedRecords(session: session)
        context.delete(session)
        try context.save()
    }

    func finishSession(_ session: WorkingSession) throws {
        var changedAny = false
        for item in session.queueItems.sorted(by: { $0.queueOrder < $1.queueOrder }) {
            guard let animal = item.animal else { continue }
            let destination = item.destinationPasture ?? session.sourcePasture
            let changed = try AnimalMovementService.move(animal, to: destination, in: context, fromPastureName: item.collectedFromPasture?.name, save: false)
            changedAny = changedAny || changed
        }
        session.status = .finished
        if changedAny || session.status == .finished {
            try context.save()
        }
    }

    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> WorkingProtocolTemplate {
        let template = WorkingProtocolTemplate(name: name, items: items)
        context.insert(template)
        try context.save()
        return template
    }

    func updateTemplate(_ template: WorkingProtocolTemplate, name: String, items: [WorkingProtocolItem]) throws {
        template.name = name
        template.items = items
        try context.save()
    }

    func deleteTemplates(_ templates: [WorkingProtocolTemplate]) throws {
        for template in templates {
            context.delete(template)
        }
        try context.save()
    }

    private func fetchAnimal(id: UUID?) throws -> Animal? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Animal>(predicate: #Predicate<Animal> { animal in animal.publicID == id })
        return try context.fetch(descriptor).first
    }

    private func fetchPasture(id: UUID?) throws -> Pasture? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Pasture>(predicate: #Predicate<Pasture> { pasture in pasture.publicID == id })
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
        for check in try context.fetch(FetchDescriptor<PregnancyCheck>()) where check.workingSession?.persistentModelID == sid && check.animal.persistentModelID == aid {
            context.delete(check)
        }
    }

    private func deleteHealthRecords(session: WorkingSession, animal: Animal, treatment: String? = nil) throws {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        for record in try context.fetch(FetchDescriptor<HealthRecord>()) where record.workingSession?.persistentModelID == sid && record.animal.persistentModelID == aid {
            if let treatment, record.treatment != treatment { continue }
            context.delete(record)
        }
    }

    private func deleteSessionLinkedRecords(session: WorkingSession) throws {
        let sid = session.persistentModelID
        for record in try context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) where record.session?.persistentModelID == sid {
            context.delete(record)
        }
        for check in try context.fetch(FetchDescriptor<PregnancyCheck>()) where check.workingSession?.persistentModelID == sid {
            context.delete(check)
        }
        for record in try context.fetch(FetchDescriptor<HealthRecord>()) where record.workingSession?.persistentModelID == sid {
            context.delete(record)
        }
    }
}
