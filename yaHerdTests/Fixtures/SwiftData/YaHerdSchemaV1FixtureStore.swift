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
    static let treatmentTemplateID = UUID(uuidString: "892A6D44-B191-4EA7-81B2-B1D4E3DA84F8")!
    static let treatmentItemID = UUID(uuidString: "A05AC102-BEEF-4AFA-AF39-770B58C8B421")!
    static let workingSessionID = UUID(uuidString: "2D0DB468-EB8F-4D73-A55C-B25790F42757")!
    static let queueItemID = UUID(uuidString: "74707056-A030-4A48-B7EA-6461B0B24342")!
    static let treatmentRecordID = UUID(uuidString: "B93D61C9-C9E9-423C-8A19-925D719BA768")!
    static let revisionRecordID = UUID(uuidString: "E5E76852-ED60-46B6-9832-99A25B5A1F61")!
    static let deletedAggregateID = UUID(uuidString: "A8583D06-7D72-4BA8-B09B-A12D16764712")!

    static func create(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: YaHerdSchemaV1.self)
        let configuration = ModelConfiguration(
            ModelContainerFactory.storeName,
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        // V1 is still unreleased. Deliberately omit the migration plan so this
        // file is written by the exact V1 schema under test.
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext
        let fixtureDate = Date(timeIntervalSince1970: 1_704_067_200)
        let completedAt = fixtureDate.addingTimeInterval(3_600)

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
        let plannedTreatment = WorkingTreatmentPlanItem(
            id: treatmentItemID,
            name: "V1 Fixture Vaccine",
            suggestedDose: WorkingTreatmentDose(
                amount: 2,
                unit: .milliliter,
                route: .subcutaneous
            )
        )
        let template = YaHerdSchemaV1.WorkingProtocolTemplate(
            publicID: treatmentTemplateID,
            name: "V1 Fixture Treatments",
            items: [plannedTreatment]
        )
        let session = YaHerdSchemaV1.WorkingSession(
            publicID: workingSessionID,
            date: fixtureDate,
            status: .finished,
            sourcePasture: pasture,
            protocolName: template.name,
            protocolItems: [plannedTreatment],
            notes: "V1 Working Session fixture"
        )
        // Nonzero values prove that the deprecated fields remain readable in V1
        // while domain snapshots and sharing import do not depend on them.
        session.currentQueueIndex = 17
        let queueItem = YaHerdSchemaV1.WorkingQueueItem(
            publicID: queueItemID,
            queueOrder: 23,
            status: .done,
            collectedFromPasture: pasture,
            destinationPasture: pasture,
            workNotes: "Fixture work complete",
            animal: animal,
            session: session
        )
        queueItem.completedAt = completedAt
        let treatmentRecord = YaHerdSchemaV1.WorkingTreatmentRecord(
            publicID: treatmentRecordID,
            date: completedAt,
            treatmentItemID: treatmentItemID,
            itemName: plannedTreatment.name,
            given: true,
            dose: WorkingTreatmentDose(
                amount: 2.5,
                unit: .milliliter,
                route: .intramuscular
            ),
            animal: animal,
            session: session
        )
        let deletedRevision = YaHerdSchemaV1.CollaborationRevisionRecord(
            publicID: revisionRecordID,
            key: CollaborationAggregateKey(type: .animal, publicID: deletedAggregateID),
            herdPublicID: herdID,
            metadata: CollaborationRevisionMetadata(
                modifiedAt: completedAt,
                revision: 4,
                modifiedByParticipantID: "fixture-participant",
                modifiedByDeviceID: "fixture-device",
                baseRevision: 3,
                baseFieldValues: [:],
                currentFieldValues: [:],
                isDeleted: true
            )
        )

        pasture.herd = herd
        animal.herd = herd
        tag.herd = herd
        template.herd = herd
        session.herd = herd
        queueItem.herd = herd
        treatmentRecord.herd = herd

        context.insert(herd)
        context.insert(pasture)
        context.insert(animal)
        context.insert(tag)
        context.insert(template)
        context.insert(session)
        context.insert(queueItem)
        context.insert(treatmentRecord)
        context.insert(deletedRevision)
        try context.save()
    }

    static func validate(in context: ModelContext) throws {
        let herds = try context.fetch(FetchDescriptor<Herd>()).filter { $0.publicID == herdID }
        let animals = try context.fetch(FetchDescriptor<Animal>()).filter { $0.publicID == animalID }
        let pastures = try context.fetch(FetchDescriptor<Pasture>()).filter { $0.publicID == pastureID }
        let tags = try context.fetch(FetchDescriptor<AnimalTag>()).filter { $0.publicID == tagID }
        let templates = try context.fetch(FetchDescriptor<WorkingProtocolTemplate>())
            .filter { $0.publicID == treatmentTemplateID }
        let sessions = try context.fetch(FetchDescriptor<WorkingSession>())
            .filter { $0.publicID == workingSessionID }
        let queueItems = try context.fetch(FetchDescriptor<WorkingQueueItem>())
            .filter { $0.publicID == queueItemID }
        let treatmentRecords = try context.fetch(FetchDescriptor<WorkingTreatmentRecord>())
            .filter { $0.publicID == treatmentRecordID }
        let revisionRecords = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
            .filter { $0.publicID == revisionRecordID }

        guard let herd = herds.first,
              let animal = animals.first,
              let pasture = pastures.first,
              let tag = tags.first,
              let template = templates.first,
              let session = sessions.first,
              let queueItem = queueItems.first,
              let treatmentRecord = treatmentRecords.first,
              let deletedRevision = revisionRecords.first else {
            throw FixtureValidationError.missingSeedData
        }

        let expectedFeature = DistinguishingFeature(
            id: featureID,
            description: "White blaze",
            order: 0
        )
        guard herd.name == "V1 Migration Fixture",
              herd.schemaVersion == 1,
              animal.tagNumber == "V1-001",
              animal.sex == .female,
              animal.sexRawValue == Sex.female.rawValue,
              animal.status == .active,
              animal.statusRawValue == AnimalStatus.active.rawValue,
              animal.location == .pasture,
              animal.locationRawValue == AnimalLocation.pasture.rawValue,
              animal.distinguishingFeatures == [expectedFeature],
              animal.herd?.publicID == herdID,
              animal.pasture?.publicID == pastureID,
              pasture.herd?.publicID == herdID,
              tag.isPrimary,
              tag.animal?.publicID == animalID,
              tag.herd?.publicID == herdID,
              template.herd?.publicID == herdID,
              template.items.first?.id == treatmentItemID,
              template.items.first?.suggestedDose.amount == 2,
              template.items.first?.suggestedDose.unit == .milliliter,
              template.items.first?.suggestedDose.route == .subcutaneous,
              session.herd?.publicID == herdID,
              session.status == .finished,
              session.statusRawValue == WorkingSessionStatus.finished.rawValue,
              session.sourcePasture?.publicID == pastureID,
              session.protocolItems.first?.id == treatmentItemID,
              session.currentQueueIndex == 17,
              queueItem.herd?.publicID == herdID,
              queueItem.session?.publicID == workingSessionID,
              queueItem.animal?.publicID == animalID,
              queueItem.queueOrder == 23,
              treatmentRecord.herd?.publicID == herdID,
              treatmentRecord.session?.publicID == workingSessionID,
              treatmentRecord.animal?.publicID == animalID,
              treatmentRecord.treatmentItemID == treatmentItemID,
              treatmentRecord.doseAmount == 2.5,
              treatmentRecord.doseUnit == .milliliter,
              treatmentRecord.administrationRoute == .intramuscular,
              deletedRevision.aggregatePublicID == deletedAggregateID,
              deletedRevision.herdPublicID == herdID,
              deletedRevision.deletionTombstone,
              deletedRevision.metadata.isDeleted else {
            throw FixtureValidationError.invalidSeedData
        }

        let sessionSnapshot = WorkingMapper.makeSessionDetail(from: session)
        guard sessionSnapshot.plannedTreatments.first?.id == treatmentItemID,
              sessionSnapshot.queueItems.map(\.id) == [queueItemID] else {
            throw FixtureValidationError.invalidWorkingSessionSnapshot
        }
    }
}

private enum FixtureValidationError: Error {
    case missingSeedData
    case invalidSeedData
    case invalidWorkingSessionSnapshot
}
