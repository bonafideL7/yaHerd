@preconcurrency import CoreData
import Foundation

enum CoreDataWorkingLifecycleMutation {
    struct CompletionEntry {
        let queueItem: CDWorkingQueueItem
        let destination: CDPasture
    }

    static func completionPlan(
        session: CDWorkingSession,
        assignments: [WorkingQueueDestinationAssignment],
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> [CompletionEntry] {
        try validateSessionOwnership(session, herd: herd)

        let queueItems = managedQueueItems(session)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            queueItems,
            herdID: herd.id
        )

        var destinationsByQueueItemID: [UUID: UUID?] = [:]
        for assignment in assignments {
            guard !destinationsByQueueItemID.keys.contains(assignment.queueItemID) else {
                throw WorkingRepositoryError.duplicateQueueItemAssignments
            }
            destinationsByQueueItemID[assignment.queueItemID] = assignment.destinationPastureID
        }

        let queueItemIDs = Set(queueItems.map(\.id))
        guard Set(destinationsByQueueItemID.keys) == queueItemIDs else {
            throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
        }

        return try queueItems.map { item in
            try validateQueueOwnership(item, session: session, herd: herd)

            guard let assignedDestination = destinationsByQueueItemID[item.id] else {
                throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
            }

            let destination: CDPasture
            if let destinationID = assignedDestination {
                guard let persisted = try lookup.herdOwned(
                    CDPasture.self,
                    id: destinationID,
                    herdID: herd.id,
                    in: context
                ) else {
                    throw WorkingRepositoryError.pastureNotFound
                }
                destination = persisted
            } else {
                guard let sourcePasture = session.sourcePasture else {
                    throw WorkingRepositoryError.pastureNotFound
                }
                try validatePastureRelationship(
                    sourcePasture,
                    expectedID: session.sourcePastureIDSnapshot,
                    relationship: "WorkingSession.sourcePasture",
                    herd: herd
                )
                destination = sourcePasture
            }

            if let animal = item.animal {
                try validateAnimalRelationship(
                    animal,
                    item: item,
                    session: session,
                    herd: herd
                )
            }

            return CompletionEntry(
                queueItem: item,
                destination: destination
            )
        }
    }

    static func applyCompletion(
        _ plan: [CompletionEntry],
        session: CDWorkingSession,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext,
        at date: Date
    ) throws {
        for entry in plan {
            let item = entry.queueItem
            let destination = entry.destination

            item.destinationPasture = destination
            item.destinationPastureIDSnapshot = destination.id
            item.destinationPastureNameSnapshot = destination.name

            guard let animal = item.animal else {
                continue
            }

            let isOwnedBySession = animal.activeWorkingSession?.id == session.id
            let sourceID: UUID?
            let sourceName: String?

            if isOwnedBySession {
                sourceID = item.collectedFromPastureIDSnapshot
                sourceName = item.collectedFromPastureNameSnapshot
                    ?? session.sourcePastureNameSnapshot
            } else {
                sourceID = animal.currentPasture?.id
                sourceName = animal.currentPasture?.name
            }

            let shouldMove = isOwnedBySession
                || animal.currentPasture?.id != destination.id
                || animal.activeWorkingSession != nil

            guard shouldMove else {
                continue
            }

            let movement = CDMovementRecord(context: context)
            movement.id = try CoreDataAnimalMutation.uniqueID(
                for: CDMovementRecord.self,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            movement.date = date
            movement.fromPastureIDSnapshot = sourceID
            movement.fromPastureNameSnapshot = sourceName
            movement.toPastureIDSnapshot = destination.id
            movement.toPastureNameSnapshot = destination.name
            movement.herd = herd
            movement.animal = animal

            animal.currentPasture = destination
            animal.activeWorkingSession = nil
            CoreDataAnimalMutation.rotateRevision(animal)
        }

        session.statusRawValue = WorkingSessionStatus.finished.rawValue
    }

    static func restoreOwnedAnimalsBeforeDeleting(
        session: CDWorkingSession,
        herd: CDHerd
    ) throws {
        try validateSessionOwnership(session, herd: herd)

        let queueItems = managedQueueItems(session)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            queueItems,
            herdID: herd.id
        )

        for item in queueItems {
            try validateQueueOwnership(item, session: session, herd: herd)
            guard let animal = item.animal else {
                continue
            }

            guard animal.herd.id == herd.id else {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "WorkingQueueItem.animal",
                    expectedHerdID: herd.id,
                    actualHerdID: animal.herd.id
                )
            }
            guard animal.id == item.animalIDSnapshot else {
                throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                    relationship: "WorkingQueueItem.animal",
                    expectedID: item.animalIDSnapshot,
                    actualID: animal.id
                )
            }

