@preconcurrency import CoreData
import Foundation

protocol CoreDataEntityNamed {
    static var coreDataEntityName: String { get }
}

protocol CoreDataApplicationIdentifiedManagedObject: CoreDataEntityNamed where Self: NSManagedObject {
    var id: UUID { get }
}

protocol CoreDataHerdOwnedManagedObject: CoreDataApplicationIdentifiedManagedObject {
    var herd: CDHerd { get }
}

struct CoreDataLookup {
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

extension CDHerd: CoreDataApplicationIdentifiedManagedObject {
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
