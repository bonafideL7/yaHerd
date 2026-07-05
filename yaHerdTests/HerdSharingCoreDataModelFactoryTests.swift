//
//  HerdSharingCoreDataModelFactoryTests.swift
//  yaHerdTests
//

import XCTest
@testable import yaHerd

final class HerdSharingCoreDataModelFactoryTests: XCTestCase {
    func testSharingBridgeModelIncludesHerdAndAnimalEntities() {
        let model = HerdSharingCoreDataModelFactory.makeModel()

        let herdEntity = model.entitiesByName[SharedHerdRecord.entityName]
        let animalEntity = model.entitiesByName[SharedAnimalRecord.entityName]

        XCTAssertNotNil(herdEntity)
        XCTAssertNotNil(animalEntity)
        XCTAssertNotNil(herdEntity?.propertiesByName["animals"])
        XCTAssertNotNil(animalEntity?.propertiesByName["herd"])
        XCTAssertNotNil(animalEntity?.propertiesByName["tagNumber"])
        XCTAssertNotNil(animalEntity?.propertiesByName["statusRawValue"])
        XCTAssertNotNil(animalEntity?.propertiesByName["pasturePublicID"])
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
