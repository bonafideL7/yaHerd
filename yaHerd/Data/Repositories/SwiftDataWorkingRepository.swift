import Foundation
import SwiftData

struct SwiftDataWorkingRepository: WorkingRepository {
    let context: ModelContext
    private let dateProvider: any DateProviding

    init(context: ModelContext, dateProvider: any DateProviding = SystemDateProvider()) {
        self.context = context
        self.dateProvider = dateProvider
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        let descriptor = FetchDescriptor<WorkingSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try context.fetch(descriptor).map(WorkingMapper.makeSessionSummary)
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        guard let session = try? lookup.fetchSession(id: id) else { return nil }
        return WorkingMapper.makeSessionDetail(from: session)
    }

    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] {
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map(WorkingMapper.makeTemplateSummary)
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot? {
        guard let template = try? lookup.fetchTemplate(id: id) else { return nil }
        return WorkingMapper.makeTemplateDetail(from: template)
    }

    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot? {
        let session = try lookup.fetchSession(id: sessionID)
        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return nil }

        let treatmentRecords = try lookup.fetchTreatmentRecords(session: session, animal: animal)
            .sorted { lhs, rhs in
                if lhs.itemName != rhs.itemName { return lhs.itemName.localizedStandardCompare(rhs.itemName) == .orderedAscending }
                return lhs.date > rhs.date
            }
            .map(WorkingMapper.makeTreatmentRecordSnapshot)

        let pregnancyCheck = try lookup.fetchPregnancyChecks(session: session, animal: animal)
            .sorted { $0.date > $1.date }
            .first
            .map(WorkingMapper.makePregnancyCheckSnapshot)

        let healthRecords = try lookup.fetchHealthRecords(session: session, animal: animal)
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
            sourcePasture: try lookup.fetchPasture(id: sourcePastureID),
            protocolName: protocolName,
            protocolItems: protocolItems
        )
        try idStore.ensureUniqueSessionPublicID(session)
        context.insert(session)
        try context.save()
        return session.publicID
    }

    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {
        let session = try lookup.fetchSession(id: sessionID)
        let animals = try lookup.fetchAnimals(ids: animalIDs)
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
            try idStore.ensureUniqueQueueItemPublicID(item)
            context.insert(item)
            session.queueItems.append(item)
            order += 1
        }

        try context.save()
    }

    func complete(queueItemID: UUID, inSessionID sessionID: UUID, treatmentEntries: [WorkingTreatmentEntryInput], pregnancyCheck: WorkingPregnancyCheckInput?, markCastrated: Bool, observationNotes: String) throws {
        let session = try lookup.fetchSession(id: sessionID)
        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }

        let completedAt = dateProvider.now
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
        let session = try lookup.fetchSession(id: sessionID)
        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }

        let now = dateProvider.now
        let completedAt = input.status == .done ? (input.completedAt ?? now) : nil
        queueItem.status = input.status
        queueItem.completedAt = completedAt
        queueItem.destinationPasture = try lookup.fetchPasture(id: input.destinationPastureID)

        try workDataWriter.replaceWorkData(session: session, animal: animal, input: input.workData, recordDate: completedAt ?? now)
        try context.save()
    }

    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {
        let session = try lookup.fetchSession(id: sessionID)
        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }
        try workDataWriter.deleteAllWorkData(session: session, animal: animal)
        queueItem.status = .queued
        queueItem.completedAt = nil
        try context.save()
    }

    func deleteSession(id: UUID) throws {
        let session = try lookup.fetchSession(id: id)
        for item in session.queueItems {
            guard let animal = item.animal else { continue }
            if animal.activeWorkingSession?.publicID == session.publicID || animal.location == .workingPen {
                let destination = item.collectedFromPasture ?? session.sourcePasture
                animal.pasture = destination
                animal.location = .pasture
                animal.activeWorkingSession = nil
            }
        }

        try sessionCleanupWriter.deleteLinkedRecords(session: session)
        context.delete(session)
        try context.save()
    }

    func saveDestinations(sessionID: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {
        let session = try lookup.fetchSession(id: sessionID)
        let destinationsByQueueItemID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.queueItemID, $0.destinationPastureID) })
        guard !destinationsByQueueItemID.isEmpty else { return }

        for item in session.queueItems {
            guard let destinationPastureID = destinationsByQueueItemID[item.publicID] else { continue }
            item.destinationPasture = try lookup.fetchPasture(id: destinationPastureID)
        }

        try context.save()
    }

    func finishSession(id: UUID) throws {
        let session = try lookup.fetchSession(id: id)
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
        if try lookup.templateNameExists(normalizedName, excluding: nil) {
            throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
        }

        let template = WorkingProtocolTemplate(name: normalizedName, items: items)
        try idStore.ensureUniqueTemplatePublicID(template)
        context.insert(template)
        try context.save()
        return template.publicID
    }

    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws {
        let template = try lookup.fetchTemplate(id: id)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try lookup.templateNameExists(normalizedName, excluding: id) {
            throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
        }

        template.name = normalizedName
        template.items = items
        try context.save()
    }

    func deleteTemplates(ids: [UUID]) throws {
        for id in ids {
            let template = try lookup.fetchTemplate(id: id)
            context.delete(template)
        }
        try context.save()
    }

    private var lookup: SwiftDataWorkingLookupStore {
        SwiftDataWorkingLookupStore(context: context)
    }

    private var idStore: SwiftDataPublicIDUniquenessStore {
        SwiftDataPublicIDUniquenessStore(context: context)
    }

    private var workDataWriter: SwiftDataWorkingWorkDataWriter {
        SwiftDataWorkingWorkDataWriter(context: context)
    }

    private var sessionCleanupWriter: SwiftDataWorkingSessionCleanupWriter {
        SwiftDataWorkingSessionCleanupWriter(context: context)
    }

    private func validateCollection(animals: [Animal], for session: WorkingSession) throws {
        let existingAnimalIDs = Set(session.queueItems.compactMap { $0.animal?.publicID })
        let candidates = animals.map {
            WorkingCollectionCandidate(
                animalID: $0.publicID,
                activeSessionID: $0.activeWorkingSession?.publicID
            )
        }
        try WorkingCollectionRules.validateCollection(
            existingAnimalIDs: existingAnimalIDs,
            candidates: candidates,
            sessionID: session.publicID
        )
    }
}