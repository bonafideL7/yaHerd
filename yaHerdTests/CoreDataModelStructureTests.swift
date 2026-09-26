import CoreData
import XCTest
@testable import yaHerd

final class CoreDataModelStructureTests: XCTestCase {
    private static let expectedEntities: Set<String> = [
        "Herd",
        "TagColorDefinition",
        "AnimalStatusReference",
        "PastureGroup",
        "Pasture",
        "Animal",
        "AnimalTag",
        "MovementRecord",
        "StatusRecord",
        "HealthRecord",
        "PregnancyCheck",
        "FieldCheckSession",
        "FieldCheckAnimalCheck",
        "FieldCheckFinding",
        "WorkingTreatmentTemplate",
        "WorkingSession",
        "WorkingQueueItem",
        "WorkingTreatmentRecord"
    ]

    func testModelLoadsWithExactDurableEntityInventory() throws {
        let model = try loadModel()

        XCTAssertEqual(Set(model.entities.compactMap(\.name)), Self.expectedEntities)
    }

    func testEveryDurableEntityHasRequiredApplicationUUID() throws {
        let model = try loadModel()

        for entityName in Self.expectedEntities {
            let entity = try entity(named: entityName, in: model)
            let id = try attribute(named: "id", in: entity)

            XCTAssertEqual(id.type, .uuid, "\(entityName).id must be UUID.")
            XCTAssertFalse(id.isOptional, "\(entityName).id must be required.")
        }
    }

    func testEveryHerdOwnedEntityHasRequiredHerdRelationshipAndCascadeInverse() throws {
        let model = try loadModel()
        let herd = try entity(named: "Herd", in: model)

        for entityName in Self.expectedEntities.subtracting(["Herd"]) {
            let entity = try entity(named: entityName, in: model)
            let herdRelationship = try relationship(named: "herd", in: entity)

            XCTAssertEqual(herdRelationship.destinationEntity?.name, "Herd")
            XCTAssertFalse(herdRelationship.isOptional)
            XCTAssertEqual(herdRelationship.maxCount, 1)

            let inverse = try XCTUnwrap(herdRelationship.inverseRelationship)
            XCTAssertEqual(inverse.entity, herd)
            XCTAssertTrue(inverse.isToMany)
            XCTAssertEqual(inverse.deleteRule, .cascadeDeleteRule)
        }
    }

    func testApplicationIDUniquenessIsRepositoryEnforced() throws {
        let model = try loadModel()

        for entityName in Self.expectedEntities {
            let entity = try entity(named: entityName, in: model)
            XCTAssertTrue(
                entity.uniquenessConstraints.isEmpty,
                "\(entityName) must not use a Core Data uniqueness constraint. Application UUID uniqueness is enforced by repository/transaction validation."
            )
        }
    }

    func testBlueprintFetchIndexesArePresent() throws {
        let model = try loadModel()
        let expected: [String: Set<String>] = [
            "Herd": ["id"],
            "TagColorDefinition": ["id"],
            "AnimalStatusReference": ["id"],
            "PastureGroup": ["id"],
            "Pasture": ["id", "sortOrder"],
            "Animal": ["id", "statusRawValue", "birthDate", "isArchived"],
            "AnimalTag": ["id", "number", "isActive", "isPrimary"],
            "MovementRecord": ["id"],
            "StatusRecord": ["id"],
            "HealthRecord": ["id"],
            "PregnancyCheck": ["id"],
            "FieldCheckSession": ["id", "startedAt", "completedAt"],
            "FieldCheckAnimalCheck": ["id"],
            "FieldCheckFinding": ["id", "statusRawValue", "recordedAt"],
            "WorkingTreatmentTemplate": ["id"],
            "WorkingSession": ["id", "statusRawValue", "date"],
            "WorkingQueueItem": ["id"],
            "WorkingTreatmentRecord": ["id"]
        ]

        for (entityName, expectedProperties) in expected {
            let entity = try entity(named: entityName, in: model)
            let indexedProperties = Set(
                entity.indexes
                    .flatMap(\.elements)
                    .compactMap(\.propertyName)
            )
            XCTAssertEqual(indexedProperties, expectedProperties, "Unexpected indexes for \(entityName).")
        }
    }

