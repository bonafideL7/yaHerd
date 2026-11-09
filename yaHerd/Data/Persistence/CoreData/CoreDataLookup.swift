@preconcurrency import CoreData
import Foundation

protocol CoreDataEntityNamed {
    static var coreDataEntityName: String { get }
}

protocol CoreDataApplicationIdentifiedManagedObject: CoreDataEntityNamed where Self: NSManagedObject {
    var id: UUID? { get }
}

extension CoreDataApplicationIdentifiedManagedObject {
    func requiredID() throws -> UUID {
        guard let id else {
            throw CoreDataPersistenceError.missingApplicationID(entity: Self.coreDataEntityName)
        }
        return id
    }
}

// Herd ownership is declared in the Core Data model. Its stored relationship may be
// temporarily nil while CloudKit imports related records.
protocol CoreDataHerdOwnedManagedObject: CoreDataApplicationIdentifiedManagedObject {
    var herd: CDHerd? { get }
}

struct CoreDataLookup: Sendable {
    func herd(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> CDHerd? {
        let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 2

        let matches = try context.fetch(request)
        guard matches.count <= 1 else {
            throw CoreDataPersistenceError.duplicateApplicationID(
                entity: CDHerd.coreDataEntityName,
                id: id,
                herdID: nil
            )
        }
        return matches.first
    }

    /// The persisted Herd root, not the currently selected UI, determines which
    /// store owns its records. A missing or ambiguous root cannot select a store.
    func store(
        forHerdID id: UUID,
        in context: NSManagedObjectContext
    ) throws -> NSPersistentStore? {
        guard let herd = try herd(id: id, in: context) else {
            return nil
        }
        return try owningStore(of: herd, in: context)
    }

    func scope<Result: NSFetchRequestResult>(
        _ request: NSFetchRequest<Result>,
        toHerd herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws {
        if !herd.isInserted {
            request.affectedStores = [try owningStore(of: herd, in: context)]
        }
    }

    /// Validate the complete pending transaction against its selected Herd
    /// before assigning inserted objects to that Herd's persistent store.
    func prepareForSave(
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        guard let herd = try herd(id: herdID, in: context) else {
            throw HerdRepositoryError.missingHerd
        }
        let destination = try owningStore(of: herd, in: context)
        let changedObjects = context.insertedObjects
            .union(context.updatedObjects)
            .union(context.deletedObjects)

        func validateOwnership(_ object: NSManagedObject) throws {
            let entity = object.entity.name ?? String(describing: type(of: object))
            let owningHerdID: NSManagedObjectID?
            if let root = object as? CDHerd {
                owningHerdID = root.objectID
            } else if let owned = object as? any CoreDataHerdOwnedManagedObject {
                if let currentHerd = owned.herd {
                    owningHerdID = currentHerd.objectID
                } else if object.isDeleted,
                          let previousHerd = object.committedValues(
                              forKeys: ["herd"]
                          )["herd"] as? CDHerd {
                    owningHerdID = previousHerd.objectID
                } else {
                    owningHerdID = nil
                }
            } else {
                owningHerdID = nil
            }
            guard owningHerdID == herd.objectID else {
                throw CoreDataPersistenceError.wrongHerdMutation(
                    entity: entity, herdID: herdID
                )
            }
            if !object.isInserted,
               changedObjects.contains(object),
               object is any CoreDataHerdOwnedManagedObject {
                let committedHerd = object.committedValues(
                    forKeys: ["herd"]
                )["herd"] as? CDHerd
                guard committedHerd?.objectID == herd.objectID else {
                    throw CoreDataPersistenceError.wrongHerdMutation(
                        entity: entity, herdID: herdID
                    )
                }
            }
            if let assignedStore = object.objectID.persistentStore {
                guard assignedStore === destination else {
                    throw CoreDataPersistenceError.wrongStoreMutation(
                        entity: entity, herdID: herdID
                    )
                }
            } else if !object.isInserted {
                throw CoreDataPersistenceError.wrongStoreMutation(
                    entity: entity, herdID: herdID
                )
            }
        }

        for object in changedObjects {
            try validateOwnership(object)
            // A child can have the correct Herd relationship but still refer to
            // an animal, pasture, group, or session owned by another Herd.
            // Inspect to-one links only; walking to-many inverse collections
            // would fault entire Herd graphs during common single-row saves.
            for relationship in object.entity.relationshipsByName.values
            where !relationship.isToMany {
                if let relatedObject = object.value(forKey: relationship.name) as? NSManagedObject {
                    try validateOwnership(relatedObject)
                }
            }
        }

        for object in context.insertedObjects {
            context.assign(object, to: destination)
        }
    }

    private func owningStore(
        of herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> NSPersistentStore {
        let herdID = try herd.requiredID()
        guard !herd.objectID.isTemporaryID,
              let coordinator = context.persistentStoreCoordinator,
              let store = herd.objectID.persistentStore,
              coordinator.persistentStores.contains(where: { $0 === store }) else {
            throw CoreDataPersistenceError.unresolvedHerdStore(id: herdID)
        }
        return store
    }

    func herdOwned<Object>(
        _ type: Object.Type,
        id: UUID,
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws -> Object?
    where Object: NSManagedObject & CoreDataHerdOwnedManagedObject {
        guard let herd = try herd(id: herdID, in: context) else {
            return nil
        }

        let request = NSFetchRequest<Object>(entityName: Object.coreDataEntityName)
        request.predicate = NSPredicate(
            format: "id == %@ AND herd == %@",
            id as NSUUID,
            herd
        )
        request.fetchLimit = 2
        try scope(request, toHerd: herd, in: context)

        let matches = try context.fetch(request)
        guard matches.count <= 1 else {
            throw CoreDataPersistenceError.duplicateApplicationID(
                entity: Object.coreDataEntityName,
                id: id,
                herdID: herdID
            )
        }
        return matches.first
    }
}

extension CDHerd: CoreDataEntityNamed {
    static let coreDataEntityName = "Herd"
}

extension CDTagColorDefinition: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "TagColorDefinition"
}

extension CDAnimalStatusReference: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "AnimalStatusReference"
}

extension CDPastureGroup: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "PastureGroup"
}

extension CDPasture: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "Pasture"
}

extension CDAnimal: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "Animal"
}

extension CDAnimalTag: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "AnimalTag"
}

extension CDMovementRecord: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "MovementRecord"
}

extension CDStatusRecord: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "StatusRecord"
}

extension CDHealthRecord: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "HealthRecord"
}

extension CDPregnancyCheck: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "PregnancyCheck"
}

extension CDFieldCheckSession: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "FieldCheckSession"
}

extension CDFieldCheckAnimalCheck: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "FieldCheckAnimalCheck"
}

extension CDFieldCheckFinding: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "FieldCheckFinding"
}

extension CDWorkingTreatmentTemplate: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "WorkingTreatmentTemplate"
}

extension CDWorkingSession: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "WorkingSession"
}

extension CDWorkingQueueItem: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "WorkingQueueItem"
}

extension CDWorkingTreatmentRecord: CoreDataHerdOwnedManagedObject {
    static let coreDataEntityName = "WorkingTreatmentRecord"
}
