import Foundation

struct AnimalListTagKey: Hashable, Sendable {
    let tagNumber: String
    let colorID: UUID?
}

struct AnimalListDerivationRequest: Sendable {
    let items: [AnimalSummary]
    let searchText: String
    let sortOrder: AnimalSortOrder
    let filter: AnimalFilter
    let showRemovedStatuses: Bool
    let showArchivedRecords: Bool
    let formattedTagsByKey: [AnimalListTagKey: String]
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
            ) { tagNumber, colorID in
                request.formattedTagsByKey[
                    AnimalListTagKey(tagNumber: tagNumber, colorID: colorID),
                    default: ""
                ]
            }
            let sections = AnimalListDerivations.groupedAnimals(
                filtered,
                sortOrder: request.sortOrder
            )
            let usesSections = AnimalListDerivations.shouldUseSections(for: request.sortOrder)

            return AnimalListDerivedStateSnapshot(
                filteredAndSortedAnimals: filtered,
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
}
