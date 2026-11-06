import CoreData
import Foundation
import XCTest
@testable import yaHerd

/// Reconstructs the actual pre-CloudKit model contract (October 25 baseline)
/// without adding an old compiled model to the production bundle. The only
/// differences from the current model are optionality and introduced defaults.
final class CoreDataHistoricalStoreCompatibilityTests: XCTestCase {
    private static let historicalRequiredAttributes: [String: [String]] = [
        "Herd": ["id", "name", "createdAt", "updatedAt"],
        "TagColorDefinition": ["id", "name", "prefix", "red", "green", "blue", "alpha", "sortOrder", "isHidden", "isDefault", "createdAt", "updatedAt"],
        "AnimalStatusReference": ["id", "name", "baseStatusRawValue"],
        "PastureGroup": ["id", "name", "grazeDays", "restDays"],
        "Pasture": ["id", "name", "sortOrder"],
        "Animal": ["id", "editorRevision", "name", "sexRawValue", "birthDate", "statusRawValue", "isArchived", "distinguishingFeaturesData"],
        "AnimalTag": ["id", "number", "isPrimary", "isActive", "assignedAt"],
        "MovementRecord": ["id", "date"],
        "StatusRecord": ["id", "date", "oldStatusRawValue", "newStatusRawValue"],
        "HealthRecord": ["id", "date", "treatment"],
        "PregnancyCheck": ["id", "date", "resultRawValue"],
        "FieldCheckSession": ["id", "startedAt", "notes", "expectedHeadCountSnapshot", "quickCowCount", "quickHeiferCount", "quickCalfCount", "quickBullCount", "quickSteerCount", "pastureIDSnapshot", "pastureNameSnapshot"],
        "FieldCheckAnimalCheck": ["id", "animalIDSnapshot", "rosterTagNumberSnapshot", "animalNameSnapshot", "animalSexRawValueSnapshot", "animalTypeRawValueSnapshot", "wasExpectedAtStart"],
        "FieldCheckFinding": ["id", "recordedAt", "typeRawValue", "severityRawValue", "statusRawValue", "note", "pastureNameSnapshot"],
        "WorkingTreatmentTemplate": ["id", "name", "itemsData"],
        "WorkingSession": ["id", "date", "statusRawValue", "treatmentTemplateNameSnapshot", "plannedTreatmentsData", "sourcePastureIDSnapshot", "sourcePastureNameSnapshot"],
        "WorkingQueueItem": ["id", "statusRawValue", "animalIDSnapshot", "animalTagNumberSnapshot", "animalNameSnapshot", "animalSexRawValueSnapshot"],
        "WorkingTreatmentRecord": ["id", "date", "treatmentItemID", "itemNameSnapshot", "given", "animalIDSnapshot"]
    ]

    private static let historicalRequiredRelationships: [String: [String]] = [
        "TagColorDefinition": ["herd"],
        "AnimalStatusReference": ["herd"],
        "PastureGroup": ["herd"],
        "Pasture": ["herd"],
        "Animal": ["herd"],
        "AnimalTag": ["herd", "animal"],
        "MovementRecord": ["herd", "animal"],
        "StatusRecord": ["herd", "animal"],
        "HealthRecord": ["herd", "animal"],
        "PregnancyCheck": ["herd", "animal"],
        "FieldCheckSession": ["herd"],
        "FieldCheckAnimalCheck": ["herd", "session"],
        "FieldCheckFinding": ["herd", "session"],
        "WorkingTreatmentTemplate": ["herd"],
        "WorkingSession": ["herd"],
        "WorkingQueueItem": ["herd", "session"],
        "WorkingTreatmentRecord": ["herd", "session"]
    ]

    private static let cloudKitIntroducedDefaults: [String: [String]] = [
        "TagColorDefinition": ["prefix", "red", "green", "blue", "alpha", "sortOrder", "isHidden", "isDefault"],
        "PastureGroup": ["grazeDays", "restDays"],
        "Pasture": ["sortOrder"],
        "Animal": ["name", "sexRawValue", "isArchived"],
        "AnimalTag": ["isPrimary", "isActive"],
        "FieldCheckSession": ["notes", "expectedHeadCountSnapshot", "quickCowCount", "quickHeiferCount", "quickCalfCount", "quickBullCount", "quickSteerCount", "pastureNameSnapshot"],
        "FieldCheckAnimalCheck": ["rosterTagNumberSnapshot", "animalNameSnapshot", "animalSexRawValueSnapshot", "wasExpectedAtStart"],
        "FieldCheckFinding": ["note"],
        "WorkingSession": ["treatmentTemplateNameSnapshot"],
        "WorkingQueueItem": ["animalTagNumberSnapshot", "animalNameSnapshot", "animalSexRawValueSnapshot"],
        "WorkingTreatmentRecord": ["given"]
    ]

