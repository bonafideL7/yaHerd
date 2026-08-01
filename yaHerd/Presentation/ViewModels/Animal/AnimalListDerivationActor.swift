import Foundation

struct AnimalFormattedTagKey: Hashable, Sendable {
    let number: String
    let colorID: UUID?
}

struct AnimalListDerivedStateSnapshot {
    let filteredAndSortedAnimals: [AnimalSummary]
    let groupedAnimals: [AnimalSection]
    let shouldUseSections: Bool
    let currentSectionIDs: Set<String>
    let emptyStateConfiguration: AnimalListEmptyStateConfiguration
    let hasHiddenOffHerdAnimals: Bool
    let hasHiddenArchivedRecords: Bool
}

actor AnimalListDerivationActor {
    func makeSnapshot(
        items: [AnimalSummary],
        searchText: String,
        sortOrder: AnimalSortOrder,
        filter: AnimalFilter,
        showRemovedStatuses: Bool,
        showArchivedRecords: Bool,
        formattedTags: [AnimalFormattedTagKey: String]
    ) -> sending AnimalListDerivedStateSnapshot {
        PerformanceLog.measure("AnimalList.searchFilterSort") {
            let filtered = AnimalListDerivations.filteredAndSortedAnimals(
                items: items,
                searchText: searchText,
                sortOrder: sortOrder,
                filter: filter,
                showRemovedStatuses: showRemovedStatuses,
                showArchivedRecords: showArchivedRecords
            ) { number, colorID in
                formattedTags[AnimalFormattedTagKey(number: number, colorID: colorID)] ?? number
            }
            let sections = AnimalListDerivations.groupedAnimals(filtered, sortOrder: sortOrder)
            let usesSections = AnimalListDerivations.shouldUseSections(for: sortOrder)

            return AnimalListDerivedStateSnapshot(
                filteredAndSortedAnimals: filtered,
                groupedAnimals: sections,
                shouldUseSections: usesSections,
                currentSectionIDs: usesSections ? Set(sections.map(\.id)) : [],
                emptyStateConfiguration: AnimalListDerivations.emptyStateConfiguration(
                    items: items,
                    searchText: searchText,
                    filter: filter,
                    showRemovedStatuses: showRemovedStatuses,
                    showArchivedRecords: showArchivedRecords
                ),
                hasHiddenOffHerdAnimals: AnimalListDerivations.hasHiddenOffHerdAnimals(items: items),
                hasHiddenArchivedRecords: AnimalListDerivations.hasHiddenArchivedRecords(items: items)
            )
        }
    }
}
