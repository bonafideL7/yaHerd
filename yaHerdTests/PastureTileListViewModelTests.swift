import XCTest
@testable import yaHerd

@MainActor
final class PastureTileListViewModelTests: XCTestCase {
    func testLoadPopulatesItems() {
        let north = PastureTestSupport.makeSummary(name: "North")
        let repository = PastureListReaderStub(result: .success([north]))
        let viewModel = PastureTileListViewModel()

        viewModel.load(using: repository)

        XCTAssertEqual(viewModel.items, [north])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFilteredItemsUsesCentralizedPastureRules() {
        let overCapacity = PastureTestSupport.makeSummary(
            name: "Over",
            acreage: 10,
            targetAcresPerHead: 2,
            activeAnimalCount: 6
        )
        let underutilized = PastureTestSupport.makeSummary(
            name: "Under",
            acreage: 10,
            targetAcresPerHead: 2,
            activeAnimalCount: 1
        )
        let missingStockingData = PastureTestSupport.makeSummary(
            name: "Missing",
            acreage: 10,
            targetAcresPerHead: nil,
            activeAnimalCount: 0
        )
        let restedEmpty = PastureTestSupport.makeSummary(
            name: "Ready",
            acreage: nil,
            targetAcresPerHead: nil,
            activeAnimalCount: 0,
            lastGrazedDate: nil,
            restDays: 21
        )
        let repository = PastureListReaderStub(result: .success([overCapacity, underutilized, missingStockingData, restedEmpty]))
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: repository)

        XCTAssertEqual(viewModel.filteredItems(for: .overCapacity), [overCapacity])
        XCTAssertEqual(viewModel.filteredItems(for: .underutilized), [underutilized])
        XCTAssertEqual(viewModel.filteredItems(for: .missingStockingData), [missingStockingData, restedEmpty])
        XCTAssertEqual(viewModel.filteredItems(for: .rotationReady), [underutilized, missingStockingData, restedEmpty])
    }

    func testMovePasturesInMemoryReordersItems() {
        let first = PastureTestSupport.makeSummary(name: "First")
        let second = PastureTestSupport.makeSummary(name: "Second")
        let third = PastureTestSupport.makeSummary(name: "Third")
        let repository = PastureListReaderStub(result: .success([first, second, third]))
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: repository)

        viewModel.movePasturesInMemory(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(viewModel.items, [second, third, first])
    }

    func testCommitPastureOrderRollsBackOnFailure() {
        let first = PastureTestSupport.makeSummary(name: "First")
        let second = PastureTestSupport.makeSummary(name: "Second")
        let loadRepository = PastureListReaderStub(result: .success([first, second]))
        let orderingRepository = PastureOrderingSpy()
        orderingRepository.errorToThrow = PastureTestError.forced
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: loadRepository)
        viewModel.movePasturesInMemory(from: IndexSet(integer: 0), to: 2)

        viewModel.commitPastureOrder(using: orderingRepository, rollbackTo: [first, second])

        XCTAssertEqual(viewModel.items, [first, second])
        XCTAssertEqual(viewModel.errorMessage, "Forced test error.")
    }

    func testDeletePastureRemovesItemAndCoordinatesUseCase() {
        let pasture = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let loadRepository = PastureListReaderStub(result: .success([pasture]))
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pasture.id]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureCleanupWriterSpy()
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: loadRepository)
        viewModel.requestDelete(pasture)

        viewModel.deletePasture(
            id: pasture.id,
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.pasturePendingDeletion)
        XCTAssertEqual(pastureRepository.deletedIDs, [[pasture.id]])
        XCTAssertEqual(fieldCheckRepository.cleanupCalls, [[pasture.id]])
    }

    func testDeletePastureRollsBackOnFailure() {
        let pasture = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let loadRepository = PastureListReaderStub(result: .success([pasture]))
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = []
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureCleanupWriterSpy()
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: loadRepository)

        viewModel.deletePasture(
            id: pasture.id,
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        XCTAssertEqual(viewModel.items, [pasture])
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(pastureRepository.deletedIDs.isEmpty)
    }
}
