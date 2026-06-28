import Foundation

struct DeletePasturesUseCase {
    let pastureRepository: any PastureDeleting
    let fieldCheckRepository: any FieldCheckPastureCleanupWriter

    func execute(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        try fieldCheckRepository.deleteSessions(forPastureIDs: ids)
        try pastureRepository.delete(ids: ids)
    }
}
