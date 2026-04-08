import Foundation
import Observation

@MainActor
@Observable
final class AnimalParentPickerViewModel {
    private(set) var items: [AnimalParentOption] = []
    var searchText = ""
    var showAllSexes = false
    var errorMessage: String?

    func load(
        excluding excludedAnimalID: UUID?,
        using repository: any AnimalRepository
    ) {
        do {
            items = try LoadAnimalParentOptionsUseCase(repository: repository).execute(excluding: excludedAnimalID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func filtered(suggestedSexes: Set<Sex>, formattedTag: (AnimalParentOption) -> String) -> [AnimalParentOption] {
        items
            .filter { animal in
                guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                    || formattedTag(animal).localizedCaseInsensitiveContains(query)
            }
            .filter { animal in
                guard !showAllSexes else { return true }
                let hasSuggested = items.contains { suggestedSexes.contains($0.sex) }
                guard hasSuggested else { return true }
                return suggestedSexes.contains(animal.sex)
            }
    }
}
