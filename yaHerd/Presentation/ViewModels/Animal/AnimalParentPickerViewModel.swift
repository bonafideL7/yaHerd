import Foundation
import Observation

@MainActor
@Observable
final class AnimalParentPickerViewModel {
    private(set) var items: [AnimalParentOption] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var searchText = ""
    var showAllSexes = false
    var errorMessage: String?

    @ObservationIgnored private var loadToken = UUID()

    /// All three parent picker callers share this complete, coherent read.
    /// Clearing before the request and publishing only on success prevents a
    /// stale or partial option from being selected after a failed refresh.
    func load(
        excluding excludedAnimalID: UUID?,
        using reader: (any AnimalParentOptionQueryReading)?
    ) async {
        let token = UUID()
        loadToken = token
        items = []
        isLoading = true
        hasLoaded = false
        errorMessage = nil

        guard let reader else {
            isLoading = false
            errorMessage = "The Animal parent-option lookup is not configured."
            return
        }

        do {
            let options = try await reader.fetchParentOptions(excluding: excludedAnimalID)
            try Task.checkCancellation()
            guard token == loadToken else { return }
            items = options
            isLoading = false
            hasLoaded = true
        } catch is CancellationError {
            if token == loadToken { isLoading = false }
        } catch {
            guard token == loadToken else { return }
            isLoading = false
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func filtered(
        suggestedSexes: Set<Sex>,
        formattedTag: (AnimalParentOption) -> String
    ) -> [AnimalParentOption] {
        guard hasLoaded else { return [] }

        return items
            .filter { animal in
                guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                    || animal.displayName.localizedCaseInsensitiveContains(query)
                    || animal.name.localizedCaseInsensitiveContains(query)
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
