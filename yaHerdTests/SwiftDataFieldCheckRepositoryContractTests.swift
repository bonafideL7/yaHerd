import SwiftData
import XCTest
@testable import yaHerd

/// Temporary Phase 0 runner for the permanent persistence-neutral Field Check repository contract.
///
/// This runner characterizes behavior the current SwiftData implementation already provides.
/// Delete this file with the SwiftData stack after the Core Data repository runs the same
/// `FieldCheckRepositoryContract` assertions unchanged.
@MainActor
final class SwiftDataFieldCheckRepositoryContractTests: XCTestCase {
    func testSessionCreationAndReadProjectionsContract() throws {
        try FieldCheckRepositoryContract.assertSessionCreationAndReadProjections(using: makeFixture())
    }

    func testMutableCountsNotesAndRosterStateSurviveReloadContract() throws {
        try FieldCheckRepositoryContract.assertMutableCountsNotesAndRosterStateSurviveReload(using: makeFixture())
    }

    func testTrackedAnimalAdditionPersistsRosterAndDestinationContract() throws {
        try FieldCheckRepositoryContract.assertTrackedAnimalAdditionPersistsRosterAndDestination(using: makeFixture())
    }

    func testFindingLifecycleAndOpenFindingReaderContract() throws {
        try FieldCheckRepositoryContract.assertFindingLifecycleAndOpenFindingReader(using: makeFixture())
    }

    func testHistoricalSnapshotsSurviveLiveRecordChangesContract() throws {
        try FieldCheckRepositoryContract.assertHistoricalSnapshotsSurviveLiveRecordChanges(using: makeFixture())
    }

    func testCompletionReopenAndEditLockingContract() throws {
        try FieldCheckRepositoryContract.assertCompletionReopenAndEditLocking(using: makeFixture())
    }

    func testMissingRecordErrorsContract() throws {
        try FieldCheckRepositoryContract.assertMissingRecordErrors(using: makeFixture())
    }

    private func makeFixture() throws -> FieldCheckRepositoryContractFixture {
        let container = try TestSupport.makeModelContainer()

        return FieldCheckRepositoryContractFixture(
            makeFieldCheckRepository: {
                SwiftDataFieldCheckRepository(context: ModelContext(container))
            },
            makeAnimalRepository: {
                SwiftDataAnimalRepository(context: ModelContext(container))
            },
            makePastureRepository: {
                SwiftDataPastureRepository(context: ModelContext(container))
            },
            makeTagColorRepository: {
                SwiftDataTagColorRepository(context: ModelContext(container))
            }
        )
    }
}
