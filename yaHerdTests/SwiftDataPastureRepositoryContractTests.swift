import SwiftData
import XCTest
@testable import yaHerd

/// Characterization runner for the current SwiftData pasture repository.
///
/// The permanent contract lives in `RepositoryContracts/PastureRepositoryContract.swift` and should
/// later run unchanged against the production Core Data repository.
@MainActor
final class SwiftDataPastureRepositoryContractTests: XCTestCase {
    func testCreateUpdateAndReloadContract() throws {
        try PastureRepositoryContract.assertCreateUpdateAndReload(using: makeFixture())
    }

    func testListOrderingAndSubsetReorderContract() throws {
        try PastureRepositoryContract.assertListOrderingAndSubsetReorder(using: makeFixture())
    }

    func testReferenceDataAndNameLookupContract() throws {
        try PastureRepositoryContract.assertReferenceDataAndNameLookup(using: makeFixture())
    }

    func testResidentAnimalsAndActiveCountContract() throws {
        try PastureRepositoryContract.assertResidentAnimalsAndActiveCount(using: makeFixture())
    }

    func testGroupLifecycleAndPastureAssignmentContract() throws {
        try PastureRepositoryContract.assertGroupLifecycleAndPastureAssignment(using: makeFixture())
    }

    func testGroupNameLookupAndDuplicateProtectionContract() throws {
        try PastureRepositoryContract.assertGroupNameLookupAndDuplicateProtection(using: makeFixture())
    }

    func testIDValidationRejectsDuplicatesAndMissingRecordsContract() throws {
        try PastureRepositoryContract.assertIDValidationRejectsDuplicatesAndMissingRecords(using: makeFixture())
    }

    func testDeleteRemovesPastureContract() throws {
        try PastureRepositoryContract.assertDeleteRemovesPasture(using: makeFixture())
    }

    private func makeFixture() throws -> PastureRepositoryContractFixture {
        let container = try TestSupport.makeModelContainer()

        return PastureRepositoryContractFixture(
            makePastureRepository: {
                SwiftDataPastureRepository(context: ModelContext(container))
            },
            makeAnimalRepository: {
                SwiftDataAnimalRepository(context: ModelContext(container))
            }
        )
    }
}
