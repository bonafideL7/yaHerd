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
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let tagColorDefinitionEntity = makeEntity(
      name: SharedTagColorDefinitionRecord.entityName,
      managedObjectClass: SharedTagColorDefinitionRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "name", type: .stringAttributeType),
        makeAttribute(name: "prefix", type: .stringAttributeType),
        makeAttribute(name: "red", type: .doubleAttributeType),
        makeAttribute(name: "green", type: .doubleAttributeType),
        makeAttribute(name: "blue", type: .doubleAttributeType),
        makeAttribute(name: "alpha", type: .doubleAttributeType),
        makeAttribute(name: "sortOrder", type: .integer64AttributeType),
        makeAttribute(name: "isHidden", type: .booleanAttributeType),
        makeAttribute(name: "isDefault", type: .booleanAttributeType),
        makeAttribute(name: "createdAt", type: .dateAttributeType),
        makeAttribute(name: "updatedAt", type: .dateAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let statusReferenceEntity = makeEntity(
      name: SharedAnimalStatusReferenceRecord.entityName,
      managedObjectClass: SharedAnimalStatusReferenceRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "name", type: .stringAttributeType),
        makeAttribute(name: "baseStatusRawValue", type: .stringAttributeType),
        makeAttribute(name: "createdAt", type: .dateAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
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
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
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
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
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
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let animalTagEntity = makeEntity(
      name: SharedAnimalTagRecord.entityName,
      managedObjectClass: SharedAnimalTagRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalPublicID", type: .stringAttributeType),
        makeAttribute(name: "number", type: .stringAttributeType),
        makeAttribute(name: "colorID", type: .stringAttributeType),
        makeAttribute(name: "isPrimary", type: .booleanAttributeType),
        makeAttribute(name: "isActive", type: .booleanAttributeType),
        makeAttribute(name: "assignedAt", type: .dateAttributeType),
        makeAttribute(name: "removedAt", type: .dateAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
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
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
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
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let healthRecordEntity = makeEntity(
      name: SharedHealthRecord.entityName,
      managedObjectClass: SharedHealthRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalPublicID", type: .stringAttributeType),
        makeAttribute(name: "date", type: .dateAttributeType),
        makeAttribute(name: "treatment", type: .stringAttributeType),
        makeAttribute(name: "notes", type: .stringAttributeType),
        makeAttribute(name: "workingSessionPublicID", type: .stringAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let pregnancyCheckEntity = makeEntity(
      name: SharedPregnancyCheckRecord.entityName,
      managedObjectClass: SharedPregnancyCheckRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalPublicID", type: .stringAttributeType),
        makeAttribute(name: "date", type: .dateAttributeType),
        makeAttribute(name: "resultRawValue", type: .stringAttributeType),
        makeAttribute(name: "technician", type: .stringAttributeType),
        makeAttribute(name: "estimatedDaysPregnant", type: .integer64AttributeType),
        makeAttribute(name: "dueDate", type: .dateAttributeType),
        makeAttribute(name: "sireAnimalPublicID", type: .stringAttributeType),
        makeAttribute(name: "workingSessionPublicID", type: .stringAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let workingProtocolTemplateEntity = makeEntity(
      name: SharedWorkingProtocolTemplateRecord.entityName,
      managedObjectClass: SharedWorkingProtocolTemplateRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "name", type: .stringAttributeType),
        makeAttribute(name: "itemsJSON", type: .binaryDataAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let workingSessionEntity = makeEntity(
      name: SharedWorkingSessionRecord.entityName,
      managedObjectClass: SharedWorkingSessionRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "date", type: .dateAttributeType),
        makeAttribute(name: "statusRawValue", type: .stringAttributeType),
        makeAttribute(name: "sourcePasturePublicID", type: .stringAttributeType),
        makeAttribute(name: "protocolName", type: .stringAttributeType),
        makeAttribute(name: "protocolItemsJSON", type: .binaryDataAttributeType),
        makeAttribute(name: "currentQueueIndex", type: .integer64AttributeType),
        makeAttribute(name: "notes", type: .stringAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let workingQueueItemEntity = makeEntity(
      name: SharedWorkingQueueItemRecord.entityName,
      managedObjectClass: SharedWorkingQueueItemRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "sessionPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalPublicID", type: .stringAttributeType),
        makeAttribute(name: "queueOrder", type: .integer64AttributeType),
        makeAttribute(name: "statusRawValue", type: .stringAttributeType),
        makeAttribute(name: "completedAt", type: .dateAttributeType),
        makeAttribute(name: "collectedFromPasturePublicID", type: .stringAttributeType),
        makeAttribute(name: "destinationPasturePublicID", type: .stringAttributeType),
        makeAttribute(name: "workNotes", type: .stringAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let workingTreatmentRecordEntity = makeEntity(
      name: SharedWorkingTreatmentRecord.entityName,
      managedObjectClass: SharedWorkingTreatmentRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "sessionPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalPublicID", type: .stringAttributeType),
        makeAttribute(name: "date", type: .dateAttributeType),
        makeAttribute(name: "itemName", type: .stringAttributeType),
        makeAttribute(name: "given", type: .booleanAttributeType),
        makeAttribute(name: "quantity", type: .doubleAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let fieldCheckSessionEntity = makeEntity(
      name: SharedFieldCheckSessionRecord.entityName,
      managedObjectClass: SharedFieldCheckSessionRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "startedAt", type: .dateAttributeType),
        makeAttribute(name: "completedAt", type: .dateAttributeType),
        makeAttribute(name: "notes", type: .stringAttributeType),
        makeAttribute(name: "expectedHeadCountSnapshot", type: .integer64AttributeType),
        makeAttribute(name: "quickCowCount", type: .integer64AttributeType),
        makeAttribute(name: "quickHeiferCount", type: .integer64AttributeType),
        makeAttribute(name: "quickCalfCount", type: .integer64AttributeType),
        makeAttribute(name: "quickBullCount", type: .integer64AttributeType),
        makeAttribute(name: "quickSteerCount", type: .integer64AttributeType),
        makeAttribute(name: "pastureNameSnapshot", type: .stringAttributeType),
        makeAttribute(name: "pastureArchivedAt", type: .dateAttributeType),
        makeAttribute(name: "pasturePublicID", type: .stringAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let fieldCheckAnimalCheckEntity = makeEntity(
      name: SharedFieldCheckAnimalCheckRecord.entityName,
      managedObjectClass: SharedFieldCheckAnimalCheckRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "sessionPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalIDSnapshot", type: .stringAttributeType),
        makeAttribute(name: "rosterTagNumber", type: .stringAttributeType),
        makeAttribute(name: "rosterTagColorID", type: .stringAttributeType),
        makeAttribute(name: "damRosterTagNumber", type: .stringAttributeType),
        makeAttribute(name: "damRosterTagColorID", type: .stringAttributeType),
        makeAttribute(name: "animalName", type: .stringAttributeType),
        makeAttribute(name: "animalSexRawValue", type: .stringAttributeType),
        makeAttribute(name: "animalTypeRawValue", type: .stringAttributeType),
        makeAttribute(name: "wasExpectedAtStart", type: .booleanAttributeType),
        makeAttribute(name: "countedAt", type: .dateAttributeType),
        makeAttribute(name: "missingConfirmedAt", type: .dateAttributeType),
        makeAttribute(name: "note", type: .stringAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    let fieldCheckFindingEntity = makeEntity(
      name: SharedFieldCheckFindingRecord.entityName,
      managedObjectClass: SharedFieldCheckFindingRecord.self,
      properties: [
        makeAttribute(name: "publicID", type: .stringAttributeType),
        makeAttribute(name: "herdPublicID", type: .stringAttributeType),
        makeAttribute(name: "sessionPublicID", type: .stringAttributeType),
        makeAttribute(name: "animalPublicID", type: .stringAttributeType),
        makeAttribute(name: "recordedAt", type: .dateAttributeType),
        makeAttribute(name: "typeRawValue", type: .stringAttributeType),
        makeAttribute(name: "severityRawValue", type: .stringAttributeType),
        makeAttribute(name: "statusRawValue", type: .stringAttributeType),
        makeAttribute(name: "note", type: .stringAttributeType),
        makeAttribute(name: "animalIDSnapshot", type: .stringAttributeType),
        makeAttribute(name: "animalDisplayTagNumberSnapshot", type: .stringAttributeType),
        makeAttribute(name: "animalDisplayTagColorIDSnapshot", type: .stringAttributeType),
        makeAttribute(name: "animalNameSnapshot", type: .stringAttributeType),
        makeAttribute(name: "pastureNameSnapshot", type: .stringAttributeType),
        makeAttribute(name: "sessionIDSnapshot", type: .stringAttributeType),
        makeAttribute(name: "lastMirroredAt", type: .dateAttributeType),
      ]
    )

    addToManyRelationship(
      name: "tagColorDefinitions", from: herdEntity, to: tagColorDefinitionEntity,
      inverseName: "herd", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "statusReferences", from: herdEntity, to: statusReferenceEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "animalTags", from: herdEntity, to: animalTagEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "pastureGroups", from: herdEntity, to: pastureGroupEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "pastures", from: herdEntity, to: pastureEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "pastures", from: pastureGroupEntity, to: pastureEntity, inverseName: "group",
      deleteRule: .nullifyDeleteRule)
    addToManyRelationship(
      name: "animals", from: herdEntity, to: animalEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "animalTags", from: animalEntity, to: animalTagEntity, inverseName: "animal",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "movements", from: herdEntity, to: movementEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "statusRecords", from: herdEntity, to: statusRecordEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "movements", from: animalEntity, to: movementEntity, inverseName: "animal",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "statusRecords", from: animalEntity, to: statusRecordEntity, inverseName: "animal",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "healthRecords", from: herdEntity, to: healthRecordEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "pregnancyChecks", from: herdEntity, to: pregnancyCheckEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "healthRecords", from: animalEntity, to: healthRecordEntity, inverseName: "animal",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "pregnancyChecks", from: animalEntity, to: pregnancyCheckEntity, inverseName: "animal",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "workingProtocolTemplates", from: herdEntity, to: workingProtocolTemplateEntity,
      inverseName: "herd", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "workingSessions", from: herdEntity, to: workingSessionEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "workingQueueItems", from: herdEntity, to: workingQueueItemEntity, inverseName: "herd",
      deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "workingTreatmentRecords", from: herdEntity, to: workingTreatmentRecordEntity,
      inverseName: "herd", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "queueItems", from: workingSessionEntity, to: workingQueueItemEntity,
      inverseName: "session", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "treatmentRecords", from: workingSessionEntity, to: workingTreatmentRecordEntity,
      inverseName: "session", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "workingQueueItems", from: animalEntity, to: workingQueueItemEntity,
      inverseName: "animal", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "workingTreatmentRecords", from: animalEntity, to: workingTreatmentRecordEntity,
      inverseName: "animal", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "fieldCheckSessions", from: herdEntity, to: fieldCheckSessionEntity,
      inverseName: "herd", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "fieldCheckAnimalChecks", from: herdEntity, to: fieldCheckAnimalCheckEntity,
      inverseName: "herd", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "fieldCheckFindings", from: herdEntity, to: fieldCheckFindingEntity,
      inverseName: "herd", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "animalChecks", from: fieldCheckSessionEntity, to: fieldCheckAnimalCheckEntity,
      inverseName: "session", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "findings", from: fieldCheckSessionEntity, to: fieldCheckFindingEntity,
      inverseName: "session", deleteRule: .cascadeDeleteRule)
    addToManyRelationship(
      name: "fieldCheckAnimalChecks", from: animalEntity, to: fieldCheckAnimalCheckEntity,
      inverseName: "animal", deleteRule: .nullifyDeleteRule)
    addToManyRelationship(
      name: "fieldCheckFindings", from: animalEntity, to: fieldCheckFindingEntity,
      inverseName: "animal", deleteRule: .nullifyDeleteRule)

    model.entities = [
      herdEntity,
      tagColorDefinitionEntity,
      statusReferenceEntity,
      animalTagEntity,
      pastureGroupEntity,
      pastureEntity,
      animalEntity,
      movementEntity,
      statusRecordEntity,
      healthRecordEntity,
      pregnancyCheckEntity,
      workingProtocolTemplateEntity,
      workingSessionEntity,
      workingQueueItemEntity,
      workingTreatmentRecordEntity,
      fieldCheckSessionEntity,
      fieldCheckAnimalCheckEntity,
      fieldCheckFindingEntity,
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