    private struct Record: Equatable, Sendable {
        let attributes: [String: String]
        let relationships: [String: [String]]
    }

    private typealias StoreSnapshot = [String: [String: Record]]

    private enum FixtureError: Error {
        case missingProperty(String, String)
        case unsupportedAttribute(String)
        case missingIdentity(String)
    }

    func testPreCloudKitFullGraphSurvivesCurrentProductionStoreOpen() async throws {
        let targetModel = try compiledModel()
        let sourceModel = try preCloudKitModel(from: targetModel)
        let targetEntityNames = Set(targetModel.entitiesByName.keys)
        let sourceEntityNames = Set(sourceModel.entitiesByName.keys)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yaHerd-HistoricalGraph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent(CoreDataPersistentContainer.storeFileName)

        // Write a historical SQLite store with the complete graph and the
        // original nonoptional relationships/defaults, not the new model.
        let sourceCoordinator = NSPersistentStoreCoordinator(managedObjectModel: sourceModel)
        let oldStore = try sourceCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil
        )
        let writeContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        writeContext.persistentStoreCoordinator = sourceCoordinator
        let expected = try writeContext.performAndWait { () throws -> StoreSnapshot in
            try Self.seedCompleteGraph(in: writeContext)
            try writeContext.save()
            return try Self.snapshot(in: writeContext, entityNames: sourceEntityNames)
        }
        XCTAssertEqual(expected.count, 18)
        XCTAssertEqual(expected["Animal"]?.count, 3)
        XCTAssertTrue(expected.values.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(
            expected["Animal"]?.values.filter { $0.attributes["isArchived"] == "1" }.count,
            1
        )

        writeContext.reset()
        try sourceCoordinator.remove(oldStore)

        // This is the production loader with inferred lightweight migration,
        // not a test-only NSPersistentStoreCoordinator destination.
        let persistent = try await CoreDataPersistentContainer.load(storeURL: storeURL)
        let readContext = persistent.makeBackgroundContext()
        try await readContext.perform {
            let actual = try Self.snapshot(in: readContext, entityNames: targetEntityNames)
            XCTAssertEqual(
                actual, expected,
                "Opening the pre-CloudKit store must preserve every UUID, persisted field and relationship across all 18 entities."
            )

            // The migrated store must remain writable without recreating rows.
            let herds = try readContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Herd"))
            let herd = try XCTUnwrap(herds.first)
            let originalID = try XCTUnwrap(herd.value(forKey: "id") as? UUID)
            herd.setValue("Post-upgrade Herd", forKey: "name")
            try readContext.save()

            let reloaded = try readContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Herd"))
            XCTAssertEqual(reloaded.count, 1)
            XCTAssertEqual(reloaded.first?.value(forKey: "id") as? UUID, originalID)
            XCTAssertEqual(reloaded.first?.value(forKey: "name") as? String, "Post-upgrade Herd")
            let afterSave = try Self.snapshot(in: readContext, entityNames: targetEntityNames)
            XCTAssertEqual(afterSave["Animal"], expected["Animal"])
            XCTAssertEqual(afterSave["AnimalTag"], expected["AnimalTag"])
            XCTAssertEqual(afterSave["MovementRecord"], expected["MovementRecord"])
        }
    }

    private func compiledModel() throws -> NSManagedObjectModel {
        let bundle = Bundle(for: CDHerd.self)
        let url = bundle.url(forResource: CoreDataPersistentContainer.modelName, withExtension: "momd")
            ?? bundle.url(forResource: CoreDataPersistentContainer.modelName, withExtension: "mom")
        return try XCTUnwrap(url.flatMap(NSManagedObjectModel.init(contentsOf:)))
    }

    private func preCloudKitModel(from target: NSManagedObjectModel) throws -> NSManagedObjectModel {
        let model = try XCTUnwrap(target.copy() as? NSManagedObjectModel)
        XCTAssertEqual(Set(model.entitiesByName.keys), Set(Self.historicalRequiredAttributes.keys))
        for (entityName, names) in Self.historicalRequiredAttributes {
            let entity = try XCTUnwrap(model.entitiesByName[entityName])
            for name in names {
                guard let attribute = entity.attributesByName[name] else {
                    throw FixtureError.missingProperty(entityName, name)
                }
                attribute.isOptional = false
            }
        }
        for (entityName, names) in Self.historicalRequiredRelationships {
            let entity = try XCTUnwrap(model.entitiesByName[entityName])
            for name in names {
                guard let relationship = entity.relationshipsByName[name] else {
                    throw FixtureError.missingProperty(entityName, name)
                }
                relationship.isOptional = false
            }
        }
        for (entityName, names) in Self.cloudKitIntroducedDefaults {
            let entity = try XCTUnwrap(model.entitiesByName[entityName])
            for name in names {
                guard let attribute = entity.attributesByName[name] else {
                    throw FixtureError.missingProperty(entityName, name)
                }
                attribute.defaultValue = nil
            }
        }
        return model
    }

