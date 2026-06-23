import Foundation
import Observation

@MainActor
@Observable
final class PastureTileListViewModel {
    private(set) var items: [PastureSummary] = []
    var errorMessage: String?

    func load(using repository: any PastureRepository) {
        do {
            items = try LoadPasturesUseCase(repository: repository).execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    func movePastures(from source: IndexSet, to destination: Int, using repository: any PastureRepository) {
        let originalItems = items
        movePasturesInMemory(from: source, to: destination)

        commitPastureOrder(using: repository, rollbackTo: originalItems)
    }

    func movePasturesInMemory(from source: IndexSet, to destination: Int) {
        items = movedItems(from: source, to: destination)
    }

    func persistPastureOrder(using repository: any PastureRepository) throws {
        try ReorderPasturesUseCase(repository: repository).execute(ids: items.map(\.id))
    }

    func commitPastureOrder(using repository: any PastureRepository, rollbackTo originalItems: [PastureSummary]) {
        do {
            try persistPastureOrder(using: repository)
        } catch {
            items = originalItems
            errorMessage = error.localizedDescription
        }
    }

    func deletePastures(at offsets: IndexSet, using repository: any PastureRepository) {
        let originalItems = items
        let ids: [UUID] = offsets.sorted().reduce(into: []) { result, index in
            guard items.indices.contains(index) else { return }
            result.append(items[index].id)
        }

        items = items.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)

        do {
            try DeletePasturesUseCase(repository: repository).execute(ids: ids)
            try persistPastureOrder(using: repository)
        } catch {
            items = originalItems
            errorMessage = error.localizedDescription
        }
    }

    func deletePasture(id: UUID, using repository: any PastureRepository) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deletePastures(at: IndexSet(integer: index), using: repository)
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
