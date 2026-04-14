import Foundation
import Observation

@MainActor
@Observable
final class PastureChangeViewModel {
    var selectedPastureID: UUID?
    var errorMessage: String?

    func moveAnimal(animalID: UUID, using repository: any AnimalRepository) -> Bool {
        do {
            try MoveAnimalsUseCase(repository: repository).execute(ids: [animalID], toPastureID: selectedPastureID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
