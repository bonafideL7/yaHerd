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

        let pastureGroupEntity = makeEntity(
            name: SharedPastureGroupRecord.entityName,
            managedObjectClass: SharedPastureGroupRecord.self,
            properties: [
                makeAttribute(name: "publicID", type: .stringAttributeType),
                makeAttribute(name: "herdPublicID", type: .stringAttributeType),
                makeAttribute(name: "name", type: .stringAttributeType),
                makeAttribute(name: "grazeDays", type: .integer64AttributeType),
                makeAttribute(name: "restDays", type: .integer64AttributeType),
                makeAttribute(name: "lastMirroredAt", type: .dateAttributeType)
            ]
        )

        let pastureEntity = makeEntity(
            name: SharedPastureRecord.entityName,
            managedObjectClass: SharedPastureRecord.self,
            properties: [
                makeAttribute(name: "publicID", type: .stringAttributeType),
                makeAttribute(name: "herdPublicID", type: .stringAttributeType),
                makeAttribute(name: "name", type: .stringAttributeType),
                makeAttribute(name: "sortOrder", type: .integer64AttributeType),
                makeAttribute(name: "acreage", type: .doubleAttributeType),
                makeAttribute(name: "usableAcreage", type: .doubleAttributeType),
                makeAttribute(name: "targetAcresPerHead", type: .doubleAttributeType),
                makeAttribute(name: "lastGrazedDate", type: .dateAttributeType),
                makeAttribute(name: "groupPublicID", type: .stringAttributeType),
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

        let movementEntity = makeEntity(
            name: SharedMovementRecord.entityName,
            managedObjectClass: SharedMovementRecord.self,
            properties: [
                makeAttribute(name: "publicID", type: .stringAttributeType),
                makeAttribute(name: "herdPublicID", type: .stringAttributeType),
                makeAttribute(name: "animalPublicID", type: .stringAttributeType),
                makeAttribute(name: "date", type: .dateAttributeType),
                makeAttribute(name: "fromPasture", type: .stringAttributeType),
                makeAttribute(name: "toPasture", type: .stringAttributeType),
                makeAttribute(name: "lastMirroredAt", type: .dateAttributeType)
            ]
        )

        let statusRecordEntity = makeEntity(
            name: SharedStatusRecord.entityName,
            managedObjectClass: SharedStatusRecord.self,
            properties: [
                makeAttribute(name: "publicID", type: .stringAttributeType),
                makeAttribute(name: "herdPublicID", type: .stringAttributeType),
                makeAttribute(name: "animalPublicID", type: .stringAttributeType),
                makeAttribute(name: "date", type: .dateAttributeType),
                makeAttribute(name: "oldStatusRawValue", type: .stringAttributeType),
                makeAttribute(name: "newStatusRawValue", type: .stringAttributeType),
                makeAttribute(name: "oldStatusReferenceID", type: .stringAttributeType),
                makeAttribute(name: "newStatusReferenceID", type: .stringAttributeType),
                makeAttribute(name: "lastMirroredAt", type: .dateAttributeType)
            ]
        )

        addToManyRelationship(
            name: "pastureGroups",
            from: herdEntity,
            to: pastureGroupEntity,
            inverseName: "herd",
            deleteRule: .cascadeDeleteRule
        )

        addToManyRelationship(
            name: "pastures",
            from: herdEntity,
            to: pastureEntity,
            inverseName: "herd",
            deleteRule: .cascadeDeleteRule
        )

        addToManyRelationship(
            name: "pastures",
            from: pastureGroupEntity,
            to: pastureEntity,
            inverseName: "group",
            deleteRule: .nullifyDeleteRule
        )

        addToManyRelationship(
            name: "animals",
            from: herdEntity,
            to: animalEntity,
            inverseName: "herd",
            deleteRule: .cascadeDeleteRule
        )

        addToManyRelationship(
            name: "movements",
            from: herdEntity,
            to: movementEntity,
            inverseName: "herd",
            deleteRule: .cascadeDeleteRule
        )

        addToManyRelationship(
            name: "statusRecords",
            from: herdEntity,
            to: statusRecordEntity,
            inverseName: "herd",
            deleteRule: .cascadeDeleteRule
        )

        addToManyRelationship(
            name: "movements",
            from: animalEntity,
            to: movementEntity,
            inverseName: "animal",
            deleteRule: .cascadeDeleteRule
        )

        addToManyRelationship(
            name: "statusRecords",
            from: animalEntity,
            to: statusRecordEntity,
            inverseName: "animal",
            deleteRule: .cascadeDeleteRule
        )

        model.entities = [
            herdEntity,
            pastureGroupEntity,
            pastureEntity,
            animalEntity,
            movementEntity,
            statusRecordEntity
        ]
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

    private static func addToManyRelationship(
        name: String,
        from sourceEntity: NSEntityDescription,
        to destinationEntity: NSEntityDescription,
        inverseName: String,
        deleteRule: NSDeleteRule
    ) {
        let toMany = NSRelationshipDescription()
        toMany.name = name
        toMany.destinationEntity = destinationEntity
        toMany.minCount = 0
        toMany.maxCount = 0
        toMany.deleteRule = deleteRule
        toMany.isOptional = true

        let toOne = NSRelationshipDescription()
        toOne.name = inverseName
        toOne.destinationEntity = sourceEntity
        toOne.minCount = 0
        toOne.maxCount = 1
        toOne.deleteRule = .nullifyDeleteRule
        toOne.isOptional = true

        toMany.inverseRelationship = toOne
        toOne.inverseRelationship = toMany

        sourceEntity.properties.append(toMany)
        destinationEntity.properties.append(toOne)
    }
}
