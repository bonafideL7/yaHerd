import Foundation
import Observation

struct AnimalQuery: Hashable, Sendable {
    var searchText: String
    var filter: AnimalFilter
    var sortOrder: AnimalSortOrder
    var showRemovedStatuses: Bool
    var showArchivedRecords: Bool

    init(
        searchText: String = "",
        filter: AnimalFilter = AnimalFilter(),
        sortOrder: AnimalSortOrder = .tagAscending,
        showRemovedStatuses: Bool = false,
        showArchivedRecords: Bool = false
    ) {
        self.searchText = searchText
        self.filter = filter
        self.sortOrder = sortOrder
        self.showRemovedStatuses = showRemovedStatuses
        self.showArchivedRecords = showArchivedRecords
    }

    var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filtersAreActive: Bool {
        filter.isActive || showRemovedStatuses || showArchivedRecords
    }

    var hasNarrowingCriteria: Bool {
        hasSearchText || filter.isActive
    }

    var hasFilteringCriteria: Bool {
        hasSearchText || filtersAreActive
    }
}

@MainActor
@Observable
final class AnimalQueryState {
    var searchText = ""
    var filter = AnimalFilter()
    var sortOrder: AnimalSortOrder = .tagAscending
    var showRemovedStatuses = false
    var showArchivedRecords = false
    var showingFilters = false

    var query: AnimalQuery {
        AnimalQuery(
            searchText: searchText,
            filter: filter,
            sortOrder: sortOrder,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords
        )
    }

    var hasSearchText: Bool { query.hasSearchText }
    var filtersAreActive: Bool { query.filtersAreActive }
    var hasAnyActiveCriteria: Bool { query.hasFilteringCriteria }

    var activeFilterCount: Int {
        var count = 0
        if showRemovedStatuses { count += 1 }
        if showArchivedRecords { count += 1 }
        if filter.sex != nil { count += 1 }
        if filter.animalType != nil { count += 1 }
        if filter.status != nil { count += 1 }

        switch filter.pasture {
        case .any:
            break
        case .noPasture, .pasture:
            count += 1
        }

        if filter.location.isActive { count += 1 }
        if filter.recordIssue.isActive { count += 1 }
        return count
    }

    func apply(_ configuration: AnimalListLaunchConfiguration) {
        searchText = configuration.searchText
        sortOrder = configuration.sortOrder
        filter = configuration.filter
        showRemovedStatuses = configuration.showRemovedStatuses
        showArchivedRecords = configuration.showArchivedRecords
        showingFilters = false
    }

    func restore(
        searchText: String,
        sortOrder: AnimalSortOrder,
        filter: AnimalFilter,
        showRemovedStatuses: Bool,
        showArchivedRecords: Bool
    ) {
        self.searchText = searchText
        self.sortOrder = sortOrder
        self.filter = filter
        self.showRemovedStatuses = showRemovedStatuses
        self.showArchivedRecords = showArchivedRecords
        showingFilters = false
    }

    func clearCriteria() {
        searchText = ""
        filter = AnimalFilter()
        showRemovedStatuses = false
        showArchivedRecords = false
    }
}
