import SwiftData
import XCTest
@testable import yaHerd

/// Characterization runner for the current SwiftData pasture repository.
///
/// The permanent contracts live under `RepositoryContracts` and should later run unchanged against
/// the production Core Data implementation.
@MainActor
final class SwiftDataPastureRepositoryContractTests: XCTestCase {
    func testCreateUpdateAndReloadContract() throws {
        try PastureRepositoryContract.assertCreateUpdateAndReload(using: makeFixture())
    }

    func testClearingOptionalStockingFieldsPersistsContract() throws {
        try PastureRepositoryEdgeCaseContract.assertClearingOptionalStockingFieldsPersists(
            using: makeFixture()
        )
    }

    func testPersistedGrazingDateContract() throws {
        let container = try TestSupport.makeModelContainer()
        try PastureRepositoryEdgeCaseContract.assertPersistedGrazingDate(
            using: makeFixture(container: container),
            markPastureGrazed: { id, date in
                try SwiftDataDashboardRepository(context: ModelContext(container))
                    .markPastureGrazedToday(id: id, on: date)
            }
        )
    }

    func testListOrderingAndSubsetReorderContract() throws {
        try PastureRepositoryContract.assertListOrderingAndSubsetReorder(using: makeFixture())
    }

    func testReferenceDataAndNameLookupContract() throws {
        try PastureRepositoryContract.assertReferenceDataAndNameLookup(using: makeFixture())
    }

    func testNameLookupExcludesOnlyRequestedPastureContract() throws {
        try PastureRepositoryEdgeCaseContract.assertNameLookupExcludesOnlyRequestedPasture(
            using: makeFixture()
        )
    }

    func testResidentAnimalsAndActiveCountContract() throws {
        try PastureRepositoryContract.assertResidentAnimalsAndActiveCount(using: makeFixture())
    }

    func testGroupLifecycleAndPastureAssignmentContract() throws {
        try PastureRepositoryContract.assertGroupLifecycleAndPastureAssignment(using: makeFixture())
    }

    func testDirectReassignmentBetweenGroupsUpdatesBothInversesContract() throws {
        try PastureRepositoryEdgeCaseContract.assertDirectReassignmentBetweenGroupsUpdatesBothInverses(
            using: makeFixture()
        )
    }

    func testGroupListOrderingAndPastureCountsContract() throws {
        try PastureRepositoryContract.assertGroupListOrderingAndPastureCounts(using: makeFixture())
    }

    func testGroupNameLookupAndDuplicateProtectionContract() throws {
        try PastureRepositoryContract.assertGroupNameLookupAndDuplicateProtection(using: makeFixture())
    }

    func testGroupNameLookupExcludesOnlyRequestedGroupContract() throws {
        try PastureRepositoryEdgeCaseContract.assertGroupNameLookupExcludesOnlyRequestedGroup(
            using: makeFixture()
        )
    }

    func testIDValidationRejectsDuplicatesAndMissingRecordsContract() throws {
        try PastureRepositoryContract.assertIDValidationRejectsDuplicatesAndMissingRecords(using: makeFixture())
    }

    func testDeleteRemovesPastureContract() throws {
        try PastureRepositoryContract.assertDeleteRemovesPasture(using: makeFixture())
    }

    func testProductionDeletionWorkflowPreservesHistoryContract() throws {
        try PastureDeletionWorkflowContract.assertDeleteMovesResidentsAndArchivesFieldCheckHistory(
            using: makeDeletionWorkflowFixture()
        )
    }

    private func makeFixture() throws -> PastureRepositoryContractFixture {
        let container = try TestSupport.makeModelContainer()
        return makeFixture(container: container)
    }

    private func makeFixture(container: ModelContainer) -> PastureRepositoryContractFixture {
        PastureRepositoryContractFixture(
            makePastureRepository: {
                SwiftDataPastureRepository(context: ModelContext(container))
            },
            makeAnimalRepository: {
                SwiftDataAnimalRepository(context: ModelContext(container))
            },
            makeTagColorRepository: {
                SwiftDataTagColorRepository(context: ModelContext(container))
            }
        )
    }

    private func makeDeletionWorkflowFixture() throws -> PastureDeletionWorkflowContractFixture {
        let container = try TestSupport.makeModelContainer()

        return PastureDeletionWorkflowContractFixture(
            makePastureRepository: {
                SwiftDataPastureRepository(context: ModelContext(container))
            },
            makeAnimalRepository: {
                SwiftDataAnimalRepository(context: ModelContext(container))
            },
            makeFieldCheckRepository: {
                SwiftDataFieldCheckRepository(context: ModelContext(container))
            },
            deletePastures: { ids, archivedAt in
                // Production SwiftData wiring shares one context across the three collaborators.
                // `archiveSessionsForDeletedPastures` deliberately relies on the pasture delete's
                // final save to persist its archive marker, so the characterization runner does too.
                let context = ModelContext(container)
                try DeletePasturesUseCase(
                    pastureRepository: SwiftDataPastureRepository(context: context),
                    animalRepository: SwiftDataAnimalRepository(context: context),
                    fieldCheckRepository: SwiftDataFieldCheckRepository(context: context)
                ).execute(ids: ids, archivedAt: archivedAt)
            }
        )
    }
}
