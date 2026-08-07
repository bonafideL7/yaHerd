import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor

extension SwiftDataPublicIDRepairServiceTests {
    func testSameNameTreatmentUsesAmountUnitAndRouteWhenEvidenceIsUnique() async throws {
        let fixture = try makeTreatmentFixture(
            secondDose: WorkingTreatmentDose(
                amount: 5,
                unit: .milliliter,
                route: .intramuscular
            ),
            treatmentDose: WorkingTreatmentDose(
                amount: 5,
                unit: .milliliter,
                route: .intramuscular
            )
        )
        let service = SwiftDataPublicIDRepairService(modelContainer: fixture.container)

        let assessment = try await service.scan()
        XCTAssertFalse(assessment.unresolvedReferences.contains {
            $0.fieldName == "treatmentItemID"
        })

        let report = try await service.repair()
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }
        let verificationContext = ModelContext(fixture.container)
        let session = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkingSession>()).first
        )
        let selectedItem = try XCTUnwrap(
            session.protocolItems.first { $0.suggestedDose.amount == 5 }
        )
        let treatment = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkingTreatmentRecord>()).first
        )
        XCTAssertEqual(treatment.treatmentItemID, selectedItem.id)
    }

    func testSameNameTreatmentWithoutUniqueDoseRequiresDeliberateChoice() async throws {
        let sharedDose = WorkingTreatmentDose(
            amount: 2,
            unit: .milliliter,
            route: .subcutaneous
        )
        let fixture = try makeTreatmentFixture(
            firstDose: sharedDose,
            secondDose: sharedDose,
            treatmentDose: sharedDose
        )
        let service = SwiftDataPublicIDRepairService(modelContainer: fixture.container)
        let assessment = try await service.scan()
        let issue = try XCTUnwrap(
            assessment.unresolvedReferences.first { $0.fieldName == "treatmentItemID" }
        )
        XCTAssertEqual(issue.candidates.count, 2)

        do {
            _ = try await service.repair()
            XCTFail("Expected ambiguous same-name treatment to block repair")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("deliberate choice"))
        }

        let selectedCandidate = issue.candidates[1]
        let report = try await service.repair(
            resolutions: [
                PublicIDRepairReferenceResolution(
                    unresolvedReferenceID: issue.id,
                    selectedCandidateStableRecordIdentifier: selectedCandidate.stableRecordIdentifier
                )
            ]
        )
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }
        let verificationContext = ModelContext(fixture.container)
        let treatment = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkingTreatmentRecord>()).first
        )
        XCTAssertEqual(treatment.treatmentItemID, selectedCandidate.resultingPublicID)
    }

    func testStaleTreatmentIDStillPresentsEveryMatchingSessionItemCandidate() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateAnimalID = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
        let firstItemID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let secondItemID = UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!
        let staleItemID = UUID(uuidString: "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF")!
        let sharedDose = WorkingTreatmentDose(
            amount: 2,
            unit: .milliliter,
            route: .subcutaneous
        )
        let herd = Herd(name: "Stale treatment reference", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        let firstAnimal = Animal(
            publicID: duplicateAnimalID,
            name: "",
            tagNumber: "610",
            birthDate: timestamp,
            sex: .female
        )
        firstAnimal.herd = herd
        context.insert(firstAnimal)
        let secondAnimal = Animal(
            publicID: duplicateAnimalID,
            name: "",
            tagNumber: "611",
            birthDate: timestamp,
            sex: .female
        )
        secondAnimal.herd = herd
        context.insert(secondAnimal)

        let session = WorkingSession(
            date: timestamp,
            protocolName: "Stale treatment protocol",
            protocolItems: [
                WorkingProtocolItem(id: firstItemID, name: "Vaccine", suggestedDose: sharedDose),
                WorkingProtocolItem(id: secondItemID, name: "Vaccine", suggestedDose: sharedDose),
            ]
        )
        session.herd = herd
        context.insert(session)
        let treatment = WorkingTreatmentRecord(
            date: timestamp,
            treatmentItemID: staleItemID,
            itemName: "Vaccine",
            given: true,
            dose: sharedDose,
            animal: firstAnimal,
            session: session
        )
        treatment.herd = herd
        context.insert(treatment)
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
        let assessment = try await service.scan()
        let issue = try XCTUnwrap(
            assessment.unresolvedReferences.first { $0.fieldName == "treatmentItemID" }
        )
        XCTAssertEqual(Set(issue.candidates.map(\.resultingPublicID)), Set([firstItemID, secondItemID]))

        let selectedCandidate = try XCTUnwrap(
            issue.candidates.first { $0.resultingPublicID == secondItemID }
        )
        let report = try await service.repair(
            resolutions: [
                PublicIDRepairReferenceResolution(
                    unresolvedReferenceID: issue.id,
                    selectedCandidateStableRecordIdentifier: selectedCandidate.stableRecordIdentifier
                )
            ]
        )
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let verificationContext = ModelContext(container)
        let repairedTreatment = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WorkingTreatmentRecord>()).first
        )
        XCTAssertEqual(repairedTreatment.treatmentItemID, secondItemID)
    }

    func testGraphAwareCanonicalSelectionProducesIdenticalExportGraphAcrossInsertionOrders() async throws {
        let first = try makeGraphDeterminismContainer(reverseInsertion: false)
        let second = try makeGraphDeterminismContainer(reverseInsertion: true)
        let firstService = SwiftDataPublicIDRepairService(modelContainer: first)
        let secondService = SwiftDataPublicIDRepairService(modelContainer: second)

        let firstReport = try await firstService.repair()
        let secondReport = try await secondService.repair()
        defer {
            try? FileManager.default.removeItem(atPath: firstReport.backupPath)
            try? FileManager.default.removeItem(atPath: secondReport.backupPath)
        }
        XCTAssertEqual(
            Set(firstReport.replacements.map(\.replacementPublicID)),
            Set(secondReport.replacements.map(\.replacementPublicID))
        )

        let firstGraph = try await exportGraphSignature(from: first)
        let secondGraph = try await exportGraphSignature(from: second)
        XCTAssertEqual(firstGraph, secondGraph)
    }

    func testIndistinguishableDuplicateRecordsBlockInsteadOfUsingFetchOrder() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateID = UUID(uuidString: "91919191-9191-4191-8191-919191919191")!
        let herd = Herd(name: "Exact duplicates", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        for _ in 0..<2 {
            let animal = Animal(
                publicID: duplicateID,
                name: "Same",
                tagNumber: "900",
                birthDate: timestamp,
                sex: .female
            )
            animal.herd = herd
            context.insert(animal)
        }
        try context.save()

        let service = SwiftDataPublicIDRepairService(modelContainer: container)
        let assessment = try await service.scan()
        let issue = try XCTUnwrap(
            assessment.unresolvedReferences.first { $0.kind == .canonicalRecord }
        )

        XCTAssertTrue(assessment.hasDuplicates)
        XCTAssertTrue(issue.candidates.isEmpty)
        XCTAssertTrue(issue.reason.contains("no store-local identity"))
        await XCTAssertThrowsErrorAsync(try await service.repair())
    }

    func testTreatmentReplacementIDsAreStableAcrossTimeZones() async throws {
        let originalTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalTimeZone }
        let secondDose = WorkingTreatmentDose(
            amount: 5,
            unit: .milliliter,
            route: .intramuscular
        )

        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        let utcFixture = try makeTreatmentFixture(
            secondDose: secondDose,
            treatmentDose: secondDose
        )
        let utcReport = try await SwiftDataPublicIDRepairService(
            modelContainer: utcFixture.container
        ).repair()
        defer { try? FileManager.default.removeItem(atPath: utcReport.backupPath) }
        let utcReplacement = try XCTUnwrap(
            utcReport.replacements.first {
                $0.entityType == .workingSession && $0.retainedPublicID == utcFixture.duplicateID
            }?.replacementPublicID
        )

        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let pacificFixture = try makeTreatmentFixture(
            secondDose: secondDose,
            treatmentDose: secondDose
        )
        let pacificReport = try await SwiftDataPublicIDRepairService(
            modelContainer: pacificFixture.container
        ).repair()
        defer { try? FileManager.default.removeItem(atPath: pacificReport.backupPath) }
        let pacificReplacement = try XCTUnwrap(
            pacificReport.replacements.first {
                $0.entityType == .workingSession && $0.retainedPublicID == pacificFixture.duplicateID
            }?.replacementPublicID
        )

        XCTAssertEqual(utcReplacement, pacificReplacement)
    }

    func testRevisionMetadataStillWinsBeforeGraphFingerprint() async throws {
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
        context.insert(
            CollaborationRevisionRecord(
                key: CollaborationAggregateKey(type: .animal, publicID: duplicateID),
                herdPublicID: herd.publicID,
                metadata: CollaborationRevisionMetadata(
                    modifiedAt: timestamp.addingTimeInterval(60),
                    revision: 4,
                    modifiedByParticipantID: "test-participant",
                    modifiedByDeviceID: "test-device",
                    baseRevision: 3,
                    baseFieldValues: fields,
                    currentFieldValues: fields,
                    isDeleted: false
                )
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
    }

    private func XCTAssertThrowsErrorAsync(
        _ expression: @autoclosure () async throws -> Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}
