@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataPastureDeletionTransactionWriter: PastureDeletionTransactionWriting {
    private let selection: any CurrentHerdSelectionReading
    private let transactionExecutor: CoreDataTransactionExecutor
    private let residentWriteCoordinator: CoreDataPastureResidentWriteCoordinator
    private nonisolated let lookup: CoreDataLookup

    private(set) var lastExecutedOperations: [PastureDeletionOperation] = []

    init(
        selection: any CurrentHerdSelectionReading,
        transactionExecutor: CoreDataTransactionExecutor,
        residentWriteCoordinator: CoreDataPastureResidentWriteCoordinator,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.transactionExecutor = transactionExecutor
        self.residentWriteCoordinator = residentWriteCoordinator
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            transactionExecutor: assembly.transactionExecutor,
            residentWriteCoordinator: assembly.pastureResidentWriteCoordinator,
            lookup: assembly.lookup
        )
    }

    func deletePastures(_ plan: DeletePasturesTransactionPlan) async throws {
        try await deletePastures(plan, beforeSave: nil)
    }

    func deletePastures(
        _ plan: DeletePasturesTransactionPlan,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let normalized = try Self.validate(plan)
        let lookup = self.lookup
        let mutationDate = Date()

        lastExecutedOperations = []
        await residentWriteCoordinator.acquirePastureDeletion()
        do {
            let executed = try await transactionExecutor.performWrite(beforeSave: beforeSave) { context in
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            try Self.revalidateExpectedStates(
                normalized.expectedStates,
                herd: herd,
                lookup: lookup,
                in: context
            )

            var executed: [PastureDeletionOperation] = []
            for operation in normalized.operations {
                switch operation {
                case let .moveAnimals(animalIDs, fromPastureID, toPastureID):
                    try Self.moveAnimals(
                        animalIDs,
                        fromPastureID: fromPastureID,
                        toPastureID: toPastureID,
                        herd: herd,
                        lookup: lookup,
                        in: context,
                        at: mutationDate
                    )

                case let .archiveFieldChecks(pastureIDs, archivedAt):
                    try Self.archiveFieldChecks(
                        pastureIDs: pastureIDs,
                        archivedAt: archivedAt,
                        herd: herd,
                        in: context
                    )

                case let .deletePastures(ids):
                    try Self.deletePastures(
                        ids: ids,
                        herd: herd,
                        lookup: lookup,
                        in: context
                    )
                }
                executed.append(operation)
            }
            return executed
            }

            lastExecutedOperations = executed
            residentWriteCoordinator.releasePastureDeletion()
        } catch {
            residentWriteCoordinator.releasePastureDeletion()
            throw error
        }
    }

    private nonisolated struct ValidatedPlan: Sendable {
        let expectedStates: [PastureDeletionExpectedState]
        let operations: [PastureDeletionOperation]
    }

    private nonisolated static func validate(
        _ plan: DeletePasturesTransactionPlan
    ) throws -> ValidatedPlan {
        let expectedIDs = plan.expectedStates.map(\.pastureID)
        guard !expectedIDs.isEmpty,
              Set(expectedIDs).count == expectedIDs.count else {
            throw PastureDeletionTransactionError.invalidPlan
        }

        let targetIDs = Set(expectedIDs)
        var moveIDsBySource: [UUID: Set<UUID>] = [:]
        var archivedIDs: Set<UUID>?
        var deleteIDs: Set<UUID>?
        var sawArchive = false
        var sawDelete = false

        for operation in plan.operations {
            switch operation {
            case let .moveAnimals(animalIDs, fromPastureID, toPastureID):
                guard !sawArchive,
                      !sawDelete,
                      targetIDs.contains(fromPastureID),
                      !animalIDs.isEmpty,
                      Set(animalIDs).count == animalIDs.count,
                      toPastureID.map({ !targetIDs.contains($0) }) ?? true else {
                    throw PastureDeletionTransactionError.invalidPlan
                }
                let moveIDs = Set(animalIDs)
                guard moveIDsBySource[fromPastureID, default: []].isDisjoint(with: moveIDs) else {
                    throw PastureDeletionTransactionError.invalidPlan
                }
                moveIDsBySource[fromPastureID, default: []].formUnion(moveIDs)

            case let .archiveFieldChecks(pastureIDs, _):
                guard !sawArchive,
                      !sawDelete,
                      Set(pastureIDs).count == pastureIDs.count,
                      Set(pastureIDs) == targetIDs else {
                    throw PastureDeletionTransactionError.invalidPlan
                }
                sawArchive = true
                archivedIDs = Set(pastureIDs)

            case let .deletePastures(ids):
                guard sawArchive,
                      !sawDelete,
                      Set(ids).count == ids.count,
                      Set(ids) == targetIDs else {
                    throw PastureDeletionTransactionError.invalidPlan
                }
                sawDelete = true
                deleteIDs = Set(ids)
            }
        }

        guard archivedIDs == targetIDs,
              deleteIDs == targetIDs,
              plan.operations.last.map({
                  if case .deletePastures = $0 { return true }
                  return false
              }) == true else {
            throw PastureDeletionTransactionError.invalidPlan
        }

        for expected in plan.expectedStates {
            guard moveIDsBySource[expected.pastureID, default: []] == expected.residentAnimalIDs else {
                throw PastureDeletionTransactionError.invalidPlan
            }
        }

        return ValidatedPlan(
            expectedStates: plan.expectedStates,
            operations: plan.operations
        )
    }

    private nonisolated static func revalidateExpectedStates(
        _ expectedStates: [PastureDeletionExpectedState],
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws {
        for expected in expectedStates {
            guard let pasture = try lookup.herdOwned(
                CDPasture.self,
                id: expected.pastureID,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureDeletionTransactionError.pastureMissing(
                    pastureID: expected.pastureID
                )
            }

            let request = NSFetchRequest<CDAnimal>(entityName: CDAnimal.coreDataEntityName)
            request.predicate = NSPredicate(
                format: "herd == %@ AND currentPasture == %@ AND isArchived == NO AND statusRawValue == %@",
                herd,
                pasture,
                AnimalStatus.active.rawValue
            )
            let residents = try context.fetch(request)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(
                residents,
                herdID: herd.id
            )
            guard Set(residents.map(\.id)) == expected.residentAnimalIDs else {
                throw PastureDeletionTransactionError.residentSetChanged(
                    pastureID: expected.pastureID
                )
            }
        }
    }

    private nonisolated static func moveAnimals(
        _ animalIDs: [UUID],
        fromPastureID: UUID,
        toPastureID: UUID?,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext,
        at date: Date
    ) throws {
        let destination: CDPasture?
        if let toPastureID {
            guard let resolved = try lookup.herdOwned(
                CDPasture.self,
                id: toPastureID,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureDeletionTransactionError.destinationPastureMissing(
                    pastureID: toPastureID
                )
            }
            destination = resolved
        } else {
            destination = nil
        }

        for animalID in animalIDs {
            guard let animal = try lookup.herdOwned(
                CDAnimal.self,
                id: animalID,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureDeletionTransactionError.animalMissing(animalID: animalID)
            }
            guard animal.currentPasture?.id == fromPastureID else {
                throw PastureDeletionTransactionError.animalSourceChanged(
                    animalID: animalID,
                    expectedPastureID: fromPastureID
                )
            }

            try CoreDataAnimalMutation.move(
                animal,
                to: destination,
                herd: herd,
                in: context,
                at: date
            )
            CoreDataAnimalMutation.rotateRevision(animal)
        }
    }

    private nonisolated static func archiveFieldChecks(
        pastureIDs: [UUID],
        archivedAt: Date,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws {
        guard !pastureIDs.isEmpty else { return }

        let request = NSFetchRequest<CDFieldCheckSession>(
            entityName: CDFieldCheckSession.coreDataEntityName
        )
        request.predicate = NSPredicate(
            format: "herd == %@ AND pastureIDSnapshot IN %@",
            herd,
            pastureIDs
        )
        for session in try context.fetch(request) {
            session.pastureArchivedAt = archivedAt
        }
    }

    private nonisolated static func deletePastures(
        ids: [UUID],
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws {
        let targetIDs = Set(ids)
        var pasturesByID: [UUID: CDPasture] = [:]
        for id in ids {
            guard let pasture = try lookup.herdOwned(
                CDPasture.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw PastureDeletionTransactionError.pastureMissing(pastureID: id)
            }
            pasturesByID[id] = pasture
        }

        let survivorRequest = NSFetchRequest<CDAnimal>(entityName: CDAnimal.coreDataEntityName)
        survivorRequest.predicate = NSPredicate(
            format: "herd == %@ AND currentPasture.id IN %@",
            herd,
            ids
        )
        let survivors = try context.fetch(survivorRequest)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            survivors,
            herdID: herd.id
        )
        for animal in survivors {
            guard let currentID = animal.currentPasture?.id,
                  targetIDs.contains(currentID) else {
                continue
            }
            if !animal.isArchived,
               AnimalStatus(rawValue: animal.statusRawValue) == .active {
                throw PastureDeletionTransactionError.residentSetChanged(
                    pastureID: currentID
                )
            }
            animal.currentPasture = nil
            CoreDataAnimalMutation.rotateRevision(animal)
        }

        for id in ids {
            if let pasture = pasturesByID[id] {
                context.delete(pasture)
            }
        }
    }
}
