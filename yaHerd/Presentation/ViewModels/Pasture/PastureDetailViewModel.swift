import Foundation
import Observation

@MainActor
@Observable
final class PastureDetailViewModel {
    private(set) var detail: PastureDetailSnapshot?
    private(set) var residentAnimals: [AnimalSummary] = []
    let form = PastureFormViewModel()
    var isEditing = false
    var hasLoaded = false
    var errorMessage: String?

    func load(pastureID: UUID, using repository: any PastureRepository) {
        defer { hasLoaded = true }

        do {
            let loadedDetail = try LoadPastureDetailUseCase(repository: repository).execute(id: pastureID)
            detail = loadedDetail
            residentAnimals = try repository.fetchResidentAnimals(pastureID: pastureID)
            if !isEditing {
                form.populate(from: loadedDetail)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditing() {
        guard let detail else { return }
        form.populate(from: detail)
        isEditing = true
    }

    func cancelEditing() {
        guard let detail else {
            isEditing = false
            return
        }
        form.populate(from: detail)
        isEditing = false
    }

    func save(pastureID: UUID, using repository: any PastureRepository) {
        do {
            let input = try form.makeUpdateInput()
            let updated = try UpdatePastureUseCase(repository: repository).execute(
                id: pastureID,
                input: input
            )
            detail = updated
            residentAnimals = try repository.fetchResidentAnimals(pastureID: pastureID)
            form.populate(from: updated)
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
