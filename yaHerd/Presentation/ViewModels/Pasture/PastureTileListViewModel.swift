import Foundation
import Observation

@MainActor
@Observable
final class PastureTileListViewModel {
    private(set) var items: [PastureSummary] = []
    var selectedPasture: PastureSummary?
    var isPresentingAddPasture = false
    var internalFilter: PastureListFilter = .all
    var draggedPasture: PastureSummary?
    var pasturePendingDeletion: PastureSummary?
    private(set) var pendingDeletionHerdID: UUID?
    private(set) var pendingDeletionSelectionRevision: UInt64?
    var errorMessage: String?
    private(set) var isDeletingPastures = false

    private var dragStartOrder: [PastureSummary] = []
    private(set) var hasLoaded = false
    private(set) var hasInitialLoadFailure = false
    private var lastLoadedRevision: UInt64 = 0
    @ObservationIgnored private var herdSelection: AppCurrentHerdSelection?
    private var selectedHerdID: UUID?
    private var selectedSelectionRevision: UInt64 = 0
    private var hasConfiguredHerdSelection = false
    private var dragSelectionRevision: UInt64?

    var isCurrentHerdSelection: Bool {
        guard let herdSelection else { return true }
        return selectedHerdID == herdSelection.currentHerdID
            && selectedSelectionRevision == herdSelection.selectionRevision
    }

    func configure(selection: AppCurrentHerdSelection) {
        herdSelection = selection
        let herdID = selection.currentHerdID
        let revision = selection.selectionRevision
        guard !hasConfiguredHerdSelection
                || selectedHerdID != herdID
                || selectedSelectionRevision != revision else { return }
        hasConfiguredHerdSelection = true
        selectedHerdID = herdID
        selectedSelectionRevision = revision
        resetForHerdChange()
    }

