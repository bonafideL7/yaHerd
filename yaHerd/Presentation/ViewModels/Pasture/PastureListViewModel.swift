import Foundation
import Observation

@MainActor
@Observable
final class PastureListViewModel {
    private(set) var items: [PastureSummary] = []
    var isPresentingAddPasture = false
    var errorMessage: String?

    func load(using repository: any PastureRepository) {
        do {
            items = try LoadPasturesUseCase(repository: repository).execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet, using repository: any PastureRepository) {
        let ids = offsets.compactMap { index in
            items.indices.contains(index) ? items[index].id : nil
        }

        do {
            try DeletePasturesUseCase(repository: repository).execute(ids: ids)
            load(using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
