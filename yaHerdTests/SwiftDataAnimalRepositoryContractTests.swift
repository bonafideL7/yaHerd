import SwiftData
import XCTest
@testable import yaHerd

/// Temporary Phase 0 runner for the permanent persistence-neutral animal repository contract.
///
/// This runner characterizes behavior the current SwiftData implementation already provides.
/// Delete this file with the SwiftData stack after the Core Data repository runs the same
/// `AnimalRepositoryContract` assertions unchanged.
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
