import SwiftData
import XCTest
@testable import yaHerd

/// Runs the persistence-neutral animal repository contract against the current SwiftData adapter.
/// Core Data migration work should add a second implementation-specific test class that invokes
/// the same `AnimalRepositoryContract` assertions unchanged.
@MainActor
final class SwiftDataAnimalRepositoryContractTests: XCTestCase {
    func testCreateUpdateAndReloadContract() throws {
        try AnimalRepositoryContract.assertCreateUpdateAndReload(using: makeFixture())
    }

    func testArchiveRestorePreservesHistoryContract() throws {
        try AnimalRepositoryContract.assertArchiveRestorePreservesHistory(using: makeFixture())
    }

    func testMovementUpdatesPastureAndTimelineContract() throws {
        try AnimalRepositoryContract.assertMovementUpdatesPastureAndTimeline(using: makeFixture())
    }

    func testTagLifecyclePreservesHistoryContract() throws {
        try AnimalRepositoryContract.assertTagLifecyclePreservesHistory(using: makeFixture())
    }

    func testParentRelationshipsSurviveReloadContract() throws {
        try AnimalRepositoryContract.assertParentRelationshipsSurviveReload(using: makeFixture())
    }

    func testHealthAndPregnancyRecordsSurviveReloadContract() throws {
        try AnimalRepositoryContract.assertHealthAndPregnancyRecordsSurviveReload(using: makeFixture())
    }

    func testDeleteRemovesAggregateContract() throws {
        try AnimalRepositoryContract.assertDeleteRemovesAggregate(using: makeFixture())
    }

    private func makeFixture() throws -> AnimalRepositoryContractFixture {
        let container = try TestSupport.makeModelContainer()

        return AnimalRepositoryContractFixture(
            makeAnimalRepository: {
                SwiftDataAnimalRepository(context: ModelContext(container))
            },
            makePastureRepository: {
                SwiftDataPastureRepository(context: ModelContext(container))
            }
        )
    }
}