    func testAnimalAggregateRelationshipDeleteRules() throws {
        let model = try loadModel()
        let animal = try entity(named: "Animal", in: model)

        for name in ["tags", "movementRecords", "statusRecords", "healthRecords", "pregnancyChecks"] {
            let relationship = try relationship(named: name, in: animal)
            XCTAssertTrue(relationship.isToMany)
            XCTAssertEqual(relationship.deleteRule, .cascadeDeleteRule, "Animal.\(name) must be owned history.")
        }

        for name in [
            "sireOffspring",
            "damOffspring",
            "pregnancyChecksAsSire",
            "fieldCheckAnimalChecks",
            "fieldCheckFindings",
            "workingQueueItems",
            "workingTreatmentRecords"
        ] {
            XCTAssertEqual(
                try relationship(named: name, in: animal).deleteRule,
                .nullifyDeleteRule,
                "Animal.\(name) must survive parent/live-reference deletion."
            )
        }

        XCTAssertTrue(try attribute(named: "editorRevision", in: animal).type == .uuid)
        XCTAssertFalse(try attribute(named: "editorRevision", in: animal).isOptional)

        for rejected in ["tagNumber", "tagColorID", "locationRawValue", "statusReferenceID"] {
            XCTAssertNil(animal.propertiesByName[rejected], "Rejected duplicate field \(rejected) must not exist.")
        }
    }

    func testPregnancySireIsIndependentNullifyingReference() throws {
        let model = try loadModel()
        let pregnancy = try entity(named: "PregnancyCheck", in: model)

        let owner = try relationship(named: "animal", in: pregnancy)
        XCTAssertFalse(owner.isOptional)
        XCTAssertEqual(owner.inverseRelationship?.deleteRule, .cascadeDeleteRule)

        let sire = try relationship(named: "sire", in: pregnancy)
        XCTAssertTrue(sire.isOptional)
        XCTAssertEqual(sire.inverseRelationship?.name, "pregnancyChecksAsSire")
        XCTAssertEqual(sire.inverseRelationship?.deleteRule, .nullifyDeleteRule)
    }

    func testPastureAndGroupRelationshipsSupportDeletionSemantics() throws {
        let model = try loadModel()
        let pasture = try entity(named: "Pasture", in: model)
        let group = try entity(named: "PastureGroup", in: model)

        XCTAssertTrue(try relationship(named: "group", in: pasture).isOptional)
        XCTAssertEqual(try relationship(named: "pastures", in: group).deleteRule, .nullifyDeleteRule)

        for name in [
            "animals",
            "workingSourceSessions",
            "workingCollectedQueueItems",
            "workingDestinationQueueItems",
            "fieldCheckSessions"
        ] {
            XCTAssertEqual(try relationship(named: name, in: pasture).deleteRule, .nullifyDeleteRule)
        }
    }

    func testFieldCheckSnapshotOptionalityAndOwnershipMatchesBlueprint() throws {
        let model = try loadModel()
        let session = try entity(named: "FieldCheckSession", in: model)
        let check = try entity(named: "FieldCheckAnimalCheck", in: model)
        let finding = try entity(named: "FieldCheckFinding", in: model)

        XCTAssertFalse(try attribute(named: "pastureIDSnapshot", in: session).isOptional)
        XCTAssertFalse(try attribute(named: "pastureNameSnapshot", in: session).isOptional)

        XCTAssertFalse(try attribute(named: "animalIDSnapshot", in: check).isOptional)
        XCTAssertTrue(try attribute(named: "damRosterTagNumberSnapshot", in: check).isOptional)
        XCTAssertNil(check.propertiesByName["note"])

        XCTAssertTrue(try attribute(named: "animalIDSnapshot", in: finding).isOptional)
        XCTAssertTrue(try attribute(named: "animalDisplayTagNumberSnapshot", in: finding).isOptional)
        XCTAssertTrue(try attribute(named: "animalNameSnapshot", in: finding).isOptional)
        XCTAssertNil(finding.propertiesByName["sessionIDSnapshot"])
        XCTAssertNil(finding.propertiesByName["needsAttention"])

        XCTAssertEqual(try relationship(named: "animalChecks", in: session).deleteRule, .cascadeDeleteRule)
        XCTAssertEqual(try relationship(named: "findings", in: session).deleteRule, .cascadeDeleteRule)
        XCTAssertFalse(try relationship(named: "session", in: finding).isOptional)
    }

