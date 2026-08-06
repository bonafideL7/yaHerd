import Foundation
import Observation

@MainActor
@Observable
final class AnimalParentPickerViewModel {
    private(set) var items: [AnimalSummary] = []
    var showAllSexes = false
    var errorMessage: String?

    func load(
        excluding excludedAnimalID: UUID?,
        using repository: any AnimalListRepository
    ) {
        do {
            items = try repository.fetchAnimals().filter { $0.id != excludedAnimalID }
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func filtered(
        query: AnimalQuery,
        suggestedSexes: Set<Sex>,
        formattedTag: (String, UUID?) -> String
    ) -> [AnimalSummary] {
        let hasSuggestedSex = items.contains { suggestedSexes.contains($0.sex) }

        return AnimalQueryEngine.apply(
            to: items,
            query: query,
            mandatoryConstraint: { animal in
                showAllSexes || !hasSuggestedSex || suggestedSexes.contains(animal.sex)
            },
            formatTag: formattedTag
        )
    }
}
