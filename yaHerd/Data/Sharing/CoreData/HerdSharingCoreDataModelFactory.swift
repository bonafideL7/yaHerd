//
//  HerdSharingCoreDataModelFactory.swift
//  yaHerd
//

import CoreData

/// Builds the isolated Core Data model used only by the CloudKit sharing bridge.
/// SwiftData remains yaHerd's app data store.
enum HerdSharingCoreDataModelFactory {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let herdEntity = makeEntity(
            name: SharedHerdRecord.entityName,
            managedObjectClass: SharedHerdRecord.self,
            properties: [
                makeAttribute(name: "publicID", type: .stringAttributeType),
                makeAttribute(name: "name", type: .stringAttributeType),
                makeAttribute(name: "createdAt", type: .dateAttributeType),
                makeAttribute(name: "updatedAt", type: .dateAttributeType),
                makeAttribute(name: "schemaVersion", type: .integer64AttributeType),
                makeAttribute(name: "lastMirroredAt", type: .dateAttributeType)
            ]
        )

        let animalEntity = makeEntity(
            name: SharedAnimalRecord.entityName,
            managedObjectClass: SharedAnimalRecord.self,
            properties: [
                makeAttribute(name: "publicID", type: .stringAttributeType),
                makeAttribute(name: "herdPublicID", type: .stringAttributeType),
                makeAttribute(name: "name", type: .stringAttributeType),
                makeAttribute(name: "tagNumber", type: .stringAttributeType),
                makeAttribute(name: "tagColorID", type: .stringAttributeType),
                makeAttribute(name: "sexRawValue", type: .stringAttributeType),
                makeAttribute(name: "birthDate", type: .dateAttributeType),
                makeAttribute(name: "statusRawValue", type: .stringAttributeType),
                makeAttribute(name: "saleDate", type: .dateAttributeType),
                makeAttribute(name: "salePrice", type: .doubleAttributeType),
                makeAttribute(name: "reasonSold", type: .stringAttributeType),
                makeAttribute(name: "deathDate", type: .dateAttributeType),
                makeAttribute(name: "causeOfDeath", type: .stringAttributeType),
                makeAttribute(name: "statusReferenceID", type: .stringAttributeType),
                makeAttribute(name: "isSoftDeleted", type: .booleanAttributeType),
                makeAttribute(name: "softDeletedAt", type: .dateAttributeType),
                makeAttribute(name: "softDeleteReason", type: .stringAttributeType),
                makeAttribute(name: "locationRawValue", type: .stringAttributeType),
                makeAttribute(name: "pasturePublicID", type: .stringAttributeType),
                makeAttribute(name: "sireAnimalPublicID", type: .stringAttributeType),
                makeAttribute(name: "damAnimalPublicID", type: .stringAttributeType),
                makeAttribute(name: "distinguishingFeaturesJSON", type: .binaryDataAttributeType),
                makeAttribute(name: "lastMirroredAt", type: .dateAttributeType)
            ]
        )

        let herdAnimals = NSRelationshipDescription()
        herdAnimals.name = "animals"
        herdAnimals.destinationEntity = animalEntity
        herdAnimals.minCount = 0
        herdAnimals.maxCount = 0
        herdAnimals.deleteRule = .cascadeDeleteRule
        herdAnimals.isOptional = true

        let animalHerd = NSRelationshipDescription()
        animalHerd.name = "herd"
        animalHerd.destinationEntity = herdEntity
        animalHerd.minCount = 0
        animalHerd.maxCount = 1
        animalHerd.deleteRule = .nullifyDeleteRule
        animalHerd.isOptional = true

        herdAnimals.inverseRelationship = animalHerd
        animalHerd.inverseRelationship = herdAnimals

        herdEntity.properties.append(herdAnimals)
        animalEntity.properties.append(animalHerd)

        model.entities = [herdEntity, animalEntity]
        return model
    }

    private static func makeEntity(
        name: String,
        managedObjectClass: NSManagedObject.Type,
        properties: [NSPropertyDescription]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(managedObjectClass)
        entity.properties = properties
        return entity
    }

    private static func makeAttribute(
        name: String,
        type: NSAttributeType
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }
}
