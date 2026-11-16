import CoreData
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataHerdSelectionTests: XCTestCase {
    func testSelectingAnotherHerdChangesRepositoryScopeWithoutMovingRecords() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = AppCurrentHerdSelection()
        let herdRepository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let directory = HerdDirectoryController(repository: herdRepository, selection: selection)
        let pastures = CoreDataPastureRepository(selection: selection, assembly: assembly)

        let north = try await directory.createOwnedHerd(named: "North")
        XCTAssertEqual(selection.currentHerdID, north.id)
        let northPasture = try pastures.create(input: PastureInput(
            name: "North Field",
            acreage: 10,
            usableAcreage: 9,
            targetAcresPerHead: 2
        ))

        let south = try await herdRepository.createOwnedHerd(named: "South")
        XCTAssertEqual(selection.currentHerdID, north.id)
        try directory.selectHerd(id: south.id)
        XCTAssertEqual(try herdRepository.fetchCurrentHerd().id, south.id)
        XCTAssertTrue(try pastures.fetchPastures().isEmpty)
        let southPasture = try pastures.create(input: PastureInput(
            name: "South Field",
            acreage: 15,
            usableAcreage: 12,
            targetAcresPerHead: 3
        ))

        try directory.selectHerd(id: north.id)
        XCTAssertEqual(try herdRepository.fetchCurrentHerd().id, north.id)
        XCTAssertEqual(try pastures.fetchPastures().map(\.id), [northPasture.id])
        try directory.selectHerd(id: south.id)
        XCTAssertEqual(try pastures.fetchPastures().map(\.id), [southPasture.id])
    }

    func testInvalidOrIncompleteHerdCannotReplaceCurrentSelection() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        let valid = try await directory.createOwnedHerd(named: "Existing")

        let incompleteID = UUID()
        let writer = try assembly.contextFactory.makeWriteContext()
        try writer.performAndWait {
            let incomplete = CDHerd(context: writer)
            incomplete.id = incompleteID
            incomplete.name = nil
            incomplete.createdAt = nil
            incomplete.updatedAt = nil
            try writer.save()
        }

        directory.refresh()
        XCTAssertEqual(directory.herds.map(\.id), [valid.id])
        for unavailable in [incompleteID, UUID()] {
            XCTAssertThrowsError(try directory.selectHerd(id: unavailable)) {
                XCTAssertEqual($0 as? HerdRepositoryError, .missingHerd)
            }
            XCTAssertEqual(selection.currentHerdID, valid.id)
        }
    }

    func testSilentImportRefreshPreservesActionableHerdErrorUntilAcknowledged() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        directory.report(HerdRepositoryError.emptyName)
        let error = try XCTUnwrap(directory.errorMessage)
        directory.refresh(reportErrors: false)
        XCTAssertEqual(directory.errorMessage, error,
                       "Background refresh must not dismiss an actionable error")

        directory.refresh()
        XCTAssertNil(directory.errorMessage, "Manual refresh may clear the error")
    }

    func testFailedCreationDoesNotSwitchHerd() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let directory = HerdDirectoryController(repository: repository, selection: selection)
        let existing = try await directory.createOwnedHerd(named: "Existing")

        do {
            _ = try await directory.createOwnedHerd(named: "   ")
            XCTFail("Blank Herd name should be rejected")
        } catch {
            XCTAssertEqual(error as? HerdRepositoryError, .emptyName)
        }
        XCTAssertEqual(selection.currentHerdID, existing.id)
        XCTAssertEqual(try repository.fetchAccessibleHerds().map(\.id), [existing.id])
    }
    func testRefreshingDirectoryFindsNewlyAvailableHerdWithoutChangingSelection() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = AppCurrentHerdSelection()
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        let directory = HerdDirectoryController(repository: repository, selection: selection)

        directory.refresh()
        XCTAssertTrue(directory.herds.isEmpty)
        let arrived = try await repository.createOwnedHerd(named: "Arrived")
        directory.refresh(reportErrors: false)

        XCTAssertEqual(directory.herds.map(\.id), [arrived.id])
        XCTAssertNil(selection.currentHerdID)
    }

}
