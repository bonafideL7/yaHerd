@preconcurrency import CoreData

/// Local saves must preserve the application-required fields while the CloudKit
/// schema permits temporarily incomplete records during remote imports.
enum CoreDataLocalWriteIntegrity {
    private static let requiredProperties: [String: [String]]? = {
        let bundle = Bundle(for: CDHerd.self)
        guard let modelDirectory = bundle.url(
            forResource: CoreDataPersistentContainer.modelName,
            withExtension: "momd"
        ), let legacyModel = NSManagedObjectModel(
            contentsOf: modelDirectory.appendingPathComponent("yaHerdModelV1.mom")
        ) else {
            return nil
        }

        var result: [String: [String]] = [:]
        for entity in legacyModel.entities {
            guard let name = entity.name else { return nil }
            let attributes = entity.attributesByName.values
                .filter { !$0.isOptional }
                .map(\.name)
            let relationships = entity.relationshipsByName.values
                .filter { !$0.isOptional && !$0.isToMany }
                .map(\.name)
            result[name] = (attributes + relationships).sorted()
        }
        return result
    }()

    static func validateChangedObjects(in context: NSManagedObjectContext) throws {
        guard let requiredProperties else {
            throw CoreDataPersistenceError.modelNotFound(name: "yaHerdModelV1")
        }

        for object in context.insertedObjects.union(context.updatedObjects) where !object.isDeleted {
            guard let entityName = object.entity.name,
                  let propertyNames = requiredProperties[entityName]
            else {
                throw CoreDataPersistenceError.modelNotFound(
                    name: object.entity.name ?? "Unknown"
                )
            }

            for propertyName in propertyNames where object.value(forKey: propertyName) == nil {
                throw CoreDataPersistenceError.missingRequiredPersistedValue(
                    entity: entityName,
                    property: propertyName
                )
            }
        }
    }
}
