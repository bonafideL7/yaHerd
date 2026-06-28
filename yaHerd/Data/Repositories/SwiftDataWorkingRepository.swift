import Foundation
import SwiftData

struct SwiftDataWorkingRepository: WorkingRepository {
    let context: ModelContext

    func fetchSessions() throws -> [WorkingSessionSummary] {
        let descriptor = FetchDescriptor<WorkingSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try context.fetch(descriptor).map(WorkingMapper.makeSessionSummary)
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        guard let session = try? fetchSession(id: id) else { return nil }
        return WorkingMapper.makeSessionDetail(from: session)
    }

    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] {
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map(WorkingMapper.makeTemplateSummary)
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot? {
        guard let template = try? fetchTemplate(id: id) else { return nil }
        return WorkingMapper.makeTemplateDetail(from: template)
    }

    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot? {
        let session = try fetchSession(id: sessionID)
        let queueItem = try fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return nil }

        let treatmentRecords = try fetchTreatmentRecords(session: session, animal: animal)
            .sorted { lhs, rhs in
                if lhs.itemName != rhs.itemName { return lhs.itemName.localizedStandardCompare(rhs.itemName) == .orderedAscending }
                return lhs.date > rhs.date
            }
            .map(WorkingMapper.makeTreatmentRecordSnapshot)

        let pregnancyCheck = try fetchPregnancyChecks(session: session, animal: animal)
            .sorted { $0.date > $1.date }
            .first
            .map(WorkingMapper.makePregnancyCheckSnapshot)

        let healthRecords = try fetchHealthRecords(session: session, animal: animal)
        let observationNotes = healthRecords.first(where: { $0.treatment == WorkingGeneratedHealthRecord.observation.treatmentName })?.notes ?? ""
        let castrationPerformed = healthRecords.contains(where: { $0.treatment == WorkingGeneratedHealthRecord.castration.treatmentName })

        return WorkingMapper.makeQueueItemEditorSnapshot(
            session: session,
            queueItem: queueItem,
            animal: animal,
            treatmentRecords: treatmentRecords,
            pregnancyCheck: pregnancyCheck,
            castrationPerformed: castrationPerformed,
            observationNotes: observationNotes
        )
    }

    func createSession(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID {
        let session = WorkingSession(
            date: date,
            status: .active,
            sourcePasture: try fetchPasture(id: sourcePastureID),
            protocolName: protocolName,
            protocolItems: protocolItems
        )
        try ensureUniqueSessionPublicID(session)
        context.insert(session)
        try context.save()
        return session.publicID
    }

    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {
        let session = try fetchSession(id: sessionID)
        let animals = try fetchAnimals(ids: animalIDs)
        try validateCollection(animals: animals, for: session)
        let startOrder = (session.queueItems.map(\.queueOrder).max() ?? -1) + 1
        var order = startOrder
        let source = session.sourcePasture

        for animal in animals.sorted(by: { $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending }) {
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
            try ensureUniqueQueueItemPublicID(item)
            context.insert(item)
            session.queueItems.append(item)
            order += 1
        }

        try context.save()
    }

    func complete(queueItemID: UUID, inSessionID sessionID: UUID, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws {
        let session = try fetchSession(id: sessionID)
        let queueItem = try fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }

        let completedAt = Date.now
        queueItem.status = .done
        queueItem.completedAt = completedAt

        let input = WorkingQueueItemWorkDataInput(
            treatmentEntries: treatmentEntries,
            pregnancyCheck: pregnancyCheck,
            castrationPerformed: markCastrated,
            observationNotes: observationNotes
        )
        try workDataWriter.replaceWorkData(session: session, animal: animal, input: input, recordDate: completedAt)
        try context.save()
    }

    func saveEdits(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID, input: WorkingSessionAnimalEditInput) throws {
        let session = try fetchSession(id: sessionID)
        let queueItem = try fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }

        let completedAt = input.status == .done ? (input.completedAt ?? Date.now) : nil
        queueItem.status = input.status
        queueItem.completedAt = completedAt
        queueItem.destinationPasture = try fetchPasture(id: input.destinationPastureID)

        try workDataWriter.replaceWorkData(session: session, animal: animal, input: input.workData, recordDate: completedAt ?? Date.now)
        try context.save()
    }

    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {
        let session = try fetchSession(id: sessionID)
        let queueItem = try fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }
        try workDataWriter.deleteAllWorkData(session: session, animal: animal)
        queueItem.status = .queued
        queueItem.completedAt = nil
        try context.save()
    }

    func deleteSession(id: UUID) throws {
        let session = try fetchSession(id: id)
        for item in session.queueItems {
            guard let animal = item.animal else { continue }
            if animal.activeWorkingSession?.publicID == session.publicID || animal.location == .workingPen {
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

    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {
        let session = try fetchSession(id: sessionID)
        let destinationsByQueueItemID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.queueItemID, $0.destinationPastureID) })
        guard !destinationsByQueueItemID.isEmpty else { return }

        for item in session.queueItems {
            guard let destinationPastureID = destinationsByQueueItemID[item.publicID] else { continue }
            item.destinationPasture = try fetchPasture(id: destinationPastureID)
        }

        try context.save()
    }

    func finishSession(id: UUID) throws {
        let session = try fetchSession(id: id)
        for item in session.queueItems.sorted(by: { $0.queueOrder < $1.queueOrder }) {
            guard let animal = item.animal else { continue }
            let destination = item.destinationPasture ?? session.sourcePasture
            _ = try AnimalMovementStore.move(
                animal,
                to: destination,
                in: context,
                fromPastureName: item.collectedFromPasture?.name,
                save: false
            )
        }
        session.status = .finished
        try context.save()
    }

    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try templateNameExists(normalizedName, excluding: nil) {
            throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
        }

        let template = WorkingProtocolTemplate(name: normalizedName, items: items)
        try ensureUniqueTemplatePublicID(template)
        context.insert(template)
        try context.save()
        return template.publicID
    }

    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws {
        let template = try fetchTemplate(id: id)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try templateNameExists(normalizedName, excluding: id) {
            throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
        }

        template.name = normalizedName
        template.items = items
        try context.save()
    }

    func deleteTemplates(ids: [UUID]) throws {
        for id in ids {
            let template = try fetchTemplate(id: id)
            context.delete(template)
        }
        try context.save()
    }

    private var workDataWriter: SwiftDataWorkingWorkDataWriter {
        SwiftDataWorkingWorkDataWriter(context: context)
    }

    private func fetchSession(id: UUID) throws -> WorkingSession {
        let descriptor = FetchDescriptor<WorkingSession>(predicate: #Predicate<WorkingSession> { session in
            session.publicID == id
        })
        guard let session = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.sessionNotFound
        }
        return session
    }

    private func fetchQueueItem(id: UUID, sessionID: UUID) throws -> WorkingQueueItem {
        let descriptor = FetchDescriptor<WorkingQueueItem>(predicate: #Predicate<WorkingQueueItem> { item in
            item.publicID == id
        })
        guard let item = try context.fetch(descriptor).first,
              item.session?.publicID == sessionID else {
            throw WorkingRepositoryError.queueItemNotFound
        }
        return item
    }

    private func fetchTemplate(id: UUID) throws -> WorkingProtocolTemplate {
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>(predicate: #Predicate<WorkingProtocolTemplate> { template in
            template.publicID == id
        })
        guard let template = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.templateNotFound
        }
        return template
    }

    private func ensureUniqueSessionPublicID(_ session: WorkingSession) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<WorkingSession>()).map(\.publicID))
        while existingIDs.contains(session.publicID) {
            session.publicID = UUID()
        }
    }

    private func ensureUniqueQueueItemPublicID(_ item: WorkingQueueItem) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<WorkingQueueItem>()).map(\.publicID))
        while existingIDs.contains(item.publicID) {
            item.publicID = UUID()
        }
    }

    private func ensureUniqueTemplatePublicID(_ template: WorkingProtocolTemplate) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<WorkingProtocolTemplate>()).map(\.publicID))
        while existingIDs.contains(template.publicID) {
            template.publicID = UUID()
        }
    }

    private func templateNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>()
        return try context.fetch(descriptor).contains { template in
            if let id, template.publicID == id {
                return false
            }
            return template.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    private func fetchAnimals(ids: [UUID]) throws -> [Animal] {
        guard !ids.isEmpty else { return [] }
        let all = try context.fetch(FetchDescriptor<Animal>())
        let animalsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.publicID, $0) })
        return ids.compactMap { animalsByID[$0] }
    }

    private func fetchPasture(id: UUID?) throws -> Pasture? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Pasture>(predicate: #Predicate<Pasture> { pasture in pasture.publicID == id })
        return try context.fetch(descriptor).first
    }

    private func fetchTreatmentRecords(session: WorkingSession, animal: Animal) throws -> [WorkingTreatmentRecord] {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        return try context.fetch(FetchDescriptor<WorkingTreatmentRecord>()).filter {
            $0.session?.persistentModelID == sid && $0.animal?.persistentModelID == aid
        }
    }

    private func fetchPregnancyChecks(session: WorkingSession, animal: Animal) throws -> [PregnancyCheck] {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        return try context.fetch(FetchDescriptor<PregnancyCheck>()).filter {
            $0.workingSession?.persistentModelID == sid && $0.animal?.persistentModelID == aid
        }
    }

    private func fetchHealthRecords(session: WorkingSession, animal: Animal) throws -> [HealthRecord] {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        return try context.fetch(FetchDescriptor<HealthRecord>()).filter {
            $0.workingSession?.persistentModelID == sid && $0.animal?.persistentModelID == aid
        }
    }

    private func validateCollection(animals: [Animal], for session: WorkingSession) throws {
        let existingAnimalIDs = Set(session.queueItems.compactMap { $0.animal?.publicID })
        for animal in animals {
            if existingAnimalIDs.contains(animal.publicID) {
                throw WorkingRepositoryError.duplicateAnimalCollection
            }

            if let activeSession = animal.activeWorkingSession, activeSession.publicID != session.publicID {
                throw WorkingRepositoryError.animalAlreadyInAnotherSession
            }
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
