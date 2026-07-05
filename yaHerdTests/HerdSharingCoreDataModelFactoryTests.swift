//
//  HerdSharingCoreDataModelFactoryTests.swift
//  yaHerdTests
//

import XCTest
@testable import yaHerd

final class HerdSharingCoreDataModelFactoryTests: XCTestCase {
    func testSharingBridgeModelIncludesHerdPastureGroupPastureAnimalMovementStatusHealthAndPregnancyEntities() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdEntity = model.entitiesByName[SharedHerdRecord.entityName]
        let pastureGroupEntity = model.entitiesByName[SharedPastureGroupRecord.entityName]
        let pastureEntity = model.entitiesByName[SharedPastureRecord.entityName]
        let animalEntity = model.entitiesByName[SharedAnimalRecord.entityName]
        let movementEntity = model.entitiesByName[SharedMovementRecord.entityName]
        let statusRecordEntity = model.entitiesByName[SharedStatusRecord.entityName]
        let healthRecordEntity = model.entitiesByName[SharedHealthRecord.entityName]
        let pregnancyCheckEntity = model.entitiesByName[SharedPregnancyCheckRecord.entityName]

        XCTAssertNotNil(herdEntity)
        XCTAssertNotNil(pastureGroupEntity)
        XCTAssertNotNil(pastureEntity)
        XCTAssertNotNil(animalEntity)
        XCTAssertNotNil(movementEntity)
        XCTAssertNotNil(statusRecordEntity)
        XCTAssertNotNil(healthRecordEntity)
        XCTAssertNotNil(pregnancyCheckEntity)
        XCTAssertNotNil(herdEntity?.propertiesByName["pastureGroups"])
        XCTAssertNotNil(herdEntity?.propertiesByName["pastures"])
        XCTAssertNotNil(herdEntity?.propertiesByName["animals"])
        XCTAssertNotNil(herdEntity?.propertiesByName["movements"])
        XCTAssertNotNil(herdEntity?.propertiesByName["statusRecords"])
        XCTAssertNotNil(herdEntity?.propertiesByName["healthRecords"])
        XCTAssertNotNil(herdEntity?.propertiesByName["pregnancyChecks"])
        XCTAssertNotNil(pastureGroupEntity?.propertiesByName["grazeDays"])
        XCTAssertNotNil(pastureGroupEntity?.propertiesByName["restDays"])
        XCTAssertNotNil(pastureEntity?.propertiesByName["acreage"])
        XCTAssertNotNil(pastureEntity?.propertiesByName["lastGrazedDate"])
        XCTAssertNotNil(animalEntity?.propertiesByName["pasturePublicID"])
        XCTAssertNotNil(animalEntity?.propertiesByName["movements"])
        XCTAssertNotNil(animalEntity?.propertiesByName["statusRecords"])
        XCTAssertNotNil(animalEntity?.propertiesByName["healthRecords"])
        XCTAssertNotNil(animalEntity?.propertiesByName["pregnancyChecks"])
        XCTAssertNotNil(movementEntity?.propertiesByName["animalPublicID"])
        XCTAssertNotNil(movementEntity?.propertiesByName["fromPasture"])
        XCTAssertNotNil(statusRecordEntity?.propertiesByName["oldStatusRawValue"])
        XCTAssertNotNil(statusRecordEntity?.propertiesByName["newStatusRawValue"])
        XCTAssertNotNil(healthRecordEntity?.propertiesByName["treatment"])
        XCTAssertNotNil(healthRecordEntity?.propertiesByName["notes"])
        XCTAssertNotNil(pregnancyCheckEntity?.propertiesByName["resultRawValue"])
        XCTAssertNotNil(pregnancyCheckEntity?.propertiesByName["sireAnimalPublicID"])
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


    func testHerdHealthRecordsRelationshipIsInverseOfHealthRecordHerdRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdHealthRecords = model.entitiesByName[SharedHerdRecord.entityName]?
            .relationshipsByName["healthRecords"]
        let healthRecordHerd = model.entitiesByName[SharedHealthRecord.entityName]?
            .relationshipsByName["herd"]

        XCTAssertEqual(herdHealthRecords?.destinationEntity?.name, SharedHealthRecord.entityName)
        XCTAssertEqual(healthRecordHerd?.destinationEntity?.name, SharedHerdRecord.entityName)
        XCTAssertTrue(herdHealthRecords?.inverseRelationship === healthRecordHerd)
        XCTAssertTrue(healthRecordHerd?.inverseRelationship === herdHealthRecords)
    }

    func testAnimalHealthRecordsRelationshipIsInverseOfHealthRecordAnimalRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let animalHealthRecords = model.entitiesByName[SharedAnimalRecord.entityName]?
            .relationshipsByName["healthRecords"]
        let healthRecordAnimal = model.entitiesByName[SharedHealthRecord.entityName]?
            .relationshipsByName["animal"]

        XCTAssertEqual(animalHealthRecords?.destinationEntity?.name, SharedHealthRecord.entityName)
        XCTAssertEqual(healthRecordAnimal?.destinationEntity?.name, SharedAnimalRecord.entityName)
        XCTAssertTrue(animalHealthRecords?.inverseRelationship === healthRecordAnimal)
        XCTAssertTrue(healthRecordAnimal?.inverseRelationship === animalHealthRecords)
    }

    func testHerdPregnancyChecksRelationshipIsInverseOfPregnancyCheckHerdRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdPregnancyChecks = model.entitiesByName[SharedHerdRecord.entityName]?
            .relationshipsByName["pregnancyChecks"]
        let pregnancyCheckHerd = model.entitiesByName[SharedPregnancyCheckRecord.entityName]?
            .relationshipsByName["herd"]

        XCTAssertEqual(herdPregnancyChecks?.destinationEntity?.name, SharedPregnancyCheckRecord.entityName)
        XCTAssertEqual(pregnancyCheckHerd?.destinationEntity?.name, SharedHerdRecord.entityName)
        XCTAssertTrue(herdPregnancyChecks?.inverseRelationship === pregnancyCheckHerd)
        XCTAssertTrue(pregnancyCheckHerd?.inverseRelationship === herdPregnancyChecks)
    }

    func testAnimalPregnancyChecksRelationshipIsInverseOfPregnancyCheckAnimalRelationship() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let animalPregnancyChecks = model.entitiesByName[SharedAnimalRecord.entityName]?
            .relationshipsByName["pregnancyChecks"]
        let pregnancyCheckAnimal = model.entitiesByName[SharedPregnancyCheckRecord.entityName]?
            .relationshipsByName["animal"]

        XCTAssertEqual(animalPregnancyChecks?.destinationEntity?.name, SharedPregnancyCheckRecord.entityName)
        XCTAssertEqual(pregnancyCheckAnimal?.destinationEntity?.name, SharedAnimalRecord.entityName)
        XCTAssertTrue(animalPregnancyChecks?.inverseRelationship === pregnancyCheckAnimal)
        XCTAssertTrue(pregnancyCheckAnimal?.inverseRelationship === animalPregnancyChecks)
    }

}
