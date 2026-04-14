import Foundation
import Observation

@MainActor
@Observable
final class PregnancyCheckAddViewModel {
    var date = Date()
    var result: PregnancyResult = .unknown
    var technician = ""
    var estimatedDaysText = ""
    var dueDate: Date = .now
    var selectedSire: AnimalParentOption?
    var errorMessage: String?

    func save(animalID: UUID, using repository: any AnimalRepository) -> Bool {
        do {
            _ = try AddPregnancyCheckUseCase(repository: repository).execute(
                animalID: animalID,
                input: PregnancyCheckInput(
                    date: date,
                    result: result,
                    technician: technician.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : technician,
                    estimatedDaysPregnant: Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)),
                    dueDate: result == .pregnant ? dueDate : nil,
                    sireAnimalID: selectedSire?.id
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func recalcDueDate() {
        guard result == .pregnant else { return }
        guard let est = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let remaining = max(0, WorkingConstants.gestationDays - est)
        if let computed = Calendar.current.date(byAdding: .day, value: remaining, to: date) {
            dueDate = computed
        }
    }
}
