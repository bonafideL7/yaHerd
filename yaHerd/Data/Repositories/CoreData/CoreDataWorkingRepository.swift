@preconcurrency import CoreData
import Foundation

enum CoreDataWorkingRepositoryError: Error, Equatable {
    case invalidOwnership(
        relationship: String,
        expectedHerdID: UUID,
        actualHerdID: UUID
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
                .map(WorkingMapper.makeSessionSummary)
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
        guard session.herd.id == herdID else {
            throw CoreDataWorkingRepositoryError.invalidOwnership(
                relationship: "WorkingSession.herd",
                expectedHerdID: herdID,
                actualHerdID: session.herd.id
            )
        }

        let queueItems = (session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? []
        let treatmentRecords = (session.treatmentRecords?.allObjects as? [CDWorkingTreatmentRecord]) ?? []
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(queueItems, herdID: herdID)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(treatmentRecords, herdID: herdID)

        for item in queueItems {
            guard item.herd.id == herdID, item.session.id == session.id else {
                throw CoreDataWorkingRepositoryError.invalidOwnership(
                    relationship: "WorkingSession.queueItems",
                    expectedHerdID: herdID,
                    actualHerdID: item.herd.id
                )
            }
        }

        for record in treatmentRecords {
            guard record.herd.id == herdID, record.session.id == session.id else {
                throw CoreDataWorkingRepositoryError.invalidOwnership(
                    relationship: "WorkingSession.treatmentRecords",
                    expectedHerdID: herdID,
                    actualHerdID: record.herd.id
                )
            }
        }
    }
}
