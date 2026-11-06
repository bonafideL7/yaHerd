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
            herdID: (try herd.requiredID())
        )

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

        let queueItemIDs = Set(try queueItems.map { try $0.requiredID() })
        guard Set(destinationsByQueueItemID.keys) == queueItemIDs else {
            throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
        }

        return try queueItems.map { item in
            try validateQueueOwnership(item, session: session, herd: herd)

            guard let assignedDestination = destinationsByQueueItemID[try item.requiredID()] else {
                throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
            }

            let destination: CDPasture
            if let destinationID = assignedDestination {
                guard let persisted = try lookup.herdOwned(
                    CDPasture.self,
                    id: destinationID,
                    herdID: (try herd.requiredID()),
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
            let destinationName = try destination.validatedName()

            item.destinationPasture = destination
            item.destinationPastureIDSnapshot = (try destination.requiredID())
            item.destinationPastureNameSnapshot = destinationName

            guard let animal = item.animal else {
                continue
            }

            let isOwnedBySession = animal.activeWorkingSession?.id == (try session.requiredID())
            let sourceID: UUID?
            let sourceName: String?

            if isOwnedBySession {
                sourceID = item.collectedFromPastureIDSnapshot
                sourceName = item.collectedFromPastureNameSnapshot
                    ?? session.sourcePastureNameSnapshot
            } else {
                sourceID = try animal.currentPasture.map { try $0.requiredID() }
                sourceName = try animal.currentPasture.map { try $0.validatedName() }
            }

            let shouldMove = try isOwnedBySession
                || sourceID != destination.requiredID()
                || animal.activeWorkingSession != nil

            guard shouldMove else {
                continue
            }

            let movement = CDMovementRecord(context: context)
            movement.id = try CoreDataAnimalMutation.uniqueID(
                for: CDMovementRecord.self,
                herdID: (try herd.requiredID()),
                lookup: lookup,
                in: context
            )
            movement.date = date
            movement.fromPastureIDSnapshot = sourceID
            movement.fromPastureNameSnapshot = sourceName
            movement.toPastureIDSnapshot = (try destination.requiredID())
            movement.toPastureNameSnapshot = destinationName
            movement.herd = herd
            movement.animal = animal

            animal.currentPasture = destination
            animal.activeWorkingSession = nil
            try CoreDataAnimalMutation.rotateRevision(animal)
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
            herdID: (try herd.requiredID())
        )

        for item in queueItems {
            try validateQueueOwnership(item, session: session, herd: herd)
            guard let animal = item.animal else {
                continue
            }

            guard animal.herd?.id == (try herd.requiredID()) else {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "WorkingQueueItem.animal",
                    expectedHerdID: (try herd.requiredID()),
                    actualHerdID: animal.herd?.id
                )
            }
            guard animal.id == item.animalIDSnapshot else {
                throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                    relationship: "WorkingQueueItem.animal",
                    expectedID: item.animalIDSnapshot,
                    actualID: (try animal.requiredID())
                )
            }

            if let currentPasture = animal.currentPasture,
               currentPasture.herd?.id != (try herd.requiredID()) {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "Animal.currentPasture",
                    expectedHerdID: (try herd.requiredID()),
                    actualHerdID: currentPasture.herd?.id
                )
            }

            guard let activeSession = animal.activeWorkingSession else {
                continue
            }
            guard activeSession.herd?.id == (try herd.requiredID()) else {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "Animal.activeWorkingSession",
                    expectedHerdID: (try herd.requiredID()),
                    actualHerdID: activeSession.herd?.id
                )
            }
            guard activeSession.objectID == session.objectID else {
                continue
            }

            let destination = try restorationPasture(
                item: item,
                session: session,
                herd: herd
            )
            animal.currentPasture = destination
            animal.activeWorkingSession = nil
            try CoreDataAnimalMutation.rotateRevision(animal)
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
        _ = try WorkingMapper.sessionDate(session)
        guard session.herd?.id == (try herd.requiredID()) else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingSession.herd",
                expectedHerdID: (try herd.requiredID()),
                actualHerdID: session.herd?.id
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
        _ = try WorkingMapper.queueAnimalID(from: item)
        guard item.herd?.id == (try herd.requiredID()) else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingSession.queueItems",
                expectedHerdID: (try herd.requiredID()),
                actualHerdID: item.herd?.id
            )
        }
        guard let owningSession = item.session else {
            throw CoreDataWorkingRepositoryError.missingQueueSession(queueItemID: (try item.requiredID()))
        }
        guard owningSession.herd?.id == (try herd.requiredID()) else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.session",
                expectedHerdID: (try herd.requiredID()),
                actualHerdID: owningSession.herd?.id
            )
        }
        guard owningSession.objectID == session.objectID else {
            throw CoreDataWorkingRepositoryError.invalidSessionRelationship(
                relationship: "WorkingQueueItem.session",
                expectedSessionID: (try session.requiredID()),
                actualSessionID: (try owningSession.requiredID())
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
        guard animal.herd?.id == (try herd.requiredID()) else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "WorkingQueueItem.animal",
                expectedHerdID: (try herd.requiredID()),
                actualHerdID: animal.herd?.id
            )
        }
        guard animal.id == item.animalIDSnapshot else {
            throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                relationship: "WorkingQueueItem.animal",
                expectedID: item.animalIDSnapshot,
                actualID: (try animal.requiredID())
            )
        }

        if let currentPasture = animal.currentPasture,
           currentPasture.herd?.id != (try herd.requiredID()) {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: "Animal.currentPasture",
                expectedHerdID: (try herd.requiredID()),
                actualHerdID: currentPasture.herd?.id
            )
        }

        if let activeSession = animal.activeWorkingSession {
            guard activeSession.herd?.id == (try herd.requiredID()) else {
                throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                    relationship: "Animal.activeWorkingSession",
                    expectedHerdID: (try herd.requiredID()),
                    actualHerdID: activeSession.herd?.id
                )
            }
            guard activeSession.objectID == session.objectID else {
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
        guard pasture.herd?.id == (try herd.requiredID()) else {
            throw CoreDataWorkingRepositoryError.invalidHerdOwnership(
                relationship: relationship,
                expectedHerdID: (try herd.requiredID()),
                actualHerdID: pasture.herd?.id
            )
        }
        guard pasture.id == expectedID else {
            throw CoreDataWorkingRepositoryError.invalidSnapshotRelationship(
                relationship: relationship,
                expectedID: expectedID,
                actualID: (try pasture.requiredID())
            )
        }
    }

    private static func managedQueueItems(
        _ session: CDWorkingSession
    ) -> [CDWorkingQueueItem] {
        (session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? []
    }
}
