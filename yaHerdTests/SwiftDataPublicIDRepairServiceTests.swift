import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class SwiftDataPublicIDRepairServiceTests: XCTestCase {
    func testScanIncludesEveryShareableEntityType() async throws {
        let container = try TestSupport.makeModelContainer()
        let service = SwiftDataPublicIDRepairService(modelContainer: container)

        let assessment = try await service.scan()

        XCTAssertEqual(
            assessment.entities.map(\.entityType),
            PublicIDRepairEntityType.allCases
        )
        XCTAssertEqual(assessment.duplicateGroupCount, 0)
        XCTAssertEqual(assessment.duplicateRecordCount, 0)
    }

    func testRepairCreatesBackupRepairsReferencesAndAllowsExport() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicatePastureID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let duplicateAnimalID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!

        let herd = Herd(name: "Repair test", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        let firstPasture = Pasture(publicID: duplicatePastureID, name: "North")
        firstPasture.herd = herd
        context.insert(firstPasture)
        let secondPasture = Pasture(publicID: duplicatePastureID, name: "South")
        secondPasture.herd = herd
        context.insert(secondPasture)

        let firstAnimal = Animal(
            publicID: duplicateAnimalID,
            name: "",
            tagNumber: "101",
            birthDate: timestamp,
            pasture: firstPasture,
            sex: .female
        )
        firstAnimal.herd = herd
        context.insert(firstAnimal)
        let secondAnimal = Animal(
            publicID: duplicateAnimalID,
            name: "",
            tagNumber: "202",
            birthDate: timestamp,
            pasture: secondPasture,
            sex: .female
        )
        secondAnimal.herd = herd
        context.insert(secondAnimal)

        let fieldCheckSession = FieldCheckSession(
            startedAt: timestamp,
            pastureNameSnapshot: secondPasture.name,
            pastureID: duplicatePastureID,
            pasture: secondPasture
        )
        fieldCheckSession.herd = herd
        context.insert(fieldCheckSession)

        let animalCheck = FieldCheckAnimalCheck(
            animalIDSnapshot: duplicateAnimalID,
            rosterTagNumber: secondAnimal.tagNumber,
            animal: secondAnimal,
            session: fieldCheckSession
        )
        animalCheck.herd = herd
        context.insert(animalCheck)

        let finding = FieldCheckFinding(
            recordedAt: timestamp,
            type: .generalObservation,
            severity: .warning,
            note: "Reference repair",
            animalIDSnapshot: duplicateAnimalID,
            sessionIDSnapshot: fieldCheckSession.publicID,
            animal: secondAnimal,
            session: fieldCheckSession
        )
        finding.herd = herd
        context.insert(finding)
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
        let assessment = try await service.scan()
        XCTAssertEqual(assessment.duplicateGroupCount, 2)
        XCTAssertEqual(assessment.duplicateRecordCount, 2)

        let report = try await service.repair()
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: report.backupPath))
        XCTAssertEqual(report.repairedRecordCount, 2)
        XCTAssertTrue(report.validationPassed)

        let verificationContext = ModelContext(container)
        let repairedPastures = try verificationContext.fetch(FetchDescriptor<Pasture>())
        let repairedAnimals = try verificationContext.fetch(FetchDescriptor<Animal>())
        XCTAssertEqual(Set(repairedPastures.map(\.publicID)).count, repairedPastures.count)
        XCTAssertEqual(Set(repairedAnimals.map(\.publicID)).count, repairedAnimals.count)

        let repairedSession = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FieldCheckSession>()).first
        )
        XCTAssertEqual(repairedSession.pastureID, repairedSession.pasture?.publicID)

        let repairedAnimalCheck = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FieldCheckAnimalCheck>()).first
        )
        XCTAssertEqual(repairedAnimalCheck.animalIDSnapshot, repairedAnimalCheck.animal?.publicID)

        let repairedFinding = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FieldCheckFinding>()).first
        )
        XCTAssertEqual(repairedFinding.animalIDSnapshot, repairedFinding.animal?.publicID)
        XCTAssertEqual(repairedFinding.sessionIDSnapshot, repairedFinding.session?.publicID)

        let sharingActor = SwiftDataHerdSharingActor(modelContainer: container)
        let repairedHerd = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<Herd>()).first
        )
        _ = try await sharingActor.makeExport(
            for: repairedHerd.toSummary(),
            storeDescription: "public-ID repair test"
        )
    }

    func testRepairUpdatesStoredLookupReferencesUsingHerdScope() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateColorID = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
        let duplicateStatusID = UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!

        let firstHerd = Herd(name: "First herd", createdAt: timestamp, updatedAt: timestamp)
        let secondHerd = Herd(name: "Second herd", createdAt: timestamp, updatedAt: timestamp)
        context.insert(firstHerd)
        context.insert(secondHerd)

        let retainedColor = TagColorDefinition(
            id: duplicateColorID,
            name: "Retained color",
            rgba: RGBAColor(r: 1, g: 0, b: 0, a: 1),
            createdAt: timestamp,
            updatedAt: timestamp.addingTimeInterval(60)
        )
        retainedColor.herd = firstHerd
        context.insert(retainedColor)
        let reassignedColor = TagColorDefinition(
            id: duplicateColorID,
            name: "Reassigned color",
            rgba: RGBAColor(r: 0, g: 0, b: 1, a: 1),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        reassignedColor.herd = secondHerd
        context.insert(reassignedColor)

        let retainedStatus = AnimalStatusReference(
            id: duplicateStatusID,
            name: "Retained status",
            baseStatus: .active,
            createdAt: timestamp.addingTimeInterval(60)
        )
        retainedStatus.herd = firstHerd
        context.insert(retainedStatus)
        let reassignedStatus = AnimalStatusReference(
            id: duplicateStatusID,
            name: "Reassigned status",
            baseStatus: .sold,
            createdAt: timestamp
        )
        reassignedStatus.herd = secondHerd
        context.insert(reassignedStatus)

        let animal = Animal(
            name: "",
            tagNumber: "212",
            tagColorID: duplicateColorID,
            birthDate: timestamp,
            statusReferenceID: duplicateStatusID,
            sex: .female
        )
        animal.herd = secondHerd
        context.insert(animal)

        let tag = AnimalTag(
            number: "212",
            colorID: duplicateColorID,
            isPrimary: true,
            animal: animal
        )
        tag.herd = secondHerd
        context.insert(tag)

        let statusRecord = StatusRecord(
            date: timestamp,
            oldStatus: .active,
            newStatus: .sold,
            oldStatusReferenceID: duplicateStatusID,
            newStatusReferenceID: duplicateStatusID,
            animal: animal
        )
        statusRecord.herd = secondHerd
        context.insert(statusRecord)

        let fieldCheckSession = FieldCheckSession(startedAt: timestamp)
        fieldCheckSession.herd = secondHerd
        context.insert(fieldCheckSession)
        let animalCheck = FieldCheckAnimalCheck(
            rosterTagNumber: "212",
            rosterTagColorID: duplicateColorID,
            damRosterTagColorID: duplicateColorID,
            animal: animal,
            session: fieldCheckSession
        )
        animalCheck.herd = secondHerd
        context.insert(animalCheck)
        let finding = FieldCheckFinding(
            recordedAt: timestamp,
            type: .generalObservation,
            severity: .warning,
            animalDisplayTagColorIDSnapshot: duplicateColorID,
            animal: animal,
            session: fieldCheckSession
        )
        finding.herd = secondHerd
        context.insert(finding)
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
        let report = try await service.repair()
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let verificationContext = ModelContext(container)
        let colors = try verificationContext.fetch(FetchDescriptor<TagColorDefinition>())
        let statuses = try verificationContext.fetch(FetchDescriptor<AnimalStatusReference>())
        let secondColor = try XCTUnwrap(colors.first { $0.herd?.name == "Second herd" })
        let secondStatus = try XCTUnwrap(statuses.first { $0.herd?.name == "Second herd" })
        XCTAssertNotEqual(secondColor.id, duplicateColorID)
        XCTAssertNotEqual(secondStatus.id, duplicateStatusID)

        let repairedAnimal = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<Animal>()).first
        )
        XCTAssertEqual(repairedAnimal.tagColorID, secondColor.id)
        XCTAssertEqual(repairedAnimal.statusReferenceID, secondStatus.id)

        let repairedTag = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<AnimalTag>()).first
        )
        XCTAssertEqual(repairedTag.colorID, secondColor.id)

        let repairedStatusRecord = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<StatusRecord>()).first
        )
        XCTAssertEqual(repairedStatusRecord.oldStatusReferenceID, secondStatus.id)
        XCTAssertEqual(repairedStatusRecord.newStatusReferenceID, secondStatus.id)

        let repairedCheck = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FieldCheckAnimalCheck>()).first
        )
        XCTAssertEqual(repairedCheck.rosterTagColorID, secondColor.id)
        XCTAssertEqual(repairedCheck.damRosterTagColorID, secondColor.id)

        let repairedFinding = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FieldCheckFinding>()).first
        )
        XCTAssertEqual(repairedFinding.animalDisplayTagColorIDSnapshot, secondColor.id)

        let updatedFields = Set(report.referenceUpdates.map(\.fieldName))
        XCTAssertTrue(updatedFields.isSuperset(of: [
            "tagColorID",
            "statusReferenceID",
            "colorID",
            "oldStatusReferenceID",
            "newStatusReferenceID",
            "rosterTagColorID",
            "damRosterTagColorID",
            "animalDisplayTagColorIDSnapshot",
        ]))
    }

    func testRepairReassignsDuplicateTreatmentItemsAndUpdatesTreatmentReferences() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateTreatmentItemID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!

        let herd = Herd(name: "Treatment item repair", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)
        let animal = Animal(
            name: "",
            tagNumber: "303",
            birthDate: timestamp,
            sex: .female
        )
        animal.herd = herd
        context.insert(animal)

        let session = WorkingSession(
            date: timestamp,
            protocolName: "Duplicate item protocol",
            protocolItems: [
                WorkingProtocolItem(id: duplicateTreatmentItemID, name: "Vaccine A"),
                WorkingProtocolItem(id: duplicateTreatmentItemID, name: "Vaccine B"),
            ]
        )
        session.herd = herd
        context.insert(session)

        let treatment = WorkingTreatmentRecord(
            date: timestamp,
            treatmentItemID: duplicateTreatmentItemID,
            itemName: "Vaccine B",
            given: true,
            animal: animal,
            session: session
        )
        treatment.herd = herd
        context.insert(treatment)
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
        let assessment = try await service.scan()
        XCTAssertTrue(assessment.hasDuplicates)
        XCTAssertEqual(
            assessment.entities.first { $0.entityType == .workingSession }?.duplicateRecordCount,
            1
        )

        let report = try await service.repair()
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let verificationContext = ModelContext(container)
        let repairedSession = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkingSession>()).first
        )
        XCTAssertEqual(Set(repairedSession.protocolItems.map(\.id)).count, 2)
        let vaccineB = try XCTUnwrap(
            repairedSession.protocolItems.first { $0.name == "Vaccine B" }
        )
        XCTAssertNotEqual(vaccineB.id, duplicateTreatmentItemID)

        let repairedTreatment = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkingTreatmentRecord>()).first
        )
        XCTAssertEqual(repairedTreatment.treatmentItemID, vaccineB.id)
        XCTAssertTrue(report.referenceUpdates.contains {
            $0.fieldName == "treatmentItemID"
                && $0.repairedPublicID == vaccineB.id
        })
    }

    func testRevisionMetadataSelectsCanonicalRecordDeterministically() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
        let herd = Herd(name: "Canonical test", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        let first = Animal(
            publicID: duplicateID,
            name: "",
            tagNumber: "100",
            birthDate: timestamp,
            sex: .female
        )
        first.herd = herd
        context.insert(first)
        let revisionCanonical = Animal(
            publicID: duplicateID,
            name: "",
            tagNumber: "200",
            birthDate: timestamp,
            sex: .female
        )
        revisionCanonical.herd = herd
        context.insert(revisionCanonical)
        try context.save()

        let fields = CollaborationFieldSnapshotProvider.snapshot(for: revisionCanonical)
        let metadata = CollaborationRevisionMetadata(
            modifiedAt: timestamp.addingTimeInterval(60),
            revision: 4,
            modifiedByParticipantID: "test-participant",
            modifiedByDeviceID: "test-device",
            baseRevision: 3,
            baseFieldValues: fields,
            currentFieldValues: fields,
            isDeleted: false
        )
        context.insert(
            CollaborationRevisionRecord(
                key: CollaborationAggregateKey(type: .animal, publicID: duplicateID),
                herdPublicID: herd.publicID,
                metadata: metadata
            )
        )
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
        let report = try await service.repair()
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let verificationContext = ModelContext(container)
        let animals = try verificationContext.fetch(FetchDescriptor<Animal>())
        let retained = try XCTUnwrap(animals.first { $0.publicID == duplicateID })
        XCTAssertEqual(retained.tagNumber, "200")
        XCTAssertEqual(Set(animals.map(\.publicID)).count, 2)
    }
}