    func testWorkingSnapshotsAndOwnershipMatchBlueprint() throws {
        let model = try loadModel()
        let session = try entity(named: "WorkingSession", in: model)
        let queue = try entity(named: "WorkingQueueItem", in: model)

        XCTAssertFalse(try attribute(named: "sourcePastureIDSnapshot", in: session).isOptional)
        XCTAssertFalse(try attribute(named: "sourcePastureNameSnapshot", in: session).isOptional)

        for snapshot in [
            "animalIDSnapshot",
            "animalTagNumberSnapshot",
            "animalNameSnapshot",
            "animalSexRawValueSnapshot"
        ] {
            XCTAssertFalse(try attribute(named: snapshot, in: queue).isOptional)
        }

        for name in ["queueItems", "treatmentRecords", "healthRecords", "pregnancyChecks"] {
            XCTAssertEqual(try relationship(named: name, in: session).deleteRule, .cascadeDeleteRule)
        }
        XCTAssertEqual(try relationship(named: "activeAnimals", in: session).deleteRule, .nullifyDeleteRule)

        XCTAssertNil(session.propertiesByName["currentQueueIndex"])
        XCTAssertNil(session.propertiesByName["notes"])
        XCTAssertNil(queue.propertiesByName["queueOrder"])
        XCTAssertNil(queue.propertiesByName["workNotes"])
    }

    func testRejectedPersistenceBaggageIsAbsent() throws {
        let model = try loadModel()

        XCTAssertNil(try entity(named: "Herd", in: model).propertiesByName["schemaVersion"])
        XCTAssertNil(try entity(named: "AnimalStatusReference", in: model).propertiesByName["createdAt"])
        XCTAssertNil(try entity(named: "StatusRecord", in: model).propertiesByName["oldStatusReferenceID"])
        XCTAssertNil(try entity(named: "StatusRecord", in: model).propertiesByName["newStatusReferenceID"])

        let forbiddenEntityFragments = ["Collaboration", "Shared", "Mirror", "RevisionRecord", "RepairJournal"]
        for name in Self.expectedEntities {
            XCTAssertFalse(forbiddenEntityFragments.contains { name.contains($0) })
        }
    }

    func testManagedObjectClassesAreExplicitCDTypes() throws {
        let model = try loadModel()
        let expectedClasses: [String: AnyClass] = [
            "Herd": CDHerd.self,
            "TagColorDefinition": CDTagColorDefinition.self,
            "AnimalStatusReference": CDAnimalStatusReference.self,
            "PastureGroup": CDPastureGroup.self,
            "Pasture": CDPasture.self,
            "Animal": CDAnimal.self,
            "AnimalTag": CDAnimalTag.self,
            "MovementRecord": CDMovementRecord.self,
            "StatusRecord": CDStatusRecord.self,
            "HealthRecord": CDHealthRecord.self,
            "PregnancyCheck": CDPregnancyCheck.self,
            "FieldCheckSession": CDFieldCheckSession.self,
            "FieldCheckAnimalCheck": CDFieldCheckAnimalCheck.self,
            "FieldCheckFinding": CDFieldCheckFinding.self,
            "WorkingTreatmentTemplate": CDWorkingTreatmentTemplate.self,
            "WorkingSession": CDWorkingSession.self,
            "WorkingQueueItem": CDWorkingQueueItem.self,
            "WorkingTreatmentRecord": CDWorkingTreatmentRecord.self
        ]

        for (entityName, managedClass) in expectedClasses {
            let entity = try entity(named: entityName, in: model)
            let expectedName = NSStringFromClass(managedClass)
            let configuredName = try XCTUnwrap(entity.managedObjectClassName)
            XCTAssertTrue(
                configuredName == expectedName || expectedName.hasSuffix(".\(configuredName)"),
                "\(entityName) must use explicit \(expectedName), found \(configuredName)."
            )
        }
    }

    private func loadModel(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSManagedObjectModel {
        let bundle = Bundle(for: CDHerd.self)
        let url = bundle.url(forResource: "yaHerdModel", withExtension: "momd")
            ?? bundle.url(forResource: "yaHerdModel", withExtension: "mom")
        let modelURL = try XCTUnwrap(url, "Compiled yaHerdModel resource is missing.", file: file, line: line)
        return try XCTUnwrap(
            NSManagedObjectModel(contentsOf: modelURL),
            "Compiled yaHerdModel could not be loaded.",
            file: file,
            line: line
        )
    }

    private func entity(
        named name: String,
        in model: NSManagedObjectModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSEntityDescription {
        try XCTUnwrap(model.entitiesByName[name], "Missing entity \(name).", file: file, line: line)
    }

    private func attribute(
        named name: String,
        in entity: NSEntityDescription,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSAttributeDescription {
        try XCTUnwrap(
            entity.attributesByName[name],
            "Missing attribute \(entity.name ?? "<unnamed>").\(name).",
            file: file,
            line: line
        )
    }

    private func relationship(
        named name: String,
        in entity: NSEntityDescription,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSRelationshipDescription {
        try XCTUnwrap(
            entity.relationshipsByName[name],
            "Missing relationship \(entity.name ?? "<unnamed>").\(name).",
            file: file,
            line: line
        )
    }
}