    private static func seedCompleteGraph(in context: NSManagedObjectContext) throws {
        func make(_ entity: String, index: Int = 0) throws -> NSManagedObject {
            let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            for attribute in object.entity.attributesByName.values {
                let name = attribute.name
                let value: Any
                switch attribute.attributeType {
                case .UUIDAttributeType:
                    value = UUID()
                case .stringAttributeType:
                    value = "\(entity)-\(name)-\(index)"
                case .dateAttributeType:
                    value = Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60))
                case .integer64AttributeType:
                    value = NSNumber(value: index + 3)
                case .doubleAttributeType:
                    value = NSNumber(value: 0.75 + Double(index))
                case .booleanAttributeType:
                    value = NSNumber(value: name == "isArchived" && index == 1)
                case .binaryDataAttributeType:
                    value = Data("[]".utf8)
                default:
                    throw FixtureError.unsupportedAttribute("\(entity).\(name)")
                }
                object.setValue(value, forKey: name)
            }
            return object
        }

        let herd = try make("Herd")
        let pastureGroup = try make("PastureGroup")
        let pasture = try make("Pasture")
        let fieldSession = try make("FieldCheckSession")
        let workingSession = try make("WorkingSession")
        let sire = try make("Animal")
        let dam = try make("Animal", index: 1)
        let calf = try make("Animal", index: 2)

        var objects: [NSManagedObject] = [
            pastureGroup, pasture, fieldSession, workingSession, sire, dam, calf
        ]
        for entity in historicalRequiredAttributes.keys.sorted()
        where !["Herd", "PastureGroup", "Pasture", "FieldCheckSession", "WorkingSession", "Animal"].contains(entity) {
            objects.append(try make(entity))
        }

        for object in objects {
            if object.entity.relationshipsByName["herd"] != nil {
                object.setValue(herd, forKey: "herd")
            }
            if object.entity.relationshipsByName["animal"] != nil {
                object.setValue(calf, forKey: "animal")
            }
            if let session = object.entity.relationshipsByName["session"] {
                object.setValue(
                    session.destinationEntity?.name == "FieldCheckSession" ? fieldSession : workingSession,
                    forKey: "session"
                )
            }
        }

        pasture.setValue(pastureGroup, forKey: "group")
        calf.setValue(sire, forKey: "sire")
        calf.setValue(dam, forKey: "dam")
        calf.setValue(pasture, forKey: "currentPasture")
        fieldSession.setValue(pasture, forKey: "pasture")
        workingSession.setValue(pasture, forKey: "sourcePasture")
        for object in objects {
            for (name, related) in [
                ("currentPasture", pasture),
                ("collectedFromPasture", pasture),
                ("destinationPasture", pasture),
                ("sourcePasture", pasture)
            ] where object.entity.relationshipsByName[name] != nil && name != "currentPasture" {
                object.setValue(related, forKey: name)
            }
        }
    }

    private static func snapshot(
        in context: NSManagedObjectContext,
        entityNames: Set<String>
    ) throws -> StoreSnapshot {
        var result: StoreSnapshot = [:]
        for entityName in entityNames.sorted() {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            let objects = try context.fetch(request)
            var records: [String: Record] = [:]
            for object in objects {
                guard let id = object.value(forKey: "id") as? UUID else {
                    throw FixtureError.missingIdentity(entityName)
                }
                var attributes: [String: String] = [:]
                for attributeName in object.entity.attributesByName.keys {
                    attributes[attributeName] = scalarDescription(object.value(forKey: attributeName))
                }
                var relationships: [String: [String]] = [:]
                for (name, definition) in object.entity.relationshipsByName {
                    let value = object.value(forKey: name)
                    let related: [NSManagedObject]
                    if definition.isToMany {
                        related = (value as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
                    } else if let object = value as? NSManagedObject {
                        related = [object]
                    } else {
                        related = []
                    }
                    relationships[name] = try related.map {
                        guard let relatedID = $0.value(forKey: "id") as? UUID else {
                            throw FixtureError.missingIdentity($0.entity.name ?? "<unnamed>")
                        }
                        return relatedID.uuidString
                    }.sorted()
                }
                records[id.uuidString] = Record(
                    attributes: attributes,
                    relationships: relationships
                )
            }
            result[entityName] = records
        }
        return result
    }

    private static func scalarDescription(_ value: Any?) -> String {
        guard let value else { return "<nil>" }
        if let uuid = value as? UUID { return uuid.uuidString }
        if let date = value as? Date { return String(date.timeIntervalSinceReferenceDate) }
        if let data = value as? Data { return data.base64EncodedString() }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }
}
