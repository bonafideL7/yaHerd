import Foundation
import SwiftData

@MainActor
struct SwiftDataWorkingRepository: WorkingRepository {
    let context: ModelContext
    private let dateProvider: any DateProviding

    init(context: ModelContext, dateProvider: any DateProviding = SystemDateProvider()) {
        self.context = context
        self.dateProvider = dateProvider
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        try PerformanceLog.measure("SwiftDataWorkingRepository.fetchSessions") {
            let descriptor = FetchDescriptor<WorkingSession>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            return try context.fetch(descriptor).map(WorkingMapper.makeSessionSummary)
        }
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        do {
            let session = try lookup.fetchSession(id: id)
            return WorkingMapper.makeSessionDetail(from: session)
        } catch WorkingRepositoryError.sessionNotFound {
            return nil
        } catch {
            throw error
        }
    }

    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] {
        try PerformanceLog.measure("SwiftDataWorkingRepository.fetchTemplates") {
            let descriptor = FetchDescriptor<WorkingProtocolTemplate>(
                sortBy: [SortDescriptor(\.name)]
            )
            return try context.fetch(descriptor).map(WorkingMapper.makeTemplateSummary)
        }
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingProtocolTemplateDetailSnapshot? {
        do {
            let template = try lookup.fetchTemplate(id: id)
            return WorkingMapper.makeTemplateDetail(from: template)
        } catch WorkingRepositoryError.templateNotFound {
            return nil
        } catch {
            throw error
        }
    }

    func fetchQueueItemEditor(
        sessionID: UUID,
        queueItemID: UUID
    ) throws -> WorkingQueueItemEditorSnapshot? {
        let session = try lookup.fetchSession(id: sessionID)
        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return nil }

        let treatmentRecords = try lookup.fetchTreatmentRecords(session: session, animal: animal)
            .sorted { lhs, rhs in
                let leftIndex = session.protocolItems.firstIndex { $0.id == lhs.treatmentItemID }
                    ?? Int.max
                let rightIndex = session.protocolItems.firstIndex { $0.id == rhs.treatmentItemID }
                    ?? Int.max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
                return lhs.date > rhs.date
            }
            .map(WorkingMapper.makeTreatmentRecordSnapshot)

        let pregnancyCheck = try lookup.fetchPregnancyChecks(session: session, animal: animal)
            .sorted { $0.date > $1.date }
            .first
            .map(WorkingMapper.makePregnancyCheckSnapshot)

        let healthRecords = try lookup.fetchHealthRecords(session: session, animal: animal)
        let observationNotes = healthRecords.first(where: {
            $0.treatment == WorkingGeneratedHealthRecord.observation.treatmentName
        })?.notes ?? ""
        let castrationPerformed = healthRecords.contains(where: {
            $0.treatment == WorkingGeneratedHealthRecord.castration.treatmentName
        })

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

    func createSession(
        date: Date,
        sourcePastureID: UUID?,
        protocolName: String,
        protocolItems: [WorkingProtocolItem]
    ) throws -> UUID {
        try WorkingTreatmentPlanRules.validate(protocolItems)
        let session = WorkingSession(
            date: date,
            status: .active,
            sourcePasture: try lookup.fetchPasture(id: sourcePastureID),
            protocolName: protocolName,
            protocolItems: protocolItems
        )
        try idStore.ensureUniqueSessionPublicID(session)
        try context.insertIntoDefaultHerd(session)
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
        return session.publicID
    }

    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {
        let session = try fetchActiveSession(id: sessionID)
        let animals = try lookup.fetchAnimals(ids: animalIDs)
        try validateCollection(animals: animals, for: session)
        let source = session.sourcePasture

        for animal in animals.sorted(by: {
            $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending
        }) {
            animal.pasture = nil
            animal.location = .workingPen
            animal.activeWorkingSession = session

            let item = WorkingQueueItem(
                status: .queued,
                collectedFromPasture: source,
                destinationPasture: nil,
                workNotes: nil,
                animal: animal,
                session: session
            )
            try idStore.ensureUniqueQueueItemPublicID(item)
            try context.insertIntoDefaultHerd(item)
            session.queueItems.append(item)
        }

        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
    }

    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) throws {
        try WorkingTreatmentPlanRules.validate(treatmentEntries)
        let session = try fetchActiveSession(id: sessionID)
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
        try workDataWriter.replaceWorkData(
            session: session,
            animal: animal,
            input: input,
            recordDate: completedAt
        )
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
    }

    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) throws {
        try WorkingTreatmentPlanRules.validate(input.treatmentEntries)
        let session = try fetchActiveSession(id: sessionID)
        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }

        let now = dateProvider.now
        let completedAt = input.status == .done ? (input.completedAt ?? now) : nil
        queueItem.status = input.status
        queueItem.completedAt = completedAt
        queueItem.destinationPasture = try lookup.fetchPasture(id: input.destinationPastureID)

        try workDataWriter.replaceWorkData(
            session: session,
            animal: animal,
            input: input.workData,
            recordDate: completedAt ?? now
        )
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
    }

    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {
        let session = try fetchActiveSession(id: sessionID)
        let queueItem = try lookup.fetchQueueItem(id: queueItemID, sessionID: sessionID)
        guard let animal = queueItem.animal else { return }
        try workDataWriter.deleteAllWorkData(session: session, animal: animal)
        queueItem.status = .queued
        queueItem.completedAt = nil
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
    }

    func deleteSession(id: UUID) throws {
        let session = try lookup.fetchSession(id: id)
        for item in session.queueItems {
            guard let animal = item.animal else { continue }
            let activeSessionID = animal.activeWorkingSession?.publicID
            if activeSessionID == session.publicID
                || (activeSessionID == nil && animal.location == .workingPen)
            {
                let destination = item.collectedFromPasture ?? session.sourcePasture
                animal.pasture = destination
                animal.location = .pasture
                animal.activeWorkingSession = nil
            }
        }

        try sessionCleanupWriter.deleteLinkedRecords(session: session)
        context.delete(session)
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
    }

    func completeSession(
        id: UUID,
        assignments: [WorkingQueueDestinationAssignment]
    ) throws {
        let session = try fetchActiveSession(id: id)
        var destinationsByQueueItemID: [UUID: UUID?] = [:]
        for assignment in assignments {
            guard !destinationsByQueueItemID.keys.contains(assignment.queueItemID) else {
                throw WorkingRepositoryError.duplicateQueueItemAssignments
            }
            destinationsByQueueItemID.updateValue(
                assignment.destinationPastureID,
                forKey: assignment.queueItemID
            )
        }

        let queueItemIDs = Set(session.queueItems.map(\.publicID))
        guard Set(destinationsByQueueItemID.keys) == queueItemIDs else {
            throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
        }

        try validateCompletionOwnership(for: session)

        for item in session.queueItems {
            guard let animal = item.animal else { continue }
            guard let assignedPastureID = destinationsByQueueItemID[item.publicID] else {
                throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
            }
            let destination = try lookup.fetchPasture(id: assignedPastureID)
                ?? session.sourcePasture
            item.destinationPasture = destination

            let fromPastureName: String?
            if animal.location == .workingPen {
                fromPastureName = item.collectedFromPasture?.name ?? session.sourcePasture?.name
            } else {
                fromPastureName = animal.pasture?.name
            }

            _ = try AnimalMovementStore.move(
                animal,
                to: destination,
                in: context,
                fromPastureName: fromPastureName,
                save: false
            )
        }

        session.status = .finished
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
    }

    func reopenSession(id: UUID) throws {
        let session = try lookup.fetchSession(id: id)
        switch session.status {
        case .finished:
            session.status = .active
        case .active:
            throw WorkingRepositoryError.sessionAlreadyActive
        case .cancelled:
            throw WorkingRepositoryError.sessionCannotBeReopened
        }

        try PersistenceLog.save(
            context,
            operation: "SwiftDataWorkingRepository.reopenSession"
        )
    }

    func createTemplate(name: String, items: [WorkingProtocolItem]) throws -> UUID {
        try WorkingTreatmentPlanRules.validate(items)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try lookup.templateNameExists(normalizedName, excluding: nil) {
            throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
        }

        let template = WorkingProtocolTemplate(name: normalizedName, items: items)
        try idStore.ensureUniqueTemplatePublicID(template)
        try context.insertIntoDefaultHerd(template)
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
        return template.publicID
    }

    func updateTemplate(id: UUID, name: String, items: [WorkingProtocolItem]) throws {
        try WorkingTreatmentPlanRules.validate(items)
        let template = try lookup.fetchTemplate(id: id)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if try lookup.templateNameExists(normalizedName, excluding: id) {
            throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
        }

        template.name = normalizedName
        template.items = items
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
    }

    func deleteTemplates(ids: [UUID]) throws {
        let templates = try lookup.fetchTemplates(ids: ids)
        for template in templates {
            context.delete(template)
        }
        try PersistenceLog.save(context, operation: "SwiftDataWorkingRepository")
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

    private func validateCompletionOwnership(for session: WorkingSession) throws {
        let hasConflictingOwnership = session.queueItems.contains { item in
            guard let activeSessionID = item.animal?.activeWorkingSession?.publicID else {
                return false
            }
            return activeSessionID != session.publicID
        }

        guard !hasConflictingOwnership else {
            throw WorkingRepositoryError.animalAlreadyInAnotherSession
        }
    }

    private func fetchActiveSession(id: UUID) throws -> WorkingSession {
        let session = try lookup.fetchSession(id: id)
        guard session.status == .active else {
            throw WorkingRepositoryError.sessionAlreadyFinished
        }
        return session
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
