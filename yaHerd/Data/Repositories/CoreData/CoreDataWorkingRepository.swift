@preconcurrency import CoreData
import Foundation

enum CoreDataWorkingRepositoryError: Error, Equatable {
    case invalidHerdOwnership(
        relationship: String,
        expectedHerdID: UUID,
        actualHerdID: UUID
    )
    case invalidSessionRelationship(
        relationship: String,
        expectedSessionID: UUID,
        actualSessionID: UUID?
    )
    case invalidSnapshotRelationship(
        relationship: String,
        expectedID: UUID?,
        actualID: UUID?
    )
}

@MainActor
final class CoreDataWorkingRepository:
    WorkingSessionListReader,
    WorkingSessionDetailReader,
    WorkingQueueItemEditorReader,
    WorkingSessionStarting,
    WorkingAnimalCollecting,
    WorkingQueueItemCompleting,
    WorkingQueueItemEditSaving,
    WorkingQueueItemDataDeleting
{
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let transactionExecutor: CoreDataTransactionExecutor
    private let animalWriteBoundary: CoreDataAnimalWriteBoundary
    private let workingWriteGate: CoreDataAsyncSerialGate
    private let pastureResidentWriteCoordinator: CoreDataPastureResidentWriteCoordinator
    private let dateProvider: any DateProviding
    private nonisolated let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        transactionExecutor: CoreDataTransactionExecutor,
        animalWriteBoundary: CoreDataAnimalWriteBoundary,
        workingWriteGate: CoreDataAsyncSerialGate,
        pastureResidentWriteCoordinator: CoreDataPastureResidentWriteCoordinator,
        lookup: CoreDataLookup,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.transactionExecutor = transactionExecutor
        self.animalWriteBoundary = animalWriteBoundary
        self.workingWriteGate = workingWriteGate
        self.pastureResidentWriteCoordinator = pastureResidentWriteCoordinator
        self.lookup = lookup
        self.dateProvider = dateProvider
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            transactionExecutor: assembly.transactionExecutor,
            animalWriteBoundary: assembly.animalWriteBoundary,
            workingWriteGate: assembly.workingWriteGate,
            pastureResidentWriteCoordinator: assembly.pastureResidentWriteCoordinator,
            lookup: assembly.lookup,
            dateProvider: dateProvider
        )
    }

    func fetchSessions() throws -> [WorkingSessionSummary] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let request = NSFetchRequest<CDWorkingSession>(
                entityName: CDWorkingSession.coreDataEntityName
            )
            request.predicate = NSPredicate(format: "herd == %@", herd)
            let sessions = try context.fetch(request)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                sessions,
                herdID: herdID
            )

            return try sessions
                .sorted {
                    if $0.date != $1.date {
                        return $0.date > $1.date
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .map { session in
                    try validateSessionGraph(session, herdID: herdID)
                    return try WorkingMapper.makeSessionSummary(from: session)
                }
        }
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }
            guard let session = try lookup.herdOwned(
                CDWorkingSession.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                return nil
            }

            try validateSessionGraph(session, herdID: herdID)
            return try WorkingMapper.makeSessionDetail(from: session)
        }
    }

    func fetchQueueItemEditor(
        sessionID: UUID,
        queueItemID: UUID
    ) throws -> WorkingQueueItemEditorSnapshot? {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }
            guard let session = try lookup.herdOwned(
                CDWorkingSession.self,
                id: sessionID,
                herdID: herdID,
                in: context
            ) else {
                return nil
            }
            guard let queueItem = try lookup.herdOwned(
                CDWorkingQueueItem.self,
                id: queueItemID,
                herdID: herdID,
                in: context
            ), queueItem.session.id == session.id else {
                return nil
            }
            guard let animal = queueItem.animal else {
                return nil
            }

            try validateSessionGraph(session, herdID: herdID)
            return try WorkingMapper.makeQueueItemEditorSnapshot(
                session: session,
                queueItem: queueItem,
                animal: animal
            )
        }
    }

    // MARK: - Queue work data

    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) async throws {
        try WorkingTreatmentPlanRules.validate(treatmentEntries)
        let completedAt = dateProvider.now
        let input = WorkingQueueItemWorkDataInput(
            treatmentEntries: treatmentEntries,
            pregnancyCheck: pregnancyCheck,
            castrationPerformed: markCastrated,
            observationNotes: observationNotes
        )
        let lookup = self.lookup

        try await performWrite { context, herd in
            let resolved = try Self.activeQueueTarget(
                sessionID: sessionID,
                queueItemID: queueItemID,
                herd: herd,
                lookup: lookup,
                in: context
            )
            guard let animal = resolved.animal else {
                return
            }

            _ = try CoreDataWorkingWorkDataMutation.validateReferences(
                input: input,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )

            resolved.queueItem.statusRawValue = WorkingQueueStatus.done.rawValue
            resolved.queueItem.completedAt = completedAt

            try CoreDataWorkingWorkDataMutation.replace(
                session: resolved.session,
                animal: animal,
                input: input,
                recordDate: completedAt,
                herd: herd,
                lookup: lookup,
                in: context
            )
        }
    }

    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) async throws {
        try WorkingTreatmentPlanRules.validate(input.treatmentEntries)
        let now = dateProvider.now
        let completedAt = input.status == .done ? (input.completedAt ?? now) : nil
        let destinationPastureID = input.destinationPastureID
        let workData = input.workData
        let statusRawValue = input.status.rawValue
        let lookup = self.lookup

        try await performWrite { context, herd in
            let resolved = try Self.activeQueueTarget(
                sessionID: sessionID,
                queueItemID: queueItemID,
                herd: herd,
                lookup: lookup,
                in: context
            )
            guard let animal = resolved.animal else {
                return
            }

            let destination: CDPasture?
            if let destinationPastureID {
                guard let persisted = try lookup.herdOwned(
                    CDPasture.self,
                    id: destinationPastureID,
                    herdID: herd.id,
                    in: context
                ) else {
                    throw WorkingRepositoryError.pastureNotFound
                }
                destination = persisted
            } else {
                destination = nil
            }

            _ = try CoreDataWorkingWorkDataMutation.validateReferences(
                input: workData,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )

            resolved.queueItem.statusRawValue = statusRawValue
            resolved.queueItem.completedAt = completedAt
            resolved.queueItem.destinationPasture = destination
            resolved.queueItem.destinationPastureIDSnapshot = destination?.id
            resolved.queueItem.destinationPastureNameSnapshot = destination?.name

            try CoreDataWorkingWorkDataMutation.replace(
                session: resolved.session,
                animal: animal,
                input: workData,
                recordDate: completedAt ?? now,
                herd: herd,
                lookup: lookup,
                in: context
            )
        }
    }

    func deleteWorkData(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID
    ) async throws {
        let lookup = self.lookup
        try await performWrite { context, herd in
            let resolved = try Self.activeQueueTarget(
                sessionID: sessionID,
                queueItemID: queueItemID,
                herd: herd,
                lookup: lookup,
                in: context
            )
            guard let animal = resolved.animal else {
                return
            }

            CoreDataWorkingWorkDataMutation.deleteAll(
                session: resolved.session,
                animal: animal,
                in: context
            )
            resolved.queueItem.statusRawValue = WorkingQueueStatus.queued.rawValue
            resolved.queueItem.completedAt = nil
        }
    }

    // MARK: - Session start and collection

    @discardableResult
    func startSession(input: WorkingSessionStartInput) async throws -> UUID {
        try WorkingTreatmentPlanRules.validate(input.plannedTreatments)

        let sourcePastureID = input.sourcePastureID
        let requestedAnimalIDs = input.animalIDs.map(Self.uniqueIDs)
        if let requestedAnimalIDs, requestedAnimalIDs.isEmpty {
            throw WorkingRepositoryError.noEligibleAnimals
        }

        let normalizedDate = Calendar.autoupdatingCurrent.startOfDay(for: input.date)
        let normalizedTemplateName = input.treatmentTemplateName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName: String
        if let normalizedTemplateName, !normalizedTemplateName.isEmpty {
            templateName = normalizedTemplateName
        } else {
            templateName = "Working Session"
        }
        let plannedTreatmentsData = try JSONEncoder().encode(input.plannedTreatments)
        let lookup = self.lookup

        return try await performWrite { context, herd in
            guard let sourcePasture = try lookup.herdOwned(
                CDPasture.self,
                id: sourcePastureID,
                herdID: herd.id,
                in: context
            ) else {
                throw WorkingRepositoryError.pastureNotFound
            }

            let animals = try Self.animalsForSessionStart(
                requestedIDs: requestedAnimalIDs,
                sourcePasture: sourcePasture,
                herd: herd,
                in: context
            )
            try Self.validateStartAnimals(
                animals,
                sourcePasture: sourcePasture
            )

            let session = CDWorkingSession(context: context)
            session.id = try CoreDataAnimalMutation.uniqueID(
                for: CDWorkingSession.self,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            session.date = normalizedDate
            session.statusRawValue = WorkingSessionStatus.active.rawValue
            session.treatmentTemplateNameSnapshot = templateName
            session.plannedTreatmentsData = plannedTreatmentsData
            session.sourcePastureIDSnapshot = sourcePasture.id
            session.sourcePastureNameSnapshot = sourcePasture.name
            session.herd = herd
            session.sourcePasture = sourcePasture

            for animal in animals.sorted(by: Self.animalTagOrder) {
                try Self.collect(
                    animal,
                    into: session,
                    from: sourcePasture,
                    herd: herd,
                    lookup: lookup,
                    in: context
                )
            }

            return session.id
        }
    }

    func collectAnimals(
        sessionID: UUID,
        animalIDs: [UUID]
    ) async throws {
        let animalIDs = Self.uniqueIDs(animalIDs)
        guard !animalIDs.isEmpty else {
            return
        }
        let lookup = self.lookup

        try await performWrite { context, herd in
            guard let session = try lookup.herdOwned(
                CDWorkingSession.self,
                id: sessionID,
                herdID: herd.id,
                in: context
            ) else {
                throw WorkingRepositoryError.sessionNotFound
            }
            guard let status = WorkingSessionStatus(rawValue: session.statusRawValue) else {
                throw CoreDataWorkingMappingError.invalidSessionStatus(
                    sessionID: session.id,
                    value: session.statusRawValue
                )
            }
            guard status == .active else {
                throw WorkingRepositoryError.sessionAlreadyFinished
            }
            guard let sourcePasture = session.sourcePasture else {
                throw WorkingRepositoryError.pastureNotFound
            }
            guard sourcePasture.herd.id == herd.id,
                  sourcePasture.id == session.sourcePastureIDSnapshot else {
                throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                    relationship: "WorkingSession.sourcePasture",
                    expectedID: session.sourcePastureIDSnapshot,
                    actualID: sourcePasture.id
                )
            }

            let animals = try CoreDataAnimalMutation.fetchAnimals(
                ids: animalIDs,
                herd: herd,
                in: context
            )
            guard animals.count == animalIDs.count else {
                throw WorkingRepositoryError.animalNotFound
            }

            let existingAnimalIDs = Set(
                ((session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? [])
                    .map(\.animalIDSnapshot)
            )
            let candidates = animals.map {
                WorkingCollectionCandidate(
                    animalID: $0.id,
                    activeSessionID: $0.activeWorkingSession?.id
                )
            }
            try WorkingCollectionRules.validateCollection(
                existingAnimalIDs: existingAnimalIDs,
                candidates: candidates,
                sessionID: session.id
            )

            guard try animals.allSatisfy({
                try Self.isEligibleForCollection($0, sourcePasture: sourcePasture)
            }) else {
                throw WorkingRepositoryError.animalNotEligibleForCollection
            }

            for animal in animals.sorted(by: Self.animalTagOrder) {
                try Self.collect(
                    animal,
                    into: session,
                    from: sourcePasture,
                    herd: herd,
                    lookup: lookup,
                    in: context
                )
            }
        }
    }

    private func performWrite<Result: Sendable>(
        _ operation: @escaping @Sendable (
            NSManagedObjectContext,
            CDHerd
        ) throws -> Result
    ) async throws -> Result {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let gate = workingWriteGate
        await gate.acquire()
        await animalWriteBoundary.beginAnimalWrite()

        do {
            try pastureResidentWriteCoordinator.beginWorkingWrite()
        } catch {
            animalWriteBoundary.endAnimalWrite()
            await gate.release()
            throw error
        }

        let lookup = self.lookup
        let animalWriteBoundary = self.animalWriteBoundary
        do {
            let result = try await transactionExecutor.performWrite(
                afterTransaction: {
                    animalWriteBoundary.endAnimalWrite()
                }
            ) { context in
                guard let herd = try lookup.herd(id: herdID, in: context) else {
                    throw HerdRepositoryError.missingHerd
                }
                return try operation(context, herd)
            }
            pastureResidentWriteCoordinator.endWorkingWrite()
            await gate.release()
            return result
        } catch {
            pastureResidentWriteCoordinator.endWorkingWrite()
            await gate.release()
            throw error
        }
    }

    private func makeReadScope() throws -> (NSManagedObjectContext, UUID) {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        return (contextFactory.makeReadContext(), herdID)
    }

    private nonisolated func validateSessionGraph(
        _ session: CDWorkingSession,
        herdID: UUID
    ) throws {
        try validateHerdOwnership(
            relationship: "WorkingSession.herd",
            expectedHerdID: herdID,
            actualHerdID: session.herd.id
        )

        if let sourcePasture = session.sourcePasture {
            try validateHerdOwnership(
                relationship: "WorkingSession.sourcePasture",
                expectedHerdID: herdID,
                actualHerdID: sourcePasture.herd.id
            )
            try validateSnapshotRelationship(
                relationship: "WorkingSession.sourcePasture",
                expectedID: session.sourcePastureIDSnapshot,
                actualID: sourcePasture.id
            )
        }

        let queueItems = (session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? []
        let treatmentRecords = (session.treatmentRecords?.allObjects as? [CDWorkingTreatmentRecord]) ?? []
        let healthRecords = (session.healthRecords?.allObjects as? [CDHealthRecord]) ?? []
        let pregnancyChecks = (session.pregnancyChecks?.allObjects as? [CDPregnancyCheck]) ?? []
        let activeAnimals = (session.activeAnimals?.allObjects as? [CDAnimal]) ?? []

        try CoreDataAnimalMutation.validateUniqueApplicationIDs(queueItems, herdID: herdID)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(treatmentRecords, herdID: herdID)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(healthRecords, herdID: herdID)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(pregnancyChecks, herdID: herdID)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(activeAnimals, herdID: herdID)

        for item in queueItems {
            try validateHerdOwnership(
                relationship: "WorkingSession.queueItems",
                expectedHerdID: herdID,
                actualHerdID: item.herd.id
            )
            try validateSessionRelationship(
                relationship: "WorkingQueueItem.session",
                expectedSessionID: session.id,
                actualSessionID: item.session.id
            )

            if let animal = item.animal {
                try validateHerdOwnership(
                    relationship: "WorkingQueueItem.animal",
                    expectedHerdID: herdID,
                    actualHerdID: animal.herd.id
                )
                try validateSnapshotRelationship(
                    relationship: "WorkingQueueItem.animal",
                    expectedID: item.animalIDSnapshot,
                    actualID: animal.id
                )
            }
            if let collectedFromPasture = item.collectedFromPasture {
                try validateHerdOwnership(
                    relationship: "WorkingQueueItem.collectedFromPasture",
                    expectedHerdID: herdID,
                    actualHerdID: collectedFromPasture.herd.id
                )
                try validateSnapshotRelationship(
                    relationship: "WorkingQueueItem.collectedFromPasture",
                    expectedID: item.collectedFromPastureIDSnapshot,
                    actualID: collectedFromPasture.id
                )
            }
            if let destinationPasture = item.destinationPasture {
                try validateHerdOwnership(
                    relationship: "WorkingQueueItem.destinationPasture",
                    expectedHerdID: herdID,
                    actualHerdID: destinationPasture.herd.id
                )
                try validateSnapshotRelationship(
                    relationship: "WorkingQueueItem.destinationPasture",
                    expectedID: item.destinationPastureIDSnapshot,
                    actualID: destinationPasture.id
                )
            }
        }

        for record in treatmentRecords {
            try validateHerdOwnership(
                relationship: "WorkingSession.treatmentRecords",
                expectedHerdID: herdID,
                actualHerdID: record.herd.id
            )
            try validateSessionRelationship(
                relationship: "WorkingTreatmentRecord.session",
                expectedSessionID: session.id,
                actualSessionID: record.session.id
            )
            if let animal = record.animal {
                try validateHerdOwnership(
                    relationship: "WorkingTreatmentRecord.animal",
                    expectedHerdID: herdID,
                    actualHerdID: animal.herd.id
                )
                try validateSnapshotRelationship(
                    relationship: "WorkingTreatmentRecord.animal",
                    expectedID: record.animalIDSnapshot,
                    actualID: animal.id
                )
            }
        }

        for record in healthRecords {
            try validateHerdOwnership(
                relationship: "WorkingSession.healthRecords",
                expectedHerdID: herdID,
                actualHerdID: record.herd.id
            )
            try validateSessionRelationship(
                relationship: "HealthRecord.workingSession",
                expectedSessionID: session.id,
                actualSessionID: record.workingSession?.id
            )
            try validateHerdOwnership(
                relationship: "HealthRecord.animal",
                expectedHerdID: herdID,
                actualHerdID: record.animal.herd.id
            )
        }

        for check in pregnancyChecks {
            try validateHerdOwnership(
                relationship: "WorkingSession.pregnancyChecks",
                expectedHerdID: herdID,
                actualHerdID: check.herd.id
            )
            try validateSessionRelationship(
                relationship: "PregnancyCheck.workingSession",
                expectedSessionID: session.id,
                actualSessionID: check.workingSession?.id
            )
            try validateHerdOwnership(
                relationship: "PregnancyCheck.animal",
                expectedHerdID: herdID,
                actualHerdID: check.animal.herd.id
            )
            if let sire = check.sire {
                try validateHerdOwnership(
                    relationship: "PregnancyCheck.sire",
                    expectedHerdID: herdID,
                    actualHerdID: sire.herd.id
                )
            }
        }

        for animal in activeAnimals {
            try validateHerdOwnership(
                relationship: "WorkingSession.activeAnimals",
                expectedHerdID: herdID,
                actualHerdID: animal.herd.id
            )
            try validateSessionRelationship(
                relationship: "Animal.activeWorkingSession",
                expectedSessionID: session.id,
                actualSessionID: animal.activeWorkingSession?.id
            )
        }
    }

    private nonisolated func validateHerdOwnership(
        relationship: String,
        expectedHerdID: UUID,
        actualHerdID: UUID
    ) throws {
        guard actualHerdID == expectedHerdID else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: relationship,
                expectedHerdID: expectedHerdID,
                actualHerdID: actualHerdID
            )
        }
    }

    private nonisolated func validateSessionRelationship(
        relationship: String,
        expectedSessionID: UUID,
        actualSessionID: UUID?
    ) throws {
        guard actualSessionID == expectedSessionID else {
            throw CoreDataWorkingRepositoryError.invalidSessionRelationship(
                relationship: relationship,
                expectedSessionID: expectedSessionID,
                actualSessionID: actualSessionID
            )
        }
    }

    private nonisolated func validateSnapshotRelationship(
        relationship: String,
        expectedID: UUID?,
        actualID: UUID?
    ) throws {
        guard actualID == expectedID else {
            throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                relationship: relationship,
                expectedID: expectedID,
                actualID: actualID
            )
        }
    }
}