    func observe(
        using repository: any PastureListReader,
        mutationStream: any ApplicationMutationStreaming
    ) async {
        refreshHerdSelection()
        let startingRevision = mutationStream.pastureRevision
        if !hasLoaded || lastLoadedRevision < startingRevision {
            if load(using: repository) {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .pastures,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled else { return }
            if load(using: repository) {
                lastLoadedRevision = revision
            }
        }
    }

    @discardableResult
    func load(using repository: any PastureListReader) -> Bool {
        refreshHerdSelection()
        if !hasLoaded { hasInitialLoadFailure = false }
        do {
            items = try repository.fetchPastures()
            errorMessage = nil
            hasInitialLoadFailure = false
            hasLoaded = true
            return true
        } catch {
            if !hasLoaded { hasInitialLoadFailure = true }
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    func filteredItems(for filter: PastureListFilter) -> [PastureSummary] {
        switch filter {
        case .all:
            return items
        case .overCapacity:
            return items.filter(\.isOverCapacity)
        case .underutilized:
            return items.filter(\.isUnderutilized)
        case .rotationReady:
            return items.filter(\.isRotationReady)
        case .missingStockingData:
            return items.filter(\.isMissingStockingData)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func requestAddPasture() {
        refreshHerdSelection()
        isPresentingAddPasture = true
    }

    func select(_ pasture: PastureSummary) {
        refreshHerdSelection()
        guard items.contains(where: { $0.id == pasture.id }) else { return }
        selectedPasture = pasture
    }

    func requestDelete(_ pasture: PastureSummary) {
        refreshHerdSelection()
        guard items.contains(where: { $0.id == pasture.id }) else { return }
        pasturePendingDeletion = pasture
        pendingDeletionHerdID = selectedHerdID
        pendingDeletionSelectionRevision = selectedSelectionRevision
    }

    func clearPendingDeletion() {
        pasturePendingDeletion = nil
        pendingDeletionHerdID = nil
        pendingDeletionSelectionRevision = nil
    }

    func beginDragging(_ pasture: PastureSummary) {
        refreshHerdSelection()
        guard selectedHerdID != nil,
              isCurrentHerdSelection,
              items.contains(where: { $0.id == pasture.id }) else { return }
        dragStartOrder = items
        draggedPasture = pasture
        dragSelectionRevision = selectedSelectionRevision
    }

    func movePastures(from source: IndexSet, to destination: Int, using repository: any PastureOrdering) {
        let originalItems = items
        movePasturesInMemory(from: source, to: destination)

        commitPastureOrder(using: repository, rollbackTo: originalItems)
    }

    func movePasturesInMemory(from source: IndexSet, to destination: Int) {
        items = movedItems(from: source, to: destination)
    }

    func moveDraggedPasture(from source: Int, to destination: Int) {
        refreshHerdSelection()
        guard dragSelectionRevision == selectedSelectionRevision,
              dragSelectionRevision != nil,
              isCurrentHerdSelection else { return }
        movePasturesInMemory(from: IndexSet(integer: source), to: destination)
    }

    func commitDragOrder(using repository: any PastureOrdering) {
        refreshHerdSelection()
        guard selectedHerdID != nil,
              isCurrentHerdSelection,
              dragSelectionRevision == selectedSelectionRevision,
              dragSelectionRevision != nil,
              !dragStartOrder.isEmpty else {
            clearDrag()
            return
        }
        commitPastureOrder(using: repository, rollbackTo: dragStartOrder)
        clearDrag()
    }

    func persistPastureOrder(using repository: any PastureOrdering) throws {
        try ReorderPasturesUseCase(repository: repository).execute(ids: items.map(\.id))
    }

    func commitPastureOrder(using repository: any PastureOrdering, rollbackTo originalItems: [PastureSummary]) {
        do {
            try persistPastureOrder(using: repository)
        } catch {
            items = originalItems
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func deletePastures(
        at offsets: IndexSet,
        deletionCommand: any PastureDeletionPerforming,
        orderingRepository: any PastureOrdering,
        selection: AppCurrentHerdSelection,
        originatingHerdID: UUID,
        originatingSelectionRevision: UInt64
    ) async {
        refreshHerdSelection()
        guard !isDeletingPastures,
              selection.currentHerdID == originatingHerdID,
              selection.selectionRevision == originatingSelectionRevision else { return }

        let ids = offsets.sorted().compactMap { index in
            items.indices.contains(index) ? items[index].id : nil
        }
        guard !ids.isEmpty else { return }

        isDeletingPastures = true
        defer { isDeletingPastures = false }

        // Do not optimistically erase records: the command may fail before commit.
        do {
            try await deletionCommand.deletePastures(ids: ids, archivedAt: .now)
        } catch {
            if !Task.isCancelled,
               selection.currentHerdID == originatingHerdID,
               selection.selectionRevision == originatingSelectionRevision {
                errorMessage = UserVisibleErrorMessage.make(error)
            }
            return
        }

        // The delete already committed for its originating Herd. Do not issue a
        // separate ordering write through repositories now scoped to another Herd.
        guard !Task.isCancelled,
              selection.currentHerdID == originatingHerdID,
              selection.selectionRevision == originatingSelectionRevision else { return }

        let deletedIDs = Set(ids)
        items.removeAll { deletedIDs.contains($0.id) }
        clearPendingDeletion()

        // Ordering is a separate operation after the deletion has committed.
        // A reorder failure must never restore deleted rows in the UI.
        do {
            try persistPastureOrder(using: orderingRepository)
            errorMessage = nil
        } catch {
            errorMessage = "Pastures were deleted, but the remaining order could not be saved: "
                + UserVisibleErrorMessage.make(error)
        }
    }

    func deletePasture(
        id: UUID,
        deletionCommand: any PastureDeletionPerforming,
        orderingRepository: any PastureOrdering,
        selection: AppCurrentHerdSelection,
        originatingHerdID: UUID,
        originatingSelectionRevision: UInt64
    ) async {
        refreshHerdSelection()
        guard !isDeletingPastures,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        await deletePastures(
            at: IndexSet(integer: index),
            deletionCommand: deletionCommand,
            orderingRepository: orderingRepository,
            selection: selection,
            originatingHerdID: originatingHerdID,
            originatingSelectionRevision: originatingSelectionRevision
        )
    }

    private func refreshHerdSelection() {
        guard let herdSelection,
              selectedHerdID != herdSelection.currentHerdID
                || selectedSelectionRevision != herdSelection.selectionRevision else { return }
        configure(selection: herdSelection)
    }

    private func resetForHerdChange() {
        items = []
        selectedPasture = nil
        isPresentingAddPasture = false
        internalFilter = .all
        clearPendingDeletion()
        clearDrag()
        errorMessage = nil
        hasLoaded = false
        hasInitialLoadFailure = false
        lastLoadedRevision = 0
    }

    private func clearDrag() {
        dragStartOrder = []
        draggedPasture = nil
        dragSelectionRevision = nil
    }

    private func movedItems(from source: IndexSet, to destination: Int) -> [PastureSummary] {
        let indexedItems = items.enumerated()
        let movingItems = indexedItems
            .filter { source.contains($0.offset) }
            .map(\.element)

        var remainingItems = indexedItems
            .filter { !source.contains($0.offset) }
            .map(\.element)

        let adjustedDestination = destination - source.filter { $0 < destination }.count
        let insertionIndex = min(max(adjustedDestination, 0), remainingItems.count)
        remainingItems.insert(contentsOf: movingItems, at: insertionIndex)
        return remainingItems
    }
}
