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
}

@MainActor
final class CoreDataWorkingRepository:
    WorkingSessionListReader,
    WorkingSessionDetailReader,
    WorkingQueueItemEditorReader
{
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private nonisolated let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup
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
            }
            if let collectedFromPasture = item.collectedFromPasture {
                try validateHerdOwnership(
                    relationship: "WorkingQueueItem.collectedFromPasture",
                    expectedHerdID: herdID,
                    actualHerdID: collectedFromPasture.herd.id
                )
            }
            if let destinationPasture = item.destinationPasture {
                try validateHerdOwnership(
                    relationship: "WorkingQueueItem.destinationPasture",
                    expectedHerdID: herdID,
                    actualHerdID: destinationPasture.herd.id
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
}
