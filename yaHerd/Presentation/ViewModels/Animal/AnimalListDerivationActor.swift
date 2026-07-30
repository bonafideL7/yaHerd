import Foundation

struct AnimalListDerivationRequest: Sendable {
    let items: [AnimalSummary]
    let searchText: String
    let sortOrder: AnimalSortOrder
    let filter: AnimalFilter
    let showRemovedStatuses: Bool
    let showArchivedRecords: Bool
    let formattedTagsByAnimalID: [UUID: String]
}

struct AnimalListDerivedStateSnapshot: Sendable {
    let filteredAndSortedAnimals: [AnimalSummary]
    let groupedAnimals: [AnimalSection]
    let shouldUseSections: Bool
    let currentSectionIDs: Set<String>
    let emptyStateConfiguration: AnimalListEmptyStateConfiguration
    let hasHiddenOffHerdAnimals: Bool
    let hasHiddenArchivedRecords: Bool
}

actor AnimalListDerivationActor {
    func derive(_ request: AnimalListDerivationRequest) -> AnimalListDerivedStateSnapshot {
        PerformanceLog.measure("AnimalListDerivationActor.derive") {
            let filtered = AnimalListDerivations.filteredAndSortedAnimals(
                items: request.items,
                searchText: request.searchText,
                sortOrder: request.sortOrder,
                filter: request.filter,
                showRemovedStatuses: request.showRemovedStatuses,
                showArchivedRecords: request.showArchivedRecords
            ) { _, _ in
                ""
            }
            let searched = applyFormattedTagSearch(
                to: filtered,
                request: request
            )
            let sections = AnimalListDerivations.groupedAnimals(
                searched,
                sortOrder: request.sortOrder
            )
            let usesSections = AnimalListDerivations.shouldUseSections(for: request.sortOrder)

            return AnimalListDerivedStateSnapshot(
                filteredAndSortedAnimals: searched,
                groupedAnimals: sections,
                shouldUseSections: usesSections,
                currentSectionIDs: usesSections ? Set(sections.map(\.id)) : [],
                emptyStateConfiguration: AnimalListDerivations.emptyStateConfiguration(
                    items: request.items,
                    searchText: request.searchText,
                    filter: request.filter,
                    showRemovedStatuses: request.showRemovedStatuses,
                    showArchivedRecords: request.showArchivedRecords
                ),
                hasHiddenOffHerdAnimals: AnimalListDerivations.hasHiddenOffHerdAnimals(
                    items: request.items
                ),
                hasHiddenArchivedRecords: AnimalListDerivations.hasHiddenArchivedRecords(
                    items: request.items
                )
            )
        }
    }

    private func applyFormattedTagSearch(
        to items: [AnimalSummary],
        request: AnimalListDerivationRequest
    ) -> [AnimalSummary] {
        let query = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        return items.filter { animal in
            animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                || animal.name.localizedCaseInsensitiveContains(query)
                || request.formattedTagsByAnimalID[animal.id, default: ""]
                    .localizedCaseInsensitiveContains(query)
        }
    }
}
