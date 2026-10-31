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

    func testWorkingTreatmentRecordRejectsMissingImportedItemName() async throws {
        let model = try loadModel()
        let entity = try entity(named: "WorkingTreatmentRecord", in: model)
        XCTAssertTrue(try attribute(named: "itemNameSnapshot", in: entity).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let record = CDWorkingTreatmentRecord(context: context)
            record.id = UUID()
            record.itemNameSnapshot = nil
            XCTAssertThrowsError(try WorkingMapper.makeTreatmentRecordSnapshot(from: record)) { error in
                XCTAssertEqual(error as? CoreDataWorkingMappingError, .corruptTreatmentRecord(recordID: record.id))
            }
            context.rollback()
        }
    }

    func testCloudKitStatusReferenceBaseStatusIsOptional() throws {
        let model = try loadModel()
        let entity = try entity(named: "AnimalStatusReference", in: model)
        XCTAssertTrue(try attribute(named: "baseStatusRawValue", in: entity).isOptional)
    }

    func testRequiredScalarAttributesHaveCloudKitDefaults() throws {
        let model = try loadModel()

        for entity in model.entities {
            for attribute in entity.attributesByName.values where !attribute.isOptional {
                switch attribute.attributeType {
                case .booleanAttributeType, .integer16AttributeType, .integer32AttributeType,
                     .integer64AttributeType, .floatAttributeType, .doubleAttributeType:
                    let expected: Double = entity.name == "TagColorDefinition"
                        && attribute.name == "alpha" ? 1 : 0
                    XCTAssertEqual(
                        (attribute.defaultValue as? NSNumber)?.doubleValue,
                        expected,
                        "Missing or incorrect CloudKit default: \(entity.name ?? "<unnamed>").\(attribute.name)"
                    )
                default:
                    break
                }
            }
        }
    }

    func testCloudKitSemanticallyEmptyTextAttributesHaveDefaults() throws {
        let model = try loadModel()
        let emptyIsValid: [(entity: String, attribute: String)] = [
            ("Animal", "name"),
            ("TagColorDefinition", "prefix"),
            ("FieldCheckSession", "notes"),
            ("FieldCheckFinding", "note"),
            ("FieldCheckAnimalCheck", "rosterTagNumberSnapshot"),
            ("FieldCheckAnimalCheck", "animalNameSnapshot"),
            ("WorkingQueueItem", "animalTagNumberSnapshot"),
            ("WorkingQueueItem", "animalNameSnapshot")
        ]

        for field in emptyIsValid {
            let entity = try entity(named: field.entity, in: model)
            let attribute = try attribute(named: field.attribute, in: entity)
            XCTAssertFalse(attribute.isOptional)
            XCTAssertEqual(
                attribute.defaultValue as? String,
                "",
                "Missing empty-string CloudKit default for \(field.entity).\(field.attribute)"
            )
        }
    }

    func testCloudKitPastureGroupNameAllowsMissingStorage() throws {
        let model = try loadModel()
        let group = try entity(named: "PastureGroup", in: model)
        XCTAssertTrue(try attribute(named: "name", in: group).isOptional)
    }

    func testWorkingSessionTitleHasExistingRepositoryFallbackAsCloudKitDefault() throws {
        let model = try loadModel()
        let session = try entity(named: "WorkingSession", in: model)
        let title = try attribute(named: "treatmentTemplateNameSnapshot", in: session)

        XCTAssertFalse(title.isOptional)
        XCTAssertEqual(title.defaultValue as? String, "Working Session")
    }

    func testRequiredSexFieldsDefaultToDomainUnknownForCloudKit() throws {
        let model = try loadModel()
        let fields: [(entity: String, attribute: String)] = [
            ("Animal", "sexRawValue"),
            ("FieldCheckAnimalCheck", "animalSexRawValueSnapshot"),
            ("WorkingQueueItem", "animalSexRawValueSnapshot")
        ]

        for field in fields {
            let entity = try entity(named: field.entity, in: model)
            let attribute = try attribute(named: field.attribute, in: entity)

            XCTAssertFalse(attribute.isOptional)
            XCTAssertEqual(
                attribute.defaultValue as? String,
                Sex.unknown.rawValue,
                "Missing unknown-sex CloudKit default for \(field.entity).\(field.attribute)"
            )
        }
    }

    /// Stage 1 preflight: the CloudKit-required storage nullability changes must
    /// be inferable without a custom NSMappingModel or migration policy.
    func testCloudKitNullabilityChangesCanBeLightweightMigrated() throws {
        let originalModel = try loadModel()
        let cloudKitModel = try XCTUnwrap(originalModel.copy() as? NSManagedObjectModel)

        for entity in cloudKitModel.entities {
            for attribute in entity.attributesByName.values {
                attribute.isOptional = true
            }
            for relationship in entity.relationshipsByName.values {
                relationship.isOptional = true
            }
        }

        let mapping = try NSMappingModel.inferredMappingModel(
            forSourceModel: originalModel,
            destinationModel: cloudKitModel
        )
        XCTAssertEqual(mapping.entityMappings.count, Self.expectedEntities.count)
    }

    /// Exercise a real SQLite store instead of assuming schema inference is
    /// sufficient to keep pre-update Herd and Pasture records intact.
    func testCloudKitNullabilityLightweightMigrationPreservesExistingSQLiteData() throws {
        let originalModel = try loadModel()

        // Model a source schema that is NOT in the application bundle. This
        // exercises Core Data's source-model discovery from existing SQLite,
        // rather than accidentally relying on the currently compiled .mom.
        let originalHerd = try XCTUnwrap(originalModel.entitiesByName["Herd"])
        let probe = NSAttributeDescription()
        probe.name = "sourceModelCacheProbe"
        probe.attributeType = .stringAttributeType
        probe.isOptional = true
        originalHerd.properties.append(probe)

        let cloudKitModel = try XCTUnwrap(originalModel.copy() as? NSManagedObjectModel)
        for entity in cloudKitModel.entities {
            entity.attributesByName.values.forEach { $0.isOptional = true }
            entity.relationshipsByName.values.forEach { $0.isOptional = true }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitModelMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("pre-cloudkit.sqlite")
        let herdID = UUID()
        let pastureID = UUID()

        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: originalModel)
        let oldStore = try oldCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: nil
        )
        let oldContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        oldContext.persistentStoreCoordinator = oldCoordinator
        try oldContext.performAndWait {
            let herd = NSEntityDescription.insertNewObject(forEntityName: "Herd", into: oldContext)
            herd.setValue(herdID, forKey: "id")
            herd.setValue("Existing Herd", forKey: "name")
            herd.setValue(Date(timeIntervalSince1970: 100), forKey: "createdAt")
            herd.setValue(Date(timeIntervalSince1970: 200), forKey: "updatedAt")

            let pasture = NSEntityDescription.insertNewObject(forEntityName: "Pasture", into: oldContext)
            pasture.setValue(pastureID, forKey: "id")
            pasture.setValue("Existing Pasture", forKey: "name")
            pasture.setValue(Int64(1), forKey: "sortOrder")
            pasture.setValue(herd, forKey: "herd")
            try oldContext.save()
        }
        oldContext.reset()
        try oldCoordinator.remove(oldStore)

        let migratedCoordinator = NSPersistentStoreCoordinator(managedObjectModel: cloudKitModel)
        let migratedStore = try migratedCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true
            ]
        )
        let readContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        readContext.persistentStoreCoordinator = migratedCoordinator
        try readContext.performAndWait {
            let herds = try readContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Herd"))
            let pastures = try readContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Pasture"))
            XCTAssertEqual(herds.count, 1)
            XCTAssertEqual(herds.first?.value(forKey: "id") as? UUID, herdID)
            XCTAssertEqual(herds.first?.value(forKey: "name") as? String, "Existing Herd")
            XCTAssertEqual(pastures.count, 1)
            XCTAssertEqual(pastures.first?.value(forKey: "id") as? UUID, pastureID)
            XCTAssertEqual(pastures.first?.value(forKey: "herd") as? NSManagedObject, herds.first)
        }
        readContext.reset()
        try migratedCoordinator.remove(migratedStore)
    }

    func testMissingPregnancyResultIsRejectedWithoutInventingUnknownResult() async throws {
        let model = try loadModel()
        let pregnancy = try entity(named: "PregnancyCheck", in: model)
        XCTAssertTrue(try attribute(named: "resultRawValue", in: pregnancy).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let check = CDPregnancyCheck(context: context)
            check.id = UUID()
            check.date = .now
            check.resultRawValue = nil

            XCTAssertThrowsError(try WorkingMapper.makePregnancyCheckSnapshot(from: check)) { error in
                XCTAssertEqual(
                    error as? CoreDataWorkingMappingError,
                    .invalidPregnancyResult(checkID: check.id, value: "")
                )
            }
            XCTAssertNil(check.resultRawValue)
            context.rollback()
        }
    }

    func testCloudKitTemplatePayloadAllowsMissingStorageButRejectsMissingDomainData() async throws {
        let model = try loadModel()
        let templateEntity = try entity(named: "WorkingTreatmentTemplate", in: model)
        XCTAssertTrue(try attribute(named: "itemsData", in: templateEntity).isOptional)
        XCTAssertTrue(try attribute(named: "name", in: templateEntity).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()

        try context.performAndWait {
            let template = CDWorkingTreatmentTemplate(context: context)
            template.id = UUID()
            template.name = "Incomplete imported template"
            template.itemsData = nil

            XCTAssertThrowsError(
                try WorkingMapper.treatmentTemplateItems(template)
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataWorkingMappingError,
                    .corruptTreatmentTemplate(templateID: template.id)
                )
            }
            context.rollback()
        }
    }

    func testCloudKitSessionPlanAllowsMissingStorageButRejectsMissingDomainData() async throws {
        let model = try loadModel()
        let sessionEntity = try entity(named: "WorkingSession", in: model)
        XCTAssertTrue(try attribute(named: "plannedTreatmentsData", in: sessionEntity).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()

        try context.performAndWait {
            let session = CDWorkingSession(context: context)
            session.id = UUID()
            session.plannedTreatmentsData = nil

            XCTAssertThrowsError(
                try WorkingMapper.plannedTreatments(session)
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataWorkingMappingError,
                    .corruptPlannedTreatments(sessionID: session.id)
                )
            }
            context.rollback()
        }
    }

    func testMissingAnimalDistinguishingFeaturesPayloadIsRejected() async throws {
        let model = try loadModel()
        let entity = try entity(named: "Animal", in: model)
        XCTAssertTrue(try attribute(named: "distinguishingFeaturesData", in: entity).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let animal = CDAnimal(context: context)
            animal.id = UUID()
            animal.distinguishingFeaturesData = nil

            XCTAssertThrowsError(
                try CoreDataAnimalProjection.distinguishingFeatures(animal)
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataAnimalRepositoryError,
                    .corruptDistinguishingFeatures(animalID: animal.id)
                )
            }
            XCTAssertNil(animal.distinguishingFeaturesData)

            animal.distinguishingFeaturesData = Data("[]".utf8)
            XCTAssertTrue(try CoreDataAnimalProjection.distinguishingFeatures(animal).isEmpty)
            context.rollback()
        }
    }

    func testCloudKitFindingPastureNameIsOptionalWithoutLosingHistoricalSnapshot() async throws {
        let model = try loadModel()
        let entity = try entity(named: "FieldCheckFinding", in: model)
        XCTAssertTrue(try attribute(named: "pastureNameSnapshot", in: entity).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let session = CDFieldCheckSession(context: context)
            session.id = UUID()

            let finding = CDFieldCheckFinding(context: context)
            finding.id = UUID()
            finding.recordedAt = Date(timeIntervalSince1970: 100)
            finding.typeRawValue = FieldCheckFindingType.generalObservation.rawValue
            finding.severityRawValue = FieldCheckFindingSeverity.info.rawValue
            finding.statusRawValue = FieldCheckFindingStatus.open.rawValue
            finding.note = "Inspect fence"
            finding.session = session

            // A partially imported record has no name yet; do not fabricate one.
            finding.pastureNameSnapshot = nil
            XCTAssertNil(try FieldCheckMapper.makeFindingSnapshot(from: finding).pastureName)

            // An existing recorded name remains an immutable historical snapshot.
            finding.pastureNameSnapshot = "South Pasture"
            XCTAssertEqual(
                try FieldCheckMapper.makeFindingSnapshot(from: finding).pastureName,
                "South Pasture"
            )
            context.rollback()
        }
    }

    func testMissingImportedFindingSeverityIsRejectedWithoutInventingHistory() async throws {
        let model = try loadModel()
        let findingEntity = try entity(named: "FieldCheckFinding", in: model)
        XCTAssertTrue(try attribute(named: "severityRawValue", in: findingEntity).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let session = CDFieldCheckSession(context: context)
            session.id = UUID()
            let finding = CDFieldCheckFinding(context: context)
            finding.id = UUID()
            finding.session = session
            finding.typeRawValue = FieldCheckFindingType.generalObservation.rawValue
            finding.statusRawValue = FieldCheckFindingStatus.open.rawValue
            finding.severityRawValue = nil

            XCTAssertThrowsError(try FieldCheckMapper.makeFindingSnapshot(from: finding)) { error in
                XCTAssertEqual(
                    error as? CoreDataFieldCheckMappingError,
                    .invalidFindingSeverity(findingID: finding.id, value: "")
                )
            }
            XCTAssertNil(finding.severityRawValue)

            finding.severityRawValue = FieldCheckFindingSeverity.warning.rawValue
            XCTAssertEqual(
                try FieldCheckMapper.makeFindingSnapshot(from: finding).severity,
                .warning
            )
            context.rollback()
        }
    }

    func testMissingImportedFindingTypeFailsWithoutInventingAType() async throws {
        let model = try loadModel()
        let findingEntity = try entity(named: "FieldCheckFinding", in: model)
        XCTAssertTrue(try attribute(named: "typeRawValue", in: findingEntity).isOptional)

        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()
        try context.performAndWait {
            let session = CDFieldCheckSession(context: context)
            session.id = UUID()
            let finding = CDFieldCheckFinding(context: context)
            finding.id = UUID()
            finding.session = session
            finding.typeRawValue = nil

            XCTAssertThrowsError(try FieldCheckMapper.makeFindingSnapshot(from: finding)) { error in
                XCTAssertEqual(
                    error as? CoreDataFieldCheckMappingError,
                    .invalidFindingType(findingID: finding.id, value: nil)
                )
            }
            XCTAssertNil(finding.typeRawValue)

            finding.typeRawValue = FieldCheckFindingType.generalObservation.rawValue
            finding.severityRawValue = FieldCheckFindingSeverity.info.rawValue
            finding.statusRawValue = FieldCheckFindingStatus.open.rawValue
            finding.note = "Observed"
            finding.recordedAt = Date()
            let snapshot = try FieldCheckMapper.makeFindingSnapshot(from: finding)
            XCTAssertEqual(snapshot.type, .generalObservation)
            context.rollback()
        }
    }

    func testMissingFieldCheckFindingSessionFailsWithoutDereferencingIt() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()

        try context.performAndWait {
            let finding = CDFieldCheckFinding(context: context)
            finding.id = UUID()

            XCTAssertThrowsError(
                try FieldCheckMapper.makeFindingSnapshot(from: finding)
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataFieldCheckMappingError,
                    .missingFindingSession(findingID: finding.id)
                )
            }
            context.rollback()
        }
    }

    func testMissingFieldCheckRosterSessionFailsWithoutDereferencingIt() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let context = assembly.contextFactory.makeReadContext()

        try context.performAndWait {
            let check = CDFieldCheckAnimalCheck(context: context)
            check.id = UUID()

            XCTAssertThrowsError(
                try FieldCheckMapper.makeAnimalCheckSnapshot(from: check, needsAttention: false)
            ) { error in
                XCTAssertEqual(
                    error as? CoreDataFieldCheckMappingError,
                    .missingAnimalCheckSession(checkID: check.id)
                )
            }
            context.rollback()
        }
    }

    func testOldRequiredFindingRelationshipStoreLoadsWithoutCustomMigration() async throws {
        let currentModel = try loadModel()
        let previousModel = try XCTUnwrap(currentModel.copy() as? NSManagedObjectModel)
        let previousFinding = try entity(named: "FieldCheckFinding", in: previousModel)
        try relationship(named: "session", in: previousFinding).isOptional = false

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExistingFieldCheckStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("yaHerd.sqlite")
        let herdID = UUID()

        let sourceCoordinator = NSPersistentStoreCoordinator(managedObjectModel: previousModel)
        let sourceStore = try sourceCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = sourceCoordinator
        try context.performAndWait {
            let herd = NSEntityDescription.insertNewObject(forEntityName: "Herd", into: context)
            herd.setValue(herdID, forKey: "id")
            herd.setValue("Preserved Herd", forKey: "name")
            herd.setValue(Date(timeIntervalSince1970: 100), forKey: "createdAt")
            herd.setValue(Date(timeIntervalSince1970: 200), forKey: "updatedAt")
            try context.save()
        }
        context.reset()
        try sourceCoordinator.remove(sourceStore)

        let reopened = try await CoreDataPersistentContainer.load(storeURL: storeURL)
        let readContext = reopened.makeBackgroundContext()
        try await readContext.perform {
            let herds = try readContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Herd"))
            XCTAssertEqual(herds.count, 1)
            XCTAssertEqual(herds.first?.value(forKey: "id") as? UUID, herdID)
            XCTAssertEqual(herds.first?.value(forKey: "name") as? String, "Preserved Herd")
        }
    }

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

    func testCloudKitAnimalTagOwnerIsNullableInStorageWithAnInverse() throws {
        let model = try loadModel()
        let tag = try entity(named: "AnimalTag", in: model)
        let relationship = try relationship(named: "animal", in: tag)

        XCTAssertTrue(relationship.isOptional)
        XCTAssertEqual(relationship.destinationEntity?.name, "Animal")
        XCTAssertEqual(relationship.inverseRelationship?.name, "tags")
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
        XCTAssertTrue(try relationship(named: "session", in: finding).isOptional)
        XCTAssertTrue(try relationship(named: "session", in: check).isOptional)
    }

    func testWorkingSnapshotsAndOwnershipMatchBlueprint() throws {
        let model = try loadModel()
        let session = try entity(named: "WorkingSession", in: model)
        let queue = try entity(named: "WorkingQueueItem", in: model)

        XCTAssertTrue(try attribute(named: "sourcePastureIDSnapshot", in: session).isOptional)
        XCTAssertTrue(try attribute(named: "sourcePastureNameSnapshot", in: session).isOptional)

        XCTAssertTrue(try relationship(named: "session", in: queue).isOptional)
        let treatment = try entity(named: "WorkingTreatmentRecord", in: model)
        XCTAssertTrue(try relationship(named: "session", in: treatment).isOptional)

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

        for entityName in expectedClasses.keys {
            let entity = try entity(named: entityName, in: model)
            let expectedName = NSStringFromClass(try XCTUnwrap(expectedClasses[entityName]))
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
