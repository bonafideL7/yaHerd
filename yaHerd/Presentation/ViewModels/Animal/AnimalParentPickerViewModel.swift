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
    @ObservationIgnored private var loadedHerdID: UUID?
    @ObservationIgnored private var loadedSelectionRevision: UInt64?

    /// Never expose an option from an older Herd selection, even before the
    /// picker has been dismissed or a replacement query has started.
    func hasCurrentOptions(
        for selection: AppCurrentHerdSelection,
        originatingSelectionRevision: UInt64
    ) -> Bool {
        hasLoaded
            && loadedHerdID != nil
            && loadedHerdID == selection.currentHerdID
            && loadedSelectionRevision == originatingSelectionRevision
            && selection.selectionRevision == originatingSelectionRevision
    }

    /// All three parent picker callers share this complete, coherent read.
    /// Clearing before the request and publishing only on success prevents a
    /// stale or partial option from being selected after a failed refresh.
    func load(
        excluding excludedAnimalID: UUID?,
        using reader: (any AnimalParentOptionQueryReading)?,
        selection: AppCurrentHerdSelection,
        originatingSelectionRevision: UInt64
    ) async {
        let token = UUID()
        loadToken = token
        items = []
        isLoading = true
        hasLoaded = false
        errorMessage = nil
        loadedHerdID = nil
        loadedSelectionRevision = nil

        // A queued refresh must not switch its query to the Herd that became
        // current after the user opened this picker.
        guard let originatingHerdID = selection.currentHerdID,
              selection.selectionRevision == originatingSelectionRevision else {
            isLoading = false
            return
        }

        guard let reader else {
            isLoading = false
            errorMessage = "The Animal parent-option lookup is not configured."
            return
        }

        do {
            let options = try await reader.fetchParentOptions(excluding: excludedAnimalID)
            try Task.checkCancellation()
            guard token == loadToken else { return }
            guard selection.currentHerdID == originatingHerdID,
                  selection.selectionRevision == originatingSelectionRevision else {
                isLoading = false
                return
            }
            items = options
            loadedHerdID = originatingHerdID
            loadedSelectionRevision = originatingSelectionRevision
            isLoading = false
            hasLoaded = true
        } catch is CancellationError {
            if token == loadToken { isLoading = false }
        } catch {
            guard token == loadToken else { return }
            isLoading = false
            guard selection.currentHerdID == originatingHerdID,
                  selection.selectionRevision == originatingSelectionRevision else { return }
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func filtered(
        suggestedSexes: Set<Sex>,
        formattedTag: (AnimalParentOption) -> String
    ) -> [AnimalParentOption] {
        guard hasLoaded else { return [] }
        // Determine whether the suggested-sex filter is usable once per
        // render, not once per Animal in a large, complete parent cohort.
        let hasSuggested = items.contains { suggestedSexes.contains($0.sex) }

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
                guard hasSuggested else { return true }
                return suggestedSexes.contains(animal.sex)
            }
    }
}
