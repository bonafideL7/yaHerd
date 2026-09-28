@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataPastureRepositoryContractTests: XCTestCase {
    func testCreateUpdateAndReload() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertCreateUpdateAndReload(using: harness.fixture)
    }

    func testListOrderingAndSubsetReorder() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertListOrderingAndSubsetReorder(using: harness.fixture)
    }

    func testReferenceDataAndNameLookup() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertReferenceDataAndNameLookup(using: harness.fixture)
    }

    func testGroupLifecycleAndPastureAssignment() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertGroupLifecycleAndPastureAssignment(using: harness.fixture)
    }

    func testGroupListOrderingAndPastureCounts() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertGroupListOrderingAndPastureCounts(using: harness.fixture)
    }

    func testGroupNameLookupAndDuplicateProtection() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertGroupNameLookupAndDuplicateProtection(using: harness.fixture)
    }

    func testIDValidationRejectsDuplicatesAndMissingRecords() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertIDValidationRejectsDuplicatesAndMissingRecords(using: harness.fixture)
    }

    func testDeleteRemovesPasture() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryContract.assertDeleteRemovesPasture(using: harness.fixture)
    }

    func testClearingOptionalStockingFieldsPersists() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryEdgeCaseContract.assertClearingOptionalStockingFieldsPersists(
            using: harness.fixture
        )
    }

    func testPersistedGrazingDate() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryEdgeCaseContract.assertPersistedGrazingDate(
            using: harness.fixture,
            markPastureGrazed: harness.markPastureGrazed
        )
    }

    func testNameLookupExcludesOnlyRequestedPasture() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryEdgeCaseContract.assertNameLookupExcludesOnlyRequestedPasture(
            using: harness.fixture
        )
    }

    func testGroupNameLookupExcludesOnlyRequestedGroup() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryEdgeCaseContract.assertGroupNameLookupExcludesOnlyRequestedGroup(
            using: harness.fixture
        )
    }

    func testDirectReassignmentBetweenGroupsUpdatesBothInverses() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryEdgeCaseContract.assertDirectReassignmentBetweenGroupsUpdatesBothInverses(
            using: harness.fixture
        )
    }

    func testUpdatingGroupPreservesPastureMembership() async throws {
        let harness = try await makeHarness()
        try await PastureRepositoryEdgeCaseContract.assertUpdatingGroupPreservesPastureMembership(
            using: harness.fixture
        )
    }

    private func makeHarness() async throws -> PastureHarness {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = PastureCurrentHerdSelection()
        let herdID = UUID()
        selection.currentHerdID = herdID

        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Pasture Contract Herd"
            herd.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            herd.updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
            try context.save()
        }

        let fixture = PastureRepositoryContractFixture(
            makePastureRepository: {
                CoreDataPastureRepository(selection: selection, assembly: assembly)
            },
            makeAnimalRepository: {
                fatalError("Animal-dependent pasture contracts run with the Milestone 5 Core Data runner.")
            },
            makeTagColorRepository: {
                fatalError("Tag-color-dependent pasture contracts run after the Core Data tag-color slice.")
            }
        )

        return PastureHarness(
            fixture: fixture,
            markPastureGrazed: { pastureID, date in
                let context = try assembly.contextFactory.makeWriteContext()
                try context.performAndWait {
                    guard let pasture = try assembly.lookup.herdOwned(
                        CDPasture.self,
                        id: pastureID,
                        herdID: herdID,
                        in: context
                    ) else {
                        throw PastureValidationError.pastureNotFound
                    }
                    pasture.lastGrazedDate = date
                    try context.save()
                }
            }
        )
    }
}

@MainActor
private final class PastureCurrentHerdSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

@MainActor
private struct PastureHarness {
    let fixture: PastureRepositoryContractFixture
    let markPastureGrazed: (UUID, Date) throws -> Void
}
