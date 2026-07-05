//
//  HerdSharingCoreDataModelFactoryTests.swift
//  yaHerdTests
//

import XCTest
@testable import yaHerd

final class HerdSharingCoreDataModelFactoryTests: XCTestCase {
    func testSharingBridgeModelIncludesHerdPastureGroupPastureAndAnimalEntities() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdEntity = model.entitiesByName[SharedHerdRecord.entityName]
        let pastureGroupEntity = model.entitiesByName[SharedPastureGroupRecord.entityName]
        let pastureEntity = model.entitiesByName[SharedPastureRecord.entityName]
        let animalEntity = model.entitiesByName[SharedAnimalRecord.entityName]

        XCTAssertNotNil(herdEntity)
        XCTAssertNotNil(pastureGroupEntity)
        XCTAssertNotNil(pastureEntity)
        XCTAssertNotNil(animalEntity)
        XCTAssertNotNil(herdEntity?.propertiesByName["pastureGroups"])
        XCTAssertNotNil(herdEntity?.propertiesByName["pastures"])
        XCTAssertNotNil(herdEntity?.propertiesByName["animals"])
        XCTAssertNotNil(pastureGroupEntity?.propertiesByName["grazeDays"])
        XCTAssertNotNil(pastureGroupEntity?.propertiesByName["restDays"])
        XCTAssertNotNil(pastureEntity?.propertiesByName["acreage"])
        XCTAssertNotNil(pastureEntity?.propertiesByName["lastGrazedDate"])
        XCTAssertNotNil(animalEntity?.propertiesByName["pasturePublicID"])
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
}
