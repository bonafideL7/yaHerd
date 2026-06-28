//
//  AnimalListFilterChipFactory.swift
//

import Foundation

struct AnimalListFilterChipFactory {
    static func makeChips(
        filter: AnimalFilter,
        showRemovedStatuses: Bool,
        showArchivedRecords: Bool,
        pastureName: (UUID) -> String?,
        setFilter: @escaping (AnimalFilter) -> Void,
        setShowRemovedStatuses: @escaping (Bool) -> Void,
        setShowArchivedRecords: @escaping (Bool) -> Void
    ) -> [AnimalListFilterChip] {
        var chips: [AnimalListFilterChip] = []

        if showRemovedStatuses {
            chips.append(.init(title: "Off-Herd Visible") { setShowRemovedStatuses(false) })
        }

        if showArchivedRecords {
            chips.append(.init(title: "Archived Visible") { setShowArchivedRecords(false) })
        }

        appendOptionalChip(
            title: filter.sex?.label,
            to: &chips
        ) {
            var updatedFilter = filter
            updatedFilter.sex = nil
            setFilter(updatedFilter)
        }

        appendOptionalChip(
            title: filter.animalType?.label,
            to: &chips
        ) {
            var updatedFilter = filter
            updatedFilter.animalType = nil
            setFilter(updatedFilter)
        }

        appendOptionalChip(
            title: filter.status?.label,
            to: &chips
        ) {
            var updatedFilter = filter
            updatedFilter.status = nil
            setFilter(updatedFilter)
        }

        switch filter.pasture {
        case .any:
            break
        case .noPasture:
            chips.append(.init(title: "No Pasture") {
                var updatedFilter = filter
                updatedFilter.pasture = .any
                setFilter(updatedFilter)
            })
        case let .pasture(pastureID):
            appendOptionalChip(
                title: pastureName(pastureID),
                to: &chips
            ) {
                var updatedFilter = filter
                updatedFilter.pasture = .any
                setFilter(updatedFilter)
            }
        }

        if filter.location.isActive {
            chips.append(.init(title: filter.location.label) {
                var updatedFilter = filter
                updatedFilter.location = .any
                setFilter(updatedFilter)
            })
        }

        if filter.recordIssue.isActive {
            chips.append(.init(title: filter.recordIssue.label) {
                var updatedFilter = filter
                updatedFilter.recordIssue = .any
                setFilter(updatedFilter)
            })
        }

        return chips
    }

    private static func appendOptionalChip(
        title: String?,
        to chips: inout [AnimalListFilterChip],
        remove: @escaping () -> Void
    ) {
        guard let title else { return }
        chips.append(.init(title: title, remove: remove))
    }
}
