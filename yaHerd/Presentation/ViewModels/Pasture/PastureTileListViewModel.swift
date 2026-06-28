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

    private var dragStartOrder: [PastureSummary] = []

    func load(using repository: any PastureListReader) {
        do {
            items = try LoadPasturesUseCase(repository: repository).execute()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func deletePastures(
        at offsets: IndexSet,
        pastureRepository: any PastureDeleteRepository & PastureOrdering,
        animalRepository: any AnimalPastureMoving,
        fieldCheckRepository: any FieldCheckPastureCleanupWriter
    ) {
        let originalItems = items
        let ids: [UUID] = offsets.sorted().reduce(into: []) { result, index in
            guard items.indices.contains(index) else { return }
            result.append(items[index].id)
        }

        items = items.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)

        do {
            try DeletePasturesUseCase(
                pastureRepository: pastureRepository,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            ).execute(ids: ids)
            try persistPastureOrder(using: pastureRepository)
            clearPendingDeletion()
        } catch {
            items = originalItems
            errorMessage = error.localizedDescription
        }
    }

    func deletePasture(
        id: UUID,
        pastureRepository: any PastureDeleteRepository & PastureOrdering,
        animalRepository: any AnimalPastureMoving,
        fieldCheckRepository: any FieldCheckPastureCleanupWriter
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deletePastures(
            at: IndexSet(integer: index),
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
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
