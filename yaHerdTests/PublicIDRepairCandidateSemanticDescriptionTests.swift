import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairCandidateSemanticDescriptionTests: XCTestCase {
    func testDuplicateHerdChoicesWithSameNameExposeDifferentSemanticContext() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let duplicateHerdID = UUID(uuidString: "11111111-AAAA-4111-8111-111111111111")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let first = Herd(
            publicID: duplicateHerdID,
            name: "My Herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let second = Herd(
            publicID: duplicateHerdID,
            name: "My Herd",
            createdAt: timestamp.addingTimeInterval(60),
            updatedAt: timestamp.addingTimeInterval(60)
        )
        context.insert(first)
        context.insert(second)

        let animal = Animal(
            name: "",
            tagNumber: "202",
            birthDate: timestamp,
            sex: .female
        )
        animal.herd = second
        context.insert(animal)
        try context.save()

        let assessment = try await SwiftDataPublicIDRepairService(
            modelContainer: container
        ).scan()
        let issue = try XCTUnwrap(
            assessment.unresolvedReferences.first {
                $0.kind == .canonicalRecord && $0.entityType == .herd
            }
        )

        XCTAssertEqual(issue.candidates.count, 2)
        XCTAssertEqual(Set(issue.candidates.map(\.recordDescription)).count, 2)
        XCTAssertTrue(issue.candidates.allSatisfy { $0.detail.contains("Relationships:") })
        XCTAssertTrue(issue.candidates.allSatisfy { !$0.detail.localizedCaseInsensitiveContains("fingerprint") })
        XCTAssertTrue(issue.candidates.contains {
            $0.recordDescription.contains("Related animal")
                || $0.detail.contains("Related animal")
        })
    }

    func testSameNameLookupCandidatesExposeMeaningfulDifferingDetailsInPickerLabels() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateColorID = UUID(uuidString: "22222222-BBBB-4222-8222-222222222222")!
        let herd = Herd(name: "Lookup herd", createdAt: timestamp, updatedAt: timestamp)
        context.insert(herd)

        let first = TagColorDefinition(
            id: duplicateColorID,
            name: "Blue",
            rgba: RGBAColor(r: 0, g: 0, b: 1),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        first.herd = herd
        context.insert(first)
        let second = TagColorDefinition(
            id: duplicateColorID,
            name: "Blue",
            rgba: RGBAColor(r: 0.1, g: 0.2, b: 0.9),
            createdAt: timestamp.addingTimeInterval(60),
            updatedAt: timestamp.addingTimeInterval(60)
        )
        second.herd = herd
        context.insert(second)

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

        let assessment = try await SwiftDataPublicIDRepairService(
            modelContainer: container
        ).scan()
        let issue = try XCTUnwrap(
            assessment.unresolvedReferences.first { $0.fieldName == "tagColorID" }
        )

        XCTAssertEqual(issue.candidates.count, 2)
        XCTAssertEqual(Set(issue.candidates.map(\.recordDescription)).count, 2)
        XCTAssertTrue(issue.candidates.allSatisfy { $0.recordDescription.hasPrefix("Blue — ") })
        XCTAssertTrue(issue.candidates.allSatisfy { $0.detail.contains("Details:") })
        XCTAssertTrue(issue.candidates.allSatisfy { $0.detail.contains("Relationships:") })
        XCTAssertTrue(issue.candidates.allSatisfy { !$0.detail.localizedCaseInsensitiveContains("fingerprint") })
    }
}
