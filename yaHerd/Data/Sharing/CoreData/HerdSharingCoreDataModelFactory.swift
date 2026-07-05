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
        let herdEntity = NSEntityDescription()
        herdEntity.name = SharedHerdRecord.entityName
        herdEntity.managedObjectClassName = NSStringFromClass(SharedHerdRecord.self)
        herdEntity.properties = [
            makeAttribute(name: "publicID", type: .stringAttributeType),
            makeAttribute(name: "name", type: .stringAttributeType),
            makeAttribute(name: "createdAt", type: .dateAttributeType),
            makeAttribute(name: "updatedAt", type: .dateAttributeType),
            makeAttribute(name: "schemaVersion", type: .integer64AttributeType),
            makeAttribute(name: "lastMirroredAt", type: .dateAttributeType)
        ]
        model.entities = [herdEntity]
        return model
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
