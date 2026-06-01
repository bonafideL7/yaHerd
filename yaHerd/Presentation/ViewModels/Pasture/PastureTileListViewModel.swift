import Foundation
import Observation

@MainActor
@Observable
final class PastureTileListViewModel {
    private(set) var items: [PastureSummary] = []
    var errorMessage: String?
    var isManaging = false

    func load(using repository: any PastureRepository) {
        do {
            items = try LoadPasturesUseCase(repository: repository).execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enterManageMode() {
        isManaging = true
    }

    func toggleManageMode() {
        isManaging.toggle()
    }

    func movePastures(from source: IndexSet, to destination: Int, using repository: any PastureRepository) {
        let originalItems = items
        items = movedItems(from: source, to: destination)

        do {
            try ReorderPasturesUseCase(repository: repository).execute(ids: items.map(\.id))
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
            try ReorderPasturesUseCase(repository: repository).execute(ids: items.map(\.id))
        } catch {
            items = originalItems
            errorMessage = error.localizedDescription
        }
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
