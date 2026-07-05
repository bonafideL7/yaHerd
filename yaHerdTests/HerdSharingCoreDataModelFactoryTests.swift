//
//  HerdSharingCoreDataModelFactoryTests.swift
//  yaHerdTests
//

import XCTest
@testable import yaHerd

final class HerdSharingCoreDataModelFactoryTests: XCTestCase {
    func testSharingBridgeModelIncludesHerdPastureGroupPastureAnimalMovementAndStatusEntities() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdEntity = model.entitiesByName[SharedHerdRecord.entityName]
        let pastureGroupEntity = model.entitiesByName[SharedPastureGroupRecord.entityName]
        let pastureEntity = model.entitiesByName[SharedPastureRecord.entityName]
        let animalEntity = model.entitiesByName[SharedAnimalRecord.entityName]
        let movementEntity = model.entitiesByName[SharedMovementRecord.entityName]
        let statusRecordEntity = model.entitiesByName[SharedStatusRecord.entityName]

        XCTAssertNotNil(herdEntity)
        XCTAssertNotNil(pastureGroupEntity)
        XCTAssertNotNil(pastureEntity)
        XCTAssertNotNil(animalEntity)
        XCTAssertNotNil(movementEntity)
        XCTAssertNotNil(statusRecordEntity)
        XCTAssertNotNil(herdEntity?.propertiesByName["pastureGroups"])
        XCTAssertNotNil(herdEntity?.propertiesByName["pastures"])
        XCTAssertNotNil(herdEntity?.propertiesByName["animals"])
        XCTAssertNotNil(herdEntity?.propertiesByName["movements"])
        XCTAssertNotNil(herdEntity?.propertiesByName["statusRecords"])
        XCTAssertNotNil(pastureGroupEntity?.propertiesByName["grazeDays"])
        XCTAssertNotNil(pastureGroupEntity?.propertiesByName["restDays"])
        XCTAssertNotNil(pastureEntity?.propertiesByName["acreage"])
        XCTAssertNotNil(pastureEntity?.propertiesByName["lastGrazedDate"])
        XCTAssertNotNil(animalEntity?.propertiesByName["pasturePublicID"])
        XCTAssertNotNil(animalEntity?.propertiesByName["movements"])
        XCTAssertNotNil(animalEntity?.propertiesByName["statusRecords"])
        XCTAssertNotNil(movementEntity?.propertiesByName["animalPublicID"])
        XCTAssertNotNil(movementEntity?.propertiesByName["fromPasture"])
        XCTAssertNotNil(statusRecordEntity?.propertiesByName["oldStatusRawValue"])
        XCTAssertNotNil(statusRecordEntity?.propertiesByName["newStatusRawValue"])
    }

    func testHerdPastureGroupsRelationshipIsInverseOfPastureGroupHerdRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdPastureGroups = model.entitiesByName[SharedHerdRecord.entityName]?
            .relationshipsByName["pastureGroups"]
        let pastureGroupHerd = model.entitiesByName[SharedPastureGroupRecord.entityName]?
            .relationshipsByName["herd"]

        XCTAssertEqual(herdPastureGroups?.destinationEntity?.name, SharedPastureGroupRecord.entityName)
        XCTAssertEqual(pastureGroupHerd?.destinationEntity?.name, SharedHerdRecord.entityName)
        XCTAssertTrue(herdPastureGroups?.inverseRelationship === pastureGroupHerd)
        XCTAssertTrue(pastureGroupHerd?.inverseRelationship === herdPastureGroups)
    }

    func testHerdPasturesRelationshipIsInverseOfPastureHerdRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdPastures = model.entitiesByName[SharedHerdRecord.entityName]?
            .relationshipsByName["pastures"]
        let pastureHerd = model.entitiesByName[SharedPastureRecord.entityName]?
            .relationshipsByName["herd"]

        XCTAssertEqual(herdPastures?.destinationEntity?.name, SharedPastureRecord.entityName)
        XCTAssertEqual(pastureHerd?.destinationEntity?.name, SharedHerdRecord.entityName)
        XCTAssertTrue(herdPastures?.inverseRelationship === pastureHerd)
        XCTAssertTrue(pastureHerd?.inverseRelationship === herdPastures)
    }

    func testPastureGroupPasturesRelationshipIsInverseOfPastureGroupRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let pastureGroupPastures = model.entitiesByName[SharedPastureGroupRecord.entityName]?
            .relationshipsByName["pastures"]
        let pastureGroup = model.entitiesByName[SharedPastureRecord.entityName]?
            .relationshipsByName["group"]

        XCTAssertEqual(pastureGroupPastures?.destinationEntity?.name, SharedPastureRecord.entityName)
        XCTAssertEqual(pastureGroup?.destinationEntity?.name, SharedPastureGroupRecord.entityName)
        XCTAssertTrue(pastureGroupPastures?.inverseRelationship === pastureGroup)
        XCTAssertTrue(pastureGroup?.inverseRelationship === pastureGroupPastures)
    }

    func testHerdAnimalsRelationshipIsInverseOfAnimalHerdRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdAnimals = model.entitiesByName[SharedHerdRecord.entityName]?
            .relationshipsByName["animals"]
        let animalHerd = model.entitiesByName[SharedAnimalRecord.entityName]?
            .relationshipsByName["herd"]

        XCTAssertEqual(herdAnimals?.destinationEntity?.name, SharedAnimalRecord.entityName)
        XCTAssertEqual(animalHerd?.destinationEntity?.name, SharedHerdRecord.entityName)
        XCTAssertTrue(herdAnimals?.inverseRelationship === animalHerd)
        XCTAssertTrue(animalHerd?.inverseRelationship === herdAnimals)
    }


    func testHerdMovementsRelationshipIsInverseOfMovementHerdRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdMovements = model.entitiesByName[SharedHerdRecord.entityName]?
            .relationshipsByName["movements"]
        let movementHerd = model.entitiesByName[SharedMovementRecord.entityName]?
            .relationshipsByName["herd"]

        XCTAssertEqual(herdMovements?.destinationEntity?.name, SharedMovementRecord.entityName)
        XCTAssertEqual(movementHerd?.destinationEntity?.name, SharedHerdRecord.entityName)
        XCTAssertTrue(herdMovements?.inverseRelationship === movementHerd)
        XCTAssertTrue(movementHerd?.inverseRelationship === herdMovements)
    }

    func testAnimalMovementsRelationshipIsInverseOfMovementAnimalRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let animalMovements = model.entitiesByName[SharedAnimalRecord.entityName]?
            .relationshipsByName["movements"]
        let movementAnimal = model.entitiesByName[SharedMovementRecord.entityName]?
            .relationshipsByName["animal"]

        XCTAssertEqual(animalMovements?.destinationEntity?.name, SharedMovementRecord.entityName)
        XCTAssertEqual(movementAnimal?.destinationEntity?.name, SharedAnimalRecord.entityName)
        XCTAssertTrue(animalMovements?.inverseRelationship === movementAnimal)
        XCTAssertTrue(movementAnimal?.inverseRelationship === animalMovements)
    }

    func testHerdStatusRecordsRelationshipIsInverseOfStatusRecordHerdRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdStatusRecords = model.entitiesByName[SharedHerdRecord.entityName]?
            .relationshipsByName["statusRecords"]
        let statusRecordHerd = model.entitiesByName[SharedStatusRecord.entityName]?
            .relationshipsByName["herd"]

        XCTAssertEqual(herdStatusRecords?.destinationEntity?.name, SharedStatusRecord.entityName)
        XCTAssertEqual(statusRecordHerd?.destinationEntity?.name, SharedHerdRecord.entityName)
        XCTAssertTrue(herdStatusRecords?.inverseRelationship === statusRecordHerd)
        XCTAssertTrue(statusRecordHerd?.inverseRelationship === herdStatusRecords)
    }

    func testAnimalStatusRecordsRelationshipIsInverseOfStatusRecordAnimalRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let animalStatusRecords = model.entitiesByName[SharedAnimalRecord.entityName]?
            .relationshipsByName["statusRecords"]
        let statusRecordAnimal = model.entitiesByName[SharedStatusRecord.entityName]?
            .relationshipsByName["animal"]

        XCTAssertEqual(animalStatusRecords?.destinationEntity?.name, SharedStatusRecord.entityName)
        XCTAssertEqual(statusRecordAnimal?.destinationEntity?.name, SharedAnimalRecord.entityName)
        XCTAssertTrue(animalStatusRecords?.inverseRelationship === statusRecordAnimal)
        XCTAssertTrue(statusRecordAnimal?.inverseRelationship === animalStatusRecords)
    }
}