private extension CoreDataWorkingRepository {
    nonisolated static func activeQueueTarget(
        sessionID: UUID,
        queueItemID: UUID,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> (
        session: CDWorkingSession,
        queueItem: CDWorkingQueueItem,
        animal: CDAnimal?
    ) {
        guard let session = try lookup.herdOwned(
            CDWorkingSession.self,
            id: sessionID,
            herdID: herd.id,
            in: context
        ) else {
            throw WorkingRepositoryError.sessionNotFound
        }
        guard let status = WorkingSessionStatus(rawValue: session.statusRawValue) else {
            throw CoreDataWorkingMappingError.invalidSessionStatus(
                sessionID: session.id,
                value: session.statusRawValue
            )
        }
        guard status == .active else {
            throw WorkingRepositoryError.sessionAlreadyFinished
        }

        guard let queueItem = try lookup.herdOwned(
            CDWorkingQueueItem.self,
            id: queueItemID,
            herdID: herd.id,
            in: context
        ), queueItem.session.id == session.id else {
            throw WorkingRepositoryError.queueItemNotFound
        }

        guard queueItem.animal?.id == queueItem.animalIDSnapshot || queueItem.animal == nil else {
            throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                relationship: "WorkingQueueItem.animal",
                expectedID: queueItem.animalIDSnapshot,
                actualID: queueItem.animal?.id
            )
        }

        if let animal = queueItem.animal, animal.herd.id != herd.id {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.animal",
                expectedHerdID: herd.id,
                actualHerdID: animal.herd.id
            )
        }