            if let currentPasture = animal.currentPasture,
               currentPasture.herd.id != herd.id {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "Animal.currentPasture",
                    expectedHerdID: herd.id,
                    actualHerdID: currentPasture.herd.id
                )
            }

            guard let activeSession = animal.activeWorkingSession else {
                continue
            }
            guard activeSession.herd.id == herd.id else {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "Animal.activeWorkingSession",
                    expectedHerdID: herd.id,
                    actualHerdID: activeSession.herd.id
                )
            }
            guard activeSession.id == session.id else {
                continue
            }

            let destination = try restorationPasture(
                item: item,
                session: session,
                herd: herd
            )
            animal.currentPasture = destination
            animal.activeWorkingSession = nil
            CoreDataAnimalMutation.rotateRevision(animal)
        }
    }

    private static func restorationPasture(
        item: CDWorkingQueueItem,
        session: CDWorkingSession,
        herd: CDHerd
    ) throws -> CDPasture? {
        if let collectedFrom = item.collectedFromPasture {
            try validatePastureRelationship(
                collectedFrom,
                expectedID: item.collectedFromPastureIDSnapshot,
                relationship: "WorkingQueueItem.collectedFromPasture",
                herd: herd
            )
            return collectedFrom
        }

        if let sourcePasture = session.sourcePasture {
            try validatePastureRelationship(
                sourcePasture,
                expectedID: session.sourcePastureIDSnapshot,
                relationship: "WorkingSession.sourcePasture",
                herd: herd
            )
            return sourcePasture
        }

        return nil
    }

    private static func validateSessionOwnership(
        _ session: CDWorkingSession,
        herd: CDHerd
    ) throws {
        guard session.herd.id == herd.id else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingSession.herd",
                expectedHerdID: herd.id,
                actualHerdID: session.herd.id
            )
        }

        if let sourcePasture = session.sourcePasture {
            try validatePastureRelationship(
                sourcePasture,
                expectedID: session.sourcePastureIDSnapshot,
                relationship: "WorkingSession.sourcePasture",
                herd: herd
            )
        }
    }

    private static func validateQueueOwnership(
        _ item: CDWorkingQueueItem,
        session: CDWorkingSession,
        herd: CDHerd
    ) throws {
        guard item.herd.id == herd.id else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingSession.queueItems",
                expectedHerdID: herd.id,
                actualHerdID: item.herd.id
            )
        }
        guard item.session.id == session.id else {
            throw CoreDataWorkingRepositoryError.invalidSessionRelationship(
                relationship: "WorkingQueueItem.session",
                expectedSessionID: session.id,
                actualSessionID: item.session.id
            )
        }

        if let collectedFrom = item.collectedFromPasture {
            try validatePastureRelationship(
                collectedFrom,
                expectedID: item.collectedFromPastureIDSnapshot,
                relationship: "WorkingQueueItem.collectedFromPasture",
                herd: herd
            )
        }
        if let destination = item.destinationPasture {
            try validatePastureRelationship(
                destination,
                expectedID: item.destinationPastureIDSnapshot,
                relationship: "WorkingQueueItem.destinationPasture",
                herd: herd
            )
        }
    }

    private static func validateAnimalRelationship(
        _ animal: CDAnimal,
        item: CDWorkingQueueItem,
        session: CDWorkingSession,
        herd: CDHerd
    ) throws {
        guard animal.herd.id == herd.id else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.animal",
                expectedHerdID: herd.id,
                actualHerdID: animal.herd.id
            )
        }
        guard animal.id == item.animalIDSnapshot else {
            throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                relationship: "WorkingQueueItem.animal",
                expectedID: item.animalIDSnapshot,
                actualID: animal.id
            )
        }

        if let currentPasture = animal.currentPasture,
           currentPasture.herd.id != herd.id {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "Animal.currentPasture",
                expectedHerdID: herd.id,
                actualHerdID: currentPasture.herd.id
            )
        }

        if let activeSession = animal.activeWorkingSession {
            guard activeSession.herd.id == herd.id else {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "Animal.activeWorkingSession",
                    expectedHerdID: herd.id,
                    actualHerdID: activeSession.herd.id
                )
            }
            guard activeSession.id == session.id else {
                throw WorkingRepositoryError.animalAlreadyInAnotherSession
            }
        }
    }

    private static func validatePastureRelationship(
        _ pasture: CDPasture,
        expectedID: UUID?,
        relationship: String,
        herd: CDHerd
    ) throws {
        guard pasture.herd.id == herd.id else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: relationship,
                expectedHerdID: herd.id,
                actualHerdID: pasture.herd.id
            )
        }
        guard pasture.id == expectedID else {
            throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                relationship: relationship,
                expectedID: expectedID,
                actualID: pasture.id
            )
        }
    }

    private static func managedQueueItems(
        _ session: CDWorkingSession
    ) -> [CDWorkingQueueItem] {
        (session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? []
    }
}
