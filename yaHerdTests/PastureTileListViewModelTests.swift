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

    func testDeletePastureRemovesItemAndCoordinatesUseCase() async {
        let pasture = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let loadRepository = PastureListReaderStub(result: .success([pasture]))
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pasture.id]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureArchiveWriterSpy()
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: loadRepository)
        viewModel.requestDelete(pasture)

        await viewModel.deletePasture(
            id: pasture.id,
            deletionCommand: DeletePasturesUseCase(
                pastureRepository: pastureRepository,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            ),
            orderingRepository: pastureRepository
        )

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.pasturePendingDeletion)
        XCTAssertEqual(pastureRepository.deletedIDs, [[pasture.id]])
        XCTAssertEqual(fieldCheckRepository.archiveCalls.map(\.pastureIDs), [[pasture.id]])
    }

    func testDeletePastureRollsBackOnFailure() async {
        let pasture = PastureTestSupport.makeSummary(id: UUID(), name: "North")
        let loadRepository = PastureListReaderStub(result: .success([pasture]))
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = []
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureArchiveWriterSpy()
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: loadRepository)

        await viewModel.deletePasture(
            id: pasture.id,
            deletionCommand: DeletePasturesUseCase(
                pastureRepository: pastureRepository,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            ),
            orderingRepository: pastureRepository
        )

        XCTAssertEqual(viewModel.items, [pasture])
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(pastureRepository.deletedIDs.isEmpty)
    }
    func testAtomicDeleteWaitsBeforeChangingRowsAndBlocksDuplicateRequests() async {
        let first = PastureTestSupport.makeSummary(name: "First")
        let second = PastureTestSupport.makeSummary(name: "Second")
        let reader = PastureListReaderStub(result: .success([first, second]))
        let ordering = PastureOrderingSpy()
        let deletion = ControlledPastureDeletionCommand()
        deletion.shouldSuspend = true
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)
        viewModel.requestDelete(first)

        let running = Task { @MainActor in
            await viewModel.deletePasture(
                id: first.id,
                deletionCommand: deletion,
                orderingRepository: ordering
            )
        }

        await deletion.waitUntilStarted()
        XCTAssertTrue(viewModel.isDeletingPastures)
        XCTAssertEqual(viewModel.items, [first, second])
        XCTAssertEqual(viewModel.pasturePendingDeletion, first)

        await viewModel.deletePasture(
            id: first.id,
            deletionCommand: deletion,
            orderingRepository: ordering
        )
        XCTAssertEqual(deletion.requestedIDs, [[first.id]])
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)

        deletion.finishSuspendedWrite()
        await running.value

        XCTAssertFalse(viewModel.isDeletingPastures)
        XCTAssertEqual(viewModel.items, [second])
        XCTAssertNil(viewModel.pasturePendingDeletion)
        XCTAssertEqual(ordering.reorderedIDs, [[second.id]])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAtomicDeleteFailureLeavesRowsAndPendingConfirmationIntact() async {
        let pasture = PastureTestSupport.makeSummary(name: "North")
        let reader = PastureListReaderStub(result: .success([pasture]))
        let ordering = PastureOrderingSpy()
        let deletion = ControlledPastureDeletionCommand()
        deletion.errorToThrow = PastureTestError.forced
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)
        viewModel.requestDelete(pasture)

        await viewModel.deletePasture(
            id: pasture.id,
            deletionCommand: deletion,
            orderingRepository: ordering
        )

        XCTAssertEqual(viewModel.items, [pasture])
        XCTAssertEqual(viewModel.pasturePendingDeletion, pasture)
        XCTAssertEqual(viewModel.errorMessage, "Forced test error.")
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testCommittedDeletionStaysDeletedIfReorderingFails() async {
        let deleted = PastureTestSupport.makeSummary(name: "Deleted")
        let retained = PastureTestSupport.makeSummary(name: "Retained")
        let reader = PastureListReaderStub(result: .success([deleted, retained]))
        let ordering = PastureOrderingSpy()
        ordering.errorToThrow = PastureTestError.forced
        let deletion = ControlledPastureDeletionCommand()
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)
        viewModel.requestDelete(deleted)

        await viewModel.deletePasture(
            id: deleted.id,
            deletionCommand: deletion,
            orderingRepository: ordering
        )

        XCTAssertEqual(deletion.requestedIDs, [[deleted.id]])
        XCTAssertEqual(viewModel.items, [retained])
        XCTAssertNil(viewModel.pasturePendingDeletion)
        XCTAssertTrue(viewModel.errorMessage?.contains("were deleted") == true)
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testEmptyOrInvalidDeletionOffsetsDoNotSubmitCommands() async {
        let pasture = PastureTestSupport.makeSummary(name: "North")
        let reader = PastureListReaderStub(result: .success([pasture]))
        let ordering = PastureOrderingSpy()
        let deletion = ControlledPastureDeletionCommand()
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)

        await viewModel.deletePastures(
            at: IndexSet([4, 7]),
            deletionCommand: deletion,
            orderingRepository: ordering
        )
        await viewModel.deletePastures(
            at: [],
            deletionCommand: deletion,
            orderingRepository: ordering
        )

        XCTAssertTrue(deletion.requestedIDs.isEmpty)
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertEqual(viewModel.items, [pasture])
    }

}

@MainActor
private final class ControlledPastureDeletionCommand: PastureDeletionPerforming {
    private(set) var requestedIDs: [[UUID]] = []
    private(set) var archivedDates: [Date] = []
    var errorToThrow: Error?
    var shouldSuspend = false

    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var pendingCompletion: CheckedContinuation<Void, Never>?

    func deletePastures(ids: [UUID], archivedAt: Date) async throws {
        requestedIDs.append(ids)
        archivedDates.append(archivedAt)
        startedWaiter?.resume()
        startedWaiter = nil

        if shouldSuspend {
            await withCheckedContinuation { continuation in
                pendingCompletion = continuation
            }
        }
        if let errorToThrow {
            throw errorToThrow
        }
    }

    func waitUntilStarted() async {
        guard requestedIDs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            startedWaiter = continuation
        }
    }

    func finishSuspendedWrite() {
        pendingCompletion?.resume()
        pendingCompletion = nil
    }
}
