@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataAnimalStatusReferenceRepositoryContractTests: XCTestCase {
    func testOptionsPreserveIdentityNameAndBaseStatus() async throws {
        let harness = try await makeHarness()
        try AnimalStatusReferenceRepositoryContract.assertOptionsPreserveIdentityNameAndBaseStatus(
            using: harness.fixture
        )
    }

    private func makeHarness() async throws -> StatusReferenceHarness {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = StatusReferenceCurrentHerdSelection()
        let herdID = UUID()
        selection.currentHerdID = herdID

        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Status Reference Contract Herd"
            herd.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            herd.updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
            try context.save()
        }

        return StatusReferenceHarness(
            fixture: AnimalStatusReferenceRepositoryContractFixture(
                makeReader: {
                    CoreDataAnimalStatusReferenceRepository(
                        selection: selection,
                        assembly: assembly
                    )
                },
                makeStatusReference: { name, baseStatus in
                    let id = UUID()
                    let context = try assembly.contextFactory.makeWriteContext()
                    try context.performAndWait {
                        guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                            throw HerdRepositoryError.missingHerd
                        }

                        let reference = CDAnimalStatusReference(context: context)
                        reference.id = id
                        reference.name = name
                        reference.baseStatusRawValue = baseStatus.rawValue
                        reference.herd = herd
                        try context.save()
                    }

                    return AnimalStatusReferenceOption(
                        id: id,
                        name: name,
                        baseStatus: baseStatus
                    )
                }
            )
        )
    }
}

@MainActor
private final class StatusReferenceCurrentHerdSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

@MainActor
private struct StatusReferenceHarness {
    let fixture: AnimalStatusReferenceRepositoryContractFixture
}
