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

}
