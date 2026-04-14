import Foundation
import Observation

@MainActor
@Observable
final class HealthRecordAddViewModel {
    var date = Date()
    var treatment = ""
    var notes = ""
    var errorMessage: String?

    var isSaveDisabled: Bool {
        treatment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(animalID: UUID, using repository: any AnimalRepository) -> Bool {
        do {
            _ = try AddHealthRecordUseCase(repository: repository).execute(
                animalID: animalID,
                date: date,
                treatment: treatment,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
