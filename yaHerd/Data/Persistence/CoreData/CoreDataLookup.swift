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
    static let expectedHerdRootKey = "yaHerd.expectedHerdRoot"

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
        if let root = matches.first,
           let expected = context.userInfo[Self.expectedHerdRootKey] as? URL,
           root.objectID.uriRepresentation() != expected {
            // The UUID was reused in a different store or by a replacement
            // root. Never redirect an existing context to that Herd.
            throw CoreDataPersistenceError.unresolvedHerdStore(id: id)
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
        if herd.isInserted {
            // Core Data has not assigned a permanent store identity to this
            // Herd yet. In a two-store context, an unrestricted fetch can read
            // private and shared records before the new Herd has an owner.
            // Keep the existing single-store creation path functional.
            guard let stores = context.persistentStoreCoordinator?.persistentStores,
                  stores.count == 1,
                  let store = stores.first else {
                throw CoreDataPersistenceError.unresolvedHerdStore(
                    id: try herd.requiredID()
                )
            }
            request.affectedStores = [store]
            return
        }
        request.affectedStores = [try owningStore(of: herd, in: context)]
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

        // Core Data may propagate additional deletions or nullifications during
        // save. Check the committed graph, including to-one inverse links.
        // Follow cascade edges recursively, but do not traverse nullify targets.
        var visitedDeletions = Set<NSManagedObject>()
        func validateDeletionEffects(_ object: NSManagedObject) throws {
            guard visitedDeletions.insert(object).inserted else { return }
            try validateOwnership(object)

            for relationship in object.entity.relationshipsByName.values
            where relationship.deleteRule == .cascadeDeleteRule
                || relationship.deleteRule == .nullifyDeleteRule {
                let committed = object.committedValues(
                    forKeys: [relationship.name]
                )[relationship.name]
                let related: [NSManagedObject]
                if relationship.isToMany {
                    related = (committed as? NSSet)?.allObjects.compactMap {
                        $0 as? NSManagedObject
                    } ?? []
                } else {
                    related = (committed as? NSManagedObject).map { [$0] } ?? []
                }

                for target in related {
                    try validateOwnership(target)
                    if relationship.deleteRule == .cascadeDeleteRule {
                        try validateDeletionEffects(target)
                    }
                }
            }
        }

        for object in changedObjects {
            try validateOwnership(object)
            // Ordinary writes inspect to-one links without faulting every
            // to-many inverse in the Herd.
            for relationship in object.entity.relationshipsByName.values
            where !relationship.isToMany {
                if let relatedObject = object.value(forKey: relationship.name) as? NSManagedObject {
                    try validateOwnership(relatedObject)
                }
            }
            if object.isDeleted {
                try validateDeletionEffects(object)
            }
        }

        for object in context.insertedObjects {
            context.assign(object, to: destination)
        }
    }

    /// Complete current Herd graph, including all direct Herd-owned entities.
    /// Validate both inverse collections and other relationships before native
    /// sharing's deep traversal. A corrupt relationship cannot expand a share.
    func objectsForSharing(root: CDHerd, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let store = try owningStore(of: root, in: context)
        var objects: [NSManagedObject] = [root]
        for relationship in root.entity.relationshipsByName.values {
            guard relationship.isToMany,
                  let entityName = relationship.destinationEntity?.name,
                  relationship.inverseRelationship?.name == "herd" else {
                throw CoreDataHerdSharingError.invalidGraph
            }
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [store]
            request.predicate = NSPredicate(format: "herd == %@", root)
            objects.append(contentsOf: try context.fetch(request))
        }

        // A new modeled Herd-owned entity must also participate in the
        // root's graph. Fail closed if the model no longer has that inverse.
        let modeledOwnedEntities = Set(
            context.persistentStoreCoordinator?.managedObjectModel.entities.compactMap { entity in
                entity.relationshipsByName["herd"]?.destinationEntity === root.entity ? entity.name : nil
            } ?? []
        )
        let linkedEntities = Set(root.entity.relationshipsByName.values.compactMap { $0.destinationEntity?.name })
        guard modeledOwnedEntities == linkedEntities else {
            throw CoreDataHerdSharingError.invalidGraph
        }

        let ids = Set(objects.map(\.objectID))
        guard ids.count == objects.count else { throw CoreDataHerdSharingError.invalidGraph }
        for object in objects {
            guard !object.objectID.isTemporaryID, object.objectID.persistentStore === store,
                  !object.isDeleted, !object.isInserted else {
                throw CoreDataHerdSharingError.invalidGraph
            }
            if object !== root {
                guard let owned = object as? any CoreDataHerdOwnedManagedObject,
                      owned.herd?.objectID == root.objectID, owned.id != nil else {
                    throw CoreDataHerdSharingError.invalidGraph
                }
            }
            for relationship in object.entity.relationshipsByName.values {
                let value = object.value(forKey: relationship.name)
                let related: [NSManagedObject]
                if relationship.isToMany {
                    related = (value as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
                } else {
                    related = (value as? NSManagedObject).map { [$0] } ?? []
                }
                guard related.allSatisfy({ ids.contains($0.objectID) }) else {
                    throw CoreDataHerdSharingError.invalidGraph
                }
            }
        }
        return objects
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
