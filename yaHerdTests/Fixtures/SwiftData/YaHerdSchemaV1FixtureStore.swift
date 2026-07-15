import Foundation
import SwiftData
@testable import yaHerd

@MainActor
enum YaHerdSchemaV1FixtureStore {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let herdID = UUID(uuidString: "18A41A91-5F6D-47D5-AEDC-2637F63CA5B8")!
    static let animalID = UUID(uuidString: "F955219E-4CD0-464B-863B-3865D56532D5")!
    static let pastureID = UUID(uuidString: "3963CE6D-46A6-4640-B1D0-7DDF165CA4A6")!
    static let tagID = UUID(uuidString: "9D31CBF9-58CC-47F8-896B-6DB2E2C1DC64")!
    static let featureID = UUID(uuidString: "991DAD1B-532A-4802-BEEC-A893A813B848")!

    static func create(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: YaHerdSchemaV1.self)
        let configuration = ModelConfiguration(
            ModelContainerFactory.storeName,
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        // Deliberately omit the current migration plan so this file is written
        // exactly as the released V1 schema would create it.
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext
        let fixtureDate = Date(timeIntervalSince1970: 1_704_067_200)

        let herd = YaHerdSchemaV1.Herd(
            publicID: herdID,
            name: "V1 Migration Fixture",
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            schemaVersion: 1
        )
        let pasture = YaHerdSchemaV1.Pasture(
            publicID: pastureID,
            name: "North Fixture Pasture",
            acreage: 80,
            usableAcreage: 72,
            targetAcresPerHead: 2,
            sortOrder: 0
        )
        let animal = YaHerdSchemaV1.Animal(
            publicID: animalID,
            name: "V1 Fixture Cow",
            tagNumber: "V1-001",
            birthDate: fixtureDate,
            status: .active,
            pasture: pasture,
            sex: .female,
            distinguishingFeatures: [
                DistinguishingFeature(
                    id: featureID,
                    description: "White blaze",
                    order: 0
                )
            ]
        )
        let tag = YaHerdSchemaV1.AnimalTag(
            publicID: tagID,
            number: "V1-001",
            isPrimary: true,
            assignedAt: fixtureDate,
            animal: animal
        )

        pasture.herd = herd
        animal.herd = herd
        tag.herd = herd

        context.insert(herd)
        context.insert(pasture)
        context.insert(animal)
        context.insert(tag)
        try context.save()
    }

    static func validate(in context: ModelContext) throws {
        let expectedHerdID = herdID
        let expectedAnimalID = animalID
        let expectedPastureID = pastureID
        let expectedTagID = tagID
        let herds = try context.fetch(
            FetchDescriptor<Herd>(
                predicate: #Predicate { $0.publicID == expectedHerdID }
            )
        )
        let animals = try context.fetch(
            FetchDescriptor<Animal>(
                predicate: #Predicate { $0.publicID == expectedAnimalID }
            )
        )
        let pastures = try context.fetch(
            FetchDescriptor<Pasture>(
                predicate: #Predicate { $0.publicID == expectedPastureID }
            )
        )
        let tags = try context.fetch(
            FetchDescriptor<AnimalTag>(
                predicate: #Predicate { $0.publicID == expectedTagID }
            )
        )

        guard let herd = herds.first,
              let animal = animals.first,
              let pasture = pastures.first,
              let tag = tags.first else {
            throw FixtureValidationError.missingSeedData
        }

        guard herd.name == "V1 Migration Fixture",
              herd.schemaVersion == 1,
              animal.tagNumber == "V1-001",
              animal.sex == .female,
              animal.distinguishingFeatures == [
                  DistinguishingFeature(
                      id: featureID,
                      description: "White blaze",
                      order: 0
                  )
              ],
              animal.herd?.publicID == herdID,
              animal.pasture?.publicID == pastureID,
              pasture.herd?.publicID == herdID,
              tag.isPrimary,
              tag.animal?.publicID == animalID,
              tag.herd?.publicID == herdID else {
            throw FixtureValidationError.invalidSeedData
        }
    }
}

private enum FixtureValidationError: Error {
    case missingSeedData
    case invalidSeedData
}
