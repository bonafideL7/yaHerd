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
    var errorMessage: String?
    private(set) var isDeletingPastures = false

    private var dragStartOrder: [PastureSummary] = []
    private var hasLoaded = false
    private var lastLoadedRevision: UInt64 = 0

    func observe(
        using repository: any PastureListReader,
        mutationStream: any ApplicationMutationStreaming
    ) async {
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
        do {
            items = try repository.fetchPastures()
            errorMessage = nil
            hasLoaded = true
            return true
        } catch {
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
        isPresentingAddPasture = true
    }

    func select(_ pasture: PastureSummary) {
        selectedPasture = pasture
    }

    func requestDelete(_ pasture: PastureSummary) {
        pasturePendingDeletion = pasture
    }

    func clearPendingDeletion() {
        pasturePendingDeletion = nil
    }

    func beginDragging(_ pasture: PastureSummary) {
        dragStartOrder = items
        draggedPasture = pasture
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
        movePasturesInMemory(from: IndexSet(integer: source), to: destination)
    }

    func commitDragOrder(using repository: any PastureOrdering) {
        guard !dragStartOrder.isEmpty else { return }
        commitPastureOrder(using: repository, rollbackTo: dragStartOrder)
        dragStartOrder = []
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
        orderingRepository: any PastureOrdering
    ) async {
        guard !isDeletingPastures else { return }

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
            errorMessage = UserVisibleErrorMessage.make(error)
            return
        }

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
        orderingRepository: any PastureOrdering
    ) async {
        guard !isDeletingPastures,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        await deletePastures(
            at: IndexSet(integer: index),
            deletionCommand: deletionCommand,
            orderingRepository: orderingRepository
        )
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
