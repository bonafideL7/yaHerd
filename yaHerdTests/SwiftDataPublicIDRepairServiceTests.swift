import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor

@MainActor
final class SwiftDataPublicIDRepairServiceTests: XCTestCase {
    func testScanIncludesEveryShareableEntityType() async throws {
        let container = try TestSupport.makeModelContainer()
        let service = SwiftDataPublicIDRepairService(modelContainer: container)

        let assessment = try await service.scan()

        XCTAssertEqual(assessment.entities.map(\.entityType), PublicIDRepairEntityType.allCases)
        XCTAssertEqual(assessment.duplicateGroupCount, 0)
        XCTAssertEqual(assessment.duplicateRecordCount, 0)
    }

    func testRepairCreatesBackupRepairsRelationshipSnapshotsAndAllowsExport() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicatePastureID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let duplicateAnimalID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        let herd = Herd(name: "Repair test", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        let north = Pasture(publicID: duplicatePastureID, name: "North")
        north.herd = herd
        context.insert(north)
        let south = Pasture(publicID: duplicatePastureID, name: "South")
        south.herd = herd
        context.insert(south)

        let firstAnimal = Animal(
            publicID: duplicateAnimalID,
            name: "",
            tagNumber: "101",
            birthDate: timestamp,
            pasture: north,
            sex: .female
        )
        firstAnimal.herd = herd
        context.insert(firstAnimal)
        let secondAnimal = Animal(
            publicID: duplicateAnimalID,
            name: "",
            tagNumber: "202",
            birthDate: timestamp,
            pasture: south,
            sex: .female
        )
        secondAnimal.herd = herd
        context.insert(secondAnimal)

        let fieldSession = FieldCheckSession(
            startedAt: timestamp,
            pastureNameSnapshot: south.name,
            pastureID: duplicatePastureID,
            pasture: south
        )
        fieldSession.herd = herd
        context.insert(fieldSession)
        let check = FieldCheckAnimalCheck(
            animalIDSnapshot: duplicateAnimalID,
            rosterTagNumber: "202",
            animal: secondAnimal,
            session: fieldSession
        )
        check.herd = herd
        context.insert(check)
        let finding = FieldCheckFinding(
            recordedAt: timestamp,
            type: .generalObservation,
            severity: .warning,
            note: "Reference repair",
            animalIDSnapshot: duplicateAnimalID,
            sessionIDSnapshot: fieldSession.publicID,
            animal: secondAnimal,
            session: fieldSession
        )
        finding.herd = herd
        context.insert(finding)
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
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
        let repairedCheck = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FieldCheckAnimalCheck>()).first
        )
        XCTAssertEqual(repairedCheck.animalIDSnapshot, repairedCheck.animal?.publicID)
        let repairedFinding = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FieldCheckFinding>()).first
        )
        XCTAssertEqual(repairedFinding.animalIDSnapshot, repairedFinding.animal?.publicID)
        XCTAssertEqual(repairedFinding.sessionIDSnapshot, repairedFinding.session?.publicID)

        let sharingActor = SwiftDataHerdSharingActor(modelContainer: container)
        _ = try await sharingActor.makeExport(
            for: herd.toSummary(),
            storeDescription: "public-ID repair test"
        )
    }

    func testAmbiguousLookupRequiresChoiceAndAppliesSelectedCandidateInRepairTransaction() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateColorID = UUID(uuidString: "ABABABAB-ABAB-4BAB-8BAB-ABABABABABAB")!
        let herd = Herd(name: "Ambiguous herd", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        let blue = TagColorDefinition(
            id: duplicateColorID,
            name: "Blue",
            rgba: RGBAColor(r: 0, g: 0, b: 1),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        blue.herd = herd
        context.insert(blue)
        let green = TagColorDefinition(
            id: duplicateColorID,
            name: "Green",
            rgba: RGBAColor(r: 0, g: 1, b: 0),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        green.herd = herd
        context.insert(green)

        let animal = Animal(
            name: "",
            tagNumber: "404",
            tagColorID: duplicateColorID,
            birthDate: timestamp,
            sex: .female
        )
        animal.herd = herd
        context.insert(animal)
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
        let assessment = try await service.scan()
        let issue = try XCTUnwrap(assessment.unresolvedReferences.first)
        XCTAssertEqual(issue.fieldName, "tagColorID")
        XCTAssertEqual(issue.candidates.map(\.recordDescription).sorted(), ["Blue", "Green"])

        do {
            _ = try await service.repair()
            XCTFail("Expected repair without a deliberate choice to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("deliberate choice"))
        }

        let greenCandidate = try XCTUnwrap(
            issue.candidates.first { $0.recordDescription == "Green" }
        )
        let report = try await service.repair(
            resolutions: [
                PublicIDRepairReferenceResolution(
                    unresolvedReferenceID: issue.id,
                    selectedCandidateStableRecordIdentifier: greenCandidate.stableRecordIdentifier
                )
            ]
        )
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let verificationContext = ModelContext(container)
        let repairedGreen = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<TagColorDefinition>())
                .first { $0.name == "Green" }
        )
        let repairedAnimal = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<Animal>()).first
        )
        XCTAssertEqual(repairedAnimal.tagColorID, repairedGreen.id)
        XCTAssertTrue(report.referenceUpdates.contains {
            $0.fieldName == "tagColorID" && $0.repairedPublicID == repairedGreen.id
        })
    }

}