        return (session, queueItem, queueItem.animal)
    }

    nonisolated static func uniqueIDs(_ ids: [UUID]) -> [UUID] {
        ids.reduce(into: [UUID]()) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }
    }

    nonisolated static func animalsForSessionStart(
        requestedIDs: [UUID]?,
        sourcePasture: CDPasture,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDAnimal] {
        if let requestedIDs {
            let animals = try CoreDataAnimalMutation.fetchAnimals(
                ids: requestedIDs,
                herd: herd,
                in: context
            )
            guard animals.count == requestedIDs.count else {
                throw WorkingRepositoryError.animalNotFound
            }
            return animals
        }

        let animals = try CoreDataAnimalMutation.fetchAnimals(
            herd: herd,
            in: context
        )
        let eligible = try animals.filter {
            try isEligibleForCollection($0, sourcePasture: sourcePasture)
        }
        guard !eligible.isEmpty else {
            throw WorkingRepositoryError.noEligibleAnimals
        }
        return eligible
    }

    nonisolated static func validateStartAnimals(
        _ animals: [CDAnimal],
        sourcePasture: CDPasture
    ) throws {
        if animals.contains(where: { $0.activeWorkingSession != nil }) {
            throw WorkingRepositoryError.animalAlreadyInAnotherSession
        }

        guard try animals.allSatisfy({
            try isEligibleForCollection($0, sourcePasture: sourcePasture)
        }) else {
            throw WorkingRepositoryError.animalNotEligibleForCollection
        }
    }

    nonisolated static func isEligibleForCollection(
        _ animal: CDAnimal,
        sourcePasture: CDPasture
    ) throws -> Bool {
        try CoreDataAnimalProjection.status(animal) == .active
            && !animal.isArchived
            && animal.currentPasture?.id == sourcePasture.id
            && animal.activeWorkingSession == nil
    }

    nonisolated static func collect(
        _ animal: CDAnimal,
        into session: CDWorkingSession,
        from sourcePasture: CDPasture,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws {
        guard animal.herd.id == herd.id else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.animal",
                expectedHerdID: herd.id,
                actualHerdID: animal.herd.id
            )
        }
        guard sourcePasture.herd.id == herd.id else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.collectedFromPasture",
                expectedHerdID: herd.id,
                actualHerdID: sourcePasture.herd.id
            )
        }
        guard session.herd.id == herd.id else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.session",
                expectedHerdID: herd.id,
                actualHerdID: session.herd.id
            )
        }

        let primary = CoreDataAnimalProjection.primaryTagFields(
            CoreDataAnimalProjection.managedTags(animal)
        )
        let damPrimary = animal.dam.map {
            CoreDataAnimalProjection.primaryTagFields(
                CoreDataAnimalProjection.managedTags($0)
            )
        }
        if let dam = animal.dam, dam.herd.id != herd.id {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.animal.dam",
                expectedHerdID: herd.id,
                actualHerdID: dam.herd.id
            )
        }

        let item = CDWorkingQueueItem(context: context)
        item.id = try CoreDataAnimalMutation.uniqueID(
            for: CDWorkingQueueItem.self,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )
        item.statusRawValue = WorkingQueueStatus.queued.rawValue
        item.completedAt = nil
        item.animalIDSnapshot = animal.id
        item.animalTagNumberSnapshot = primary.number
        item.animalTagColorIDSnapshot = primary.colorID
        item.animalNameSnapshot = animal.name
        item.animalSexRawValueSnapshot = try CoreDataAnimalProjection.sex(animal).rawValue
        item.animalDamDisplayTagNumberSnapshot = animal.dam == nil ? nil : damPrimary?.number
        item.animalDamDisplayTagColorIDSnapshot = damPrimary?.colorID
        item.collectedFromPastureIDSnapshot = sourcePasture.id
        item.collectedFromPastureNameSnapshot = sourcePasture.name
        item.destinationPastureIDSnapshot = nil
        item.destinationPastureNameSnapshot = nil
        item.herd = herd
        item.session = session
        item.animal = animal
        item.collectedFromPasture = sourcePasture
        item.destinationPasture = nil

        animal.currentPasture = nil
        animal.activeWorkingSession = session
        CoreDataAnimalMutation.rotateRevision(animal)
    }

    nonisolated static func animalTagOrder(
        _ lhs: CDAnimal,
        _ rhs: CDAnimal
    ) -> Bool {
        let lhsTag = CoreDataAnimalProjection.primaryTagFields(
            CoreDataAnimalProjection.managedTags(lhs)
        ).number
        let rhsTag = CoreDataAnimalProjection.primaryTagFields(
            CoreDataAnimalProjection.managedTags(rhs)
        ).number
        let comparison = lhsTag.localizedStandardCompare(rhsTag)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

