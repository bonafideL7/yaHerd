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
}
