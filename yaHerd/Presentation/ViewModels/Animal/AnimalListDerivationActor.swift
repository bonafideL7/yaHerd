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

struct AnimalListSectionSnapshot: Sendable {
    let id: String
    let title: String
    let animals: [AnimalSummary]
}

struct AnimalListEmptyStateSnapshot: Sendable {
    let title: String
    let description: String
    let systemImage: String
}

struct AnimalListDerivedStateSnapshot: Sendable {
    let filteredAndSortedAnimals: [AnimalSummary]
    let groupedAnimals: [AnimalListSectionSnapshot]
    let shouldUseSections: Bool
    let currentSectionIDs: Set<String>
    let emptyStateConfiguration: AnimalListEmptyStateSnapshot
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
            let emptyState = AnimalListDerivations.emptyStateConfiguration(
                items: request.items,
                searchText: request.searchText,
                filter: request.filter,
                showRemovedStatuses: request.showRemovedStatuses,
                showArchivedRecords: request.showArchivedRecords
            )
            let usesSections = AnimalListDerivations.shouldUseSections(for: request.sortOrder)

            return AnimalListDerivedStateSnapshot(
                filteredAndSortedAnimals: filtered,
                groupedAnimals: sections.map {
                    AnimalListSectionSnapshot(
                        id: $0.id,
                        title: $0.title,
                        animals: $0.animals
                    )
                },
                shouldUseSections: usesSections,
                currentSectionIDs: usesSections ? Set(sections.map(\.id)) : [],
                emptyStateConfiguration: AnimalListEmptyStateSnapshot(
                    title: emptyState.title,
                    description: emptyState.description,
                    systemImage: emptyState.systemImage
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
