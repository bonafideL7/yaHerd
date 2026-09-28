@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataHerdRepositoryContractTests: XCTestCase {
    func testMissingReadAndRenameDoNotBootstrapHerd() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertMissingReadAndRenameDoNotBootstrapHerd(
            using: harness.fixture
        )
    }

    func testRenameNormalizesNamePreservesIdentityAndSurvivesReload() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertRenameNormalizesNamePreservesIdentityAndSurvivesReload(
            using: harness.fixture
        )
    }

    func testRenamePersistenceFailureRollsBackAndRepositoryRecovers() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertRenamePersistenceFailureRollsBackAndRepositoryRecovers(
            using: harness.fixture,
            failureInjection: harness.failureInjection
        )
    }

    func testEmptyRenameIsRejectedWithoutBootstrapping() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertEmptyRenameIsRejectedWithoutBootstrapping(
            using: harness.fixture
        )
    }

    func testEmptyRenameDoesNotMutateExistingHerd() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertEmptyRenameDoesNotMutateExistingHerd(
            using: harness.fixture
        )
    }

    func testCurrentHerdSelectionUsesApplicationIdentityAndScopesRename() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertCurrentHerdSelectionUsesApplicationIdentityAndScopesRename(
            using: harness.fixture
        )
    }

    func testMissingCurrentHerdSelectionDoesNotInferStoredHerd() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertMissingCurrentHerdSelectionDoesNotInferStoredHerd(
            using: harness.fixture
        )
    }

    func testStaleCurrentHerdSelectionDoesNotFallBackToAnotherStoredHerd() async throws {
        let harness = try await makeHarness()
        try await HerdRepositoryContract.assertStaleCurrentHerdSelectionDoesNotFallBackToAnotherStoredHerd(
            using: harness.fixture
        )
    }

    private func makeHarness() async throws -> Harness {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = CoreDataContractSelection()

        let fixture = HerdRepositoryContractFixture(
            makeHerdRepository: {
                CoreDataHerdRepository(
                    selection: selection,
                    assembly: assembly
                )
            },
            selectionControl: CoreDataContractTestSupport.herdSelectionControl(
                selection: selection,
                assembly: assembly
            ),
            ownershipControl: HerdRepositoryOwnershipTestControl(
                seedPasture: { id, herdID in
                    let context = try assembly.contextFactory.makeWriteContext()
                    try context.performAndWait {
                        guard let herd = try CoreDataLookup().herd(
                            id: herdID,
                            in: context
                        ) else {
                            throw HerdRepositoryError.missingHerd
                        }

                        let pasture = CDPasture(context: context)
                        pasture.id = id
                        pasture.name = "Herd Contract Pasture"
                        pasture.sortOrder = 0
                        pasture.herd = herd
                        try context.save()
                    }
                },
                persistedPasture: { id in
                    let context = assembly.contextFactory.makeReadContext()
                    return try context.performAndWait {
                        let request = NSFetchRequest<CDPasture>(
                            entityName: CDPasture.coreDataEntityName
                        )
                        request.predicate = NSPredicate(
                            format: "id == %@",
                            id as NSUUID
                        )
                        request.fetchLimit = 2
                        let matches = try context.fetch(request)
                        guard matches.count <= 1 else {
                            throw CoreDataPersistenceError.duplicateApplicationID(
                                entity: CDPasture.coreDataEntityName,
                                id: id,
                                herdID: nil
                            )
                        }
                        return matches.first.map {
                            HerdRepositoryOwnedPastureContractSnapshot(
                                id: $0.id,
                                herdID: $0.herd.id
                            )
                        }
                    }
                }
            )
        )

        let failureInjection = HerdRepositoryRollbackFailureInjection {
            repository,
            name in
            guard let repository = repository as? CoreDataHerdRepository else {
                XCTFail("Core Data Herd contract runner received an unexpected repository type.")
                return
            }

            _ = try await repository.renameCurrentHerd(
                to: name,
                beforeSave: { _ in
                    throw HerdRepositoryRollbackInjectedError.afterRenameStaged
                }
            )
        }

        return Harness(
            fixture: fixture,
            failureInjection: failureInjection
        )
    }
}

@MainActor
private struct Harness {
    let fixture: HerdRepositoryContractFixture
    let failureInjection: HerdRepositoryRollbackFailureInjection
}
