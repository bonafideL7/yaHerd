import XCTest
@testable import yaHerd

@MainActor
final class PastureTileListViewModelTests: XCTestCase {
    private let testHerdID = UUID()
    private lazy var testSelection = AppCurrentHerdSelection(currentHerdID: testHerdID)

    func testLoadPopulatesItems() {
        let north = PastureTestSupport.makeSummary(name: "North")
        let repository = PastureListReaderStub(result: .success([north]))
        let viewModel = PastureTileListViewModel()

        viewModel.load(using: repository)

        XCTAssertEqual(viewModel.items, [north])
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.hasInitialLoadFailure)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFirstLoadFailureCanRetryWithoutDiscardingSuccessfulSnapshot() {
        let north = PastureTestSupport.makeSummary(name: "North")
        let unavailable = PastureListReaderStub(result: .failure(PastureTestError.forced))
        let available = PastureListReaderStub(result: .success([north]))
        let model = PastureTileListViewModel()

        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.hasInitialLoadFailure)
        XCTAssertFalse(model.load(using: unavailable))
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.hasInitialLoadFailure)

        XCTAssertTrue(model.load(using: available))
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.hasInitialLoadFailure)
        XCTAssertEqual(model.items, [north])

        XCTAssertFalse(model.load(using: unavailable))
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.hasInitialLoadFailure)
        XCTAssertEqual(model.items, [north], "Refresh failure must not replace retained content.")
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
            orderingRepository: pastureRepository,
            selection: testSelection,
            originatingHerdID: testHerdID,
            originatingSelectionRevision: testSelection.selectionRevision
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
            orderingRepository: pastureRepository,
            selection: testSelection,
            originatingHerdID: testHerdID,
            originatingSelectionRevision: testSelection.selectionRevision
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
                orderingRepository: ordering,
                selection: testSelection,
                originatingHerdID: testHerdID,
                originatingSelectionRevision: testSelection.selectionRevision
            )
        }

        await deletion.waitUntilStarted()
        XCTAssertTrue(viewModel.isDeletingPastures)
        XCTAssertEqual(viewModel.items, [first, second])
        XCTAssertEqual(viewModel.pasturePendingDeletion, first)

        await viewModel.deletePasture(
            id: first.id,
            deletionCommand: deletion,
            orderingRepository: ordering,
            selection: testSelection,
            originatingHerdID: testHerdID,
            originatingSelectionRevision: testSelection.selectionRevision
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
            orderingRepository: ordering,
            selection: testSelection,
            originatingHerdID: testHerdID,
            originatingSelectionRevision: testSelection.selectionRevision
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
            orderingRepository: ordering,
            selection: testSelection,
            originatingHerdID: testHerdID,
            originatingSelectionRevision: testSelection.selectionRevision
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
            orderingRepository: ordering,
            selection: testSelection,
            originatingHerdID: testHerdID,
            originatingSelectionRevision: testSelection.selectionRevision
        )
        await viewModel.deletePastures(
            at: IndexSet(),
            deletionCommand: deletion,
            orderingRepository: ordering,
            selection: testSelection,
            originatingHerdID: testHerdID,
            originatingSelectionRevision: testSelection.selectionRevision
        )

        XCTAssertTrue(deletion.requestedIDs.isEmpty)
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertEqual(viewModel.items, [pasture])
    }

    func testHerdSwitchBeforeDeleteTaskStartsRejectsOldHerdRequest() async {
        let pasture = PastureTestSupport.makeSummary(name: "Old Herd Pasture")
        let reader = PastureListReaderStub(result: .success([pasture]))
        let deletion = ControlledPastureDeletionCommand()
        let ordering = PastureOrderingSpy()
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)

        // The confirmation action captured Herd A, but the queued task starts in B.
        selection.select(UUID())
        await viewModel.deletePasture(
            id: pasture.id,
            deletionCommand: deletion,
            orderingRepository: ordering,
            selection: selection,
            originatingHerdID: originatingHerdID,
            originatingSelectionRevision: originatingSelectionRevision
        )

        XCTAssertTrue(deletion.requestedIDs.isEmpty)
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertEqual(viewModel.items, [pasture])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testHerdSwitchDuringDeletionSkipsReorderingAnotherHerd() async {
        let first = PastureTestSupport.makeSummary(name: "First")
        let second = PastureTestSupport.makeSummary(name: "Second")
        let reader = PastureListReaderStub(result: .success([first, second]))
        let ordering = PastureOrderingSpy()
        let deletion = ControlledPastureDeletionCommand()
        deletion.shouldSuspend = true
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)

        let running = Task { @MainActor in
            await viewModel.deletePasture(
                id: first.id,
                deletionCommand: deletion,
                orderingRepository: ordering,
                selection: selection,
                originatingHerdID: originatingHerdID,
                originatingSelectionRevision: originatingSelectionRevision
            )
        }

        await deletion.waitUntilStarted()
        selection.select(UUID())
        deletion.finishSuspendedWrite()
        await running.value

        XCTAssertEqual(deletion.requestedIDs, [[first.id]])
        XCTAssertTrue(ordering.reorderedIDs.isEmpty,
                      "A completed old-Herd deletion must not reorder the newly selected Herd.")
        XCTAssertEqual(viewModel.items, [first, second],
                       "The obsolete Herd view must not publish deletion results.")
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testHerdSwitchDuringFailedDeletionSuppressesOldHerdError() async {
        let pasture = PastureTestSupport.makeSummary(name: "Original")
        let reader = PastureListReaderStub(result: .success([pasture]))
        let ordering = PastureOrderingSpy()
        let deletion = ControlledPastureDeletionCommand()
        deletion.shouldSuspend = true
        deletion.errorToThrow = PastureTestError.forced
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)

        let running = Task { @MainActor in
            await viewModel.deletePasture(
                id: pasture.id,
                deletionCommand: deletion,
                orderingRepository: ordering,
                selection: selection,
                originatingHerdID: originatingHerdID,
                originatingSelectionRevision: originatingSelectionRevision
            )
        }
        await deletion.waitUntilStarted()
        selection.select(UUID())
        deletion.finishSuspendedWrite()
        await running.value

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.items, [pasture])
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testHerdRoundTripBeforeQueuedDeletionDoesNotStartOldRequest() async {
        let pasture = PastureTestSupport.makeSummary(name: "Old Herd Pasture")
        let reader = PastureListReaderStub(result: .success([pasture]))
        let deletion = ControlledPastureDeletionCommand()
        let ordering = PastureOrderingSpy()
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let originatingSelectionRevision = selection.selectionRevision
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)

        // The confirmation captured A, but selection changed away and back
        // before the queued task could begin its repository mutation.
        selection.select(UUID())
        selection.select(herdA)
        await viewModel.deletePasture(
            id: pasture.id,
            deletionCommand: deletion,
            orderingRepository: ordering,
            selection: selection,
            originatingHerdID: herdA,
            originatingSelectionRevision: originatingSelectionRevision
        )

        XCTAssertTrue(deletion.requestedIDs.isEmpty)
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertEqual(viewModel.items, [pasture])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testHerdRoundTripDuringDeletionDoesNotReorderFromObsoleteView() async {
        let first = PastureTestSupport.makeSummary(name: "First")
        let second = PastureTestSupport.makeSummary(name: "Second")
        let reader = PastureListReaderStub(result: .success([first, second]))
        let ordering = PastureOrderingSpy()
        let deletion = ControlledPastureDeletionCommand()
        deletion.shouldSuspend = true
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let originatingSelectionRevision = selection.selectionRevision
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)
        viewModel.requestDelete(first)

        let running = Task { @MainActor in
            await viewModel.deletePasture(
                id: first.id,
                deletionCommand: deletion,
                orderingRepository: ordering,
                selection: selection,
                originatingHerdID: herdA,
                originatingSelectionRevision: originatingSelectionRevision
            )
        }

        await deletion.waitUntilStarted()
        selection.select(UUID())
        selection.select(herdA)
        deletion.finishSuspendedWrite()
        await running.value

        XCTAssertEqual(deletion.requestedIDs, [[first.id]])
        XCTAssertTrue(ordering.reorderedIDs.isEmpty,
                      "An earlier view must not reorder even after returning to its Herd.")
        XCTAssertEqual(viewModel.items, [first, second])
        XCTAssertEqual(viewModel.pasturePendingDeletion, first)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testHerdRoundTripDuringFailedDeletionDoesNotPublishObsoleteError() async {
        let pasture = PastureTestSupport.makeSummary(name: "Original")
        let reader = PastureListReaderStub(result: .success([pasture]))
        let ordering = PastureOrderingSpy()
        let deletion = ControlledPastureDeletionCommand()
        deletion.shouldSuspend = true
        deletion.errorToThrow = PastureTestError.forced
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let originatingSelectionRevision = selection.selectionRevision
        let viewModel = PastureTileListViewModel()
        viewModel.load(using: reader)

        let running = Task { @MainActor in
            await viewModel.deletePasture(
                id: pasture.id,
                deletionCommand: deletion,
                orderingRepository: ordering,
                selection: selection,
                originatingHerdID: herdA,
                originatingSelectionRevision: originatingSelectionRevision
            )
        }

        await deletion.waitUntilStarted()
        selection.select(UUID())
        selection.select(herdA)
        deletion.finishSuspendedWrite()
        await running.value

        XCTAssertEqual(deletion.requestedIDs, [[pasture.id]])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.items, [pasture])
        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertFalse(viewModel.isDeletingPastures)
    }

    func testHerdSwitchDiscardsPreviousPastureStateBeforeLoadingNewHerd() {
        let oldPasture = PastureTestSupport.makeSummary(name: "Old Herd")
        let newPasture = PastureTestSupport.makeSummary(name: "New Herd")
        let reader = PastureListReaderStub(result: .success([oldPasture]))
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))
        model.select(oldPasture)
        model.requestDelete(oldPasture)
        model.requestAddPasture()
        model.beginDragging(oldPasture)
        model.internalFilter = .overCapacity

        selection.select(UUID())
        model.configure(selection: selection)

        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.selectedPasture)
        XCTAssertNil(model.pasturePendingDeletion)
        XCTAssertNil(model.draggedPasture)
        XCTAssertFalse(model.isPresentingAddPasture)
        XCTAssertEqual(model.internalFilter, .all)
        XCTAssertNil(model.errorMessage)

        reader.result = .success([newPasture])
        XCTAssertTrue(model.load(using: reader))
        XCTAssertEqual(model.items, [newPasture])
    }

    func testFailedNewHerdLoadNeverRetainsOldHerdPastures() {
        let oldPasture = PastureTestSupport.makeSummary(name: "Old Herd")
        let reader = PastureListReaderStub(result: .success([oldPasture]))
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))

        selection.select(UUID())
        reader.result = .failure(PastureTestError.forced)

        XCTAssertFalse(model.load(using: reader))
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.hasInitialLoadFailure)
    }

    func testDragCommitAfterHerdRoundTripNeverReordersNewSelection() {
        let first = PastureTestSupport.makeSummary(name: "First")
        let second = PastureTestSupport.makeSummary(name: "Second")
        let reader = PastureListReaderStub(result: .success([first, second]))
        let ordering = PastureOrderingSpy()
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))

        model.beginDragging(first)
        model.moveDraggedPasture(from: 0, to: 2)
        selection.select(UUID())
        selection.select(herdA)

        model.commitDragOrder(using: ordering)

        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.draggedPasture)
        XCTAssertFalse(model.hasLoaded)
    }

    func testDeletionConfirmationRetainsOriginatingHerdUntilDismissed() {
        let pasture = PastureTestSupport.makeSummary(name: "Old Herd Pasture")
        let reader = PastureListReaderStub(result: .success([pasture]))
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))

        model.requestDelete(pasture)

        XCTAssertEqual(model.pendingDeletionHerdID, herdA)
        XCTAssertEqual(model.pendingDeletionSelectionRevision, selection.selectionRevision)

        selection.select(UUID())
        // A confirmation presented before the switch must not acquire B's
        // selection identity when its destructive action is eventually tapped.
        XCTAssertEqual(model.pendingDeletionHerdID, herdA)
        model.configure(selection: selection)
        XCTAssertNil(model.pasturePendingDeletion)
        XCTAssertNil(model.pendingDeletionHerdID)
        XCTAssertNil(model.pendingDeletionSelectionRevision)
    }

    func testOldDropCallbackCannotCommitANewHerdDrag() {
        let firstA = PastureTestSupport.makeSummary(name: "A First")
        let firstB = PastureTestSupport.makeSummary(name: "B First")
        let secondB = PastureTestSupport.makeSummary(name: "B Second")
        let reader = PastureListReaderStub(result: .success([firstA]))
        let ordering = PastureOrderingSpy()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))
        let oldRevision = selection.selectionRevision
        model.beginDragging(firstA, originatingSelectionRevision: oldRevision)

        selection.select(UUID())
        model.configure(selection: selection)
        reader.result = .success([firstB, secondB])
        XCTAssertTrue(model.load(using: reader))
        let currentRevision = selection.selectionRevision
        model.beginDragging(firstB, originatingSelectionRevision: currentRevision)
        model.moveDraggedPasture(
            from: 0, to: 2, originatingSelectionRevision: currentRevision
        )

        model.commitDragOrder(using: ordering, originatingSelectionRevision: oldRevision)

        XCTAssertTrue(ordering.reorderedIDs.isEmpty)
        XCTAssertEqual(model.items, [secondB, firstB])

        model.commitDragOrder(using: ordering, originatingSelectionRevision: currentRevision)

        XCTAssertEqual(ordering.reorderedIDs, [[secondB.id, firstB.id]])
    }

    func testUnselectedHerdCannotLoadOldPasturesOrStartAddFlow() {
        let old = PastureTestSupport.makeSummary(name: "Original Herd")
        let reader = PastureListReaderStub(result: .success([old]))
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))

        selection.select(nil)

        XCTAssertFalse(model.load(using: reader))
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.hasLoaded)
        model.requestAddPasture()
        XCTAssertFalse(model.isPresentingAddPasture)
    }

    func testOldDeleteGestureCannotTargetMatchingIDInNewHerd() {
        let id = UUID()
        let a = PastureTestSupport.makeSummary(id: id, name: "Herd A")
        let b = PastureTestSupport.makeSummary(id: id, name: "Herd B")
        let reader = PastureListReaderStub(result: .success([a]))
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))
        let oldRevision = selection.selectionRevision

        selection.select(UUID())
        model.configure(selection: selection)
        reader.result = .success([b])
        XCTAssertTrue(model.load(using: reader))

        model.requestDelete(a, originatingSelectionRevision: oldRevision)
        XCTAssertNil(model.pasturePendingDeletion)

        model.requestDelete(b, originatingSelectionRevision: selection.selectionRevision)
        XCTAssertEqual(model.pasturePendingDeletion, b)
    }

    func testDragCommitWithinUnchangedHerdPersistsNewOrder() {
        let first = PastureTestSupport.makeSummary(name: "First")
        let second = PastureTestSupport.makeSummary(name: "Second")
        let reader = PastureListReaderStub(result: .success([first, second]))
        let ordering = PastureOrderingSpy()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = PastureTileListViewModel()
        model.configure(selection: selection)
        XCTAssertTrue(model.load(using: reader))

        model.beginDragging(first)
        model.moveDraggedPasture(from: 0, to: 2)
        model.commitDragOrder(using: ordering)

        XCTAssertEqual(ordering.reorderedIDs, [[second.id, first.id]])
        XCTAssertEqual(model.items, [second, first])
    }


    func testObsoletePastureMutationObserverDoesNotReadNewlySelectedHerd() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let reader = PastureListReaderStub(
            result: .success([PastureTestSupport.makeSummary(name: "Original")])
        )
        let mutations = ApplicationMutationCenter()
        let model = PastureTileListViewModel()
        model.configure(selection: selection)

        let obsoleteObserver = Task {
            await model.observe(using: reader, mutationStream: mutations)
        }
        for _ in 0..<100 where !model.hasLoaded {
            await Task.yield()
        }
        XCTAssertTrue(model.hasLoaded)

        selection.select(UUID())
        model.configure(selection: selection)
        let replacement = PastureTestSupport.makeSummary(name: "Replacement")
        reader.result = .success([replacement])
        XCTAssertTrue(model.load(using: reader))

        // The only remaining observer was created for the previous Herd.
        // It must not issue a repository read or show its failure in this Herd.
        reader.result = .failure(PastureTestError.forced)
        mutations.recordSuccessfulMutation(reason: .pasture)
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(model.items, [replacement])
        XCTAssertNil(model.errorMessage)

        obsoleteObserver.cancel()
        await obsoleteObserver.value
    }

    func testObsoletePastureObserverStaysInvalidAfterReturningToOriginalHerd() async {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let reader = PastureListReaderStub(
            result: .success([PastureTestSupport.makeSummary(name: "Old Snapshot")])
        )
        let mutations = ApplicationMutationCenter()
        let model = PastureTileListViewModel()
        model.configure(selection: selection)

        let obsoleteObserver = Task {
            await model.observe(using: reader, mutationStream: mutations)
        }
        for _ in 0..<100 where !model.hasLoaded {
            await Task.yield()
        }
        XCTAssertTrue(model.hasLoaded)

        selection.select(UUID())
        model.configure(selection: selection)
        selection.select(originalHerdID)
        model.configure(selection: selection)
        let refreshed = PastureTestSupport.makeSummary(name: "New Snapshot")
        reader.result = .success([refreshed])
        XCTAssertTrue(model.load(using: reader))

        reader.result = .failure(PastureTestError.forced)
        mutations.recordSuccessfulMutation(reason: .pasture)
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(model.items, [refreshed])
        XCTAssertNil(model.errorMessage, "The selection revision must invalidate a prior observer.")

        obsoleteObserver.cancel()
        await obsoleteObserver.value
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
