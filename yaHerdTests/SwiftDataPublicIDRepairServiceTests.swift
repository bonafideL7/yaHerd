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
