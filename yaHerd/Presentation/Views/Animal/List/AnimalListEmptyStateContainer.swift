//
//  AnimalListEmptyStateContainer.swift
//

import SwiftUI

struct AnimalListEmptyStateContainer: View {
    let configuration: AnimalListEmptyStateConfiguration
    let hasItems: Bool
    let filtersAreActive: Bool
    let hasHiddenOffHerdAnimals: Bool
    let hasHiddenArchivedRecords: Bool
    let showRemovedStatuses: Bool
    let showArchivedRecords: Bool
    let colorScheme: ColorScheme
    let onAddAnimal: () -> Void
    let onAddSampleData: () -> Void
    let onAddLargeSampleData: () -> Void
    let onClearFilters: () -> Void
    let onShowInactive: () -> Void
    let onShowArchivedRecords: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onAddAnimal)

            AnimalListEmptyStateView(
                configuration: configuration,
                hasItems: hasItems,
                filtersAreActive: filtersAreActive,
                hasHiddenOffHerdAnimals: hasHiddenOffHerdAnimals,
                hasHiddenArchivedRecords: hasHiddenArchivedRecords,
                showRemovedStatuses: showRemovedStatuses,
                showArchivedRecords: showArchivedRecords,
                colorScheme: colorScheme,
                onAddAnimal: onAddAnimal,
                onAddSampleData: onAddSampleData,
                onAddLargeSampleData: onAddLargeSampleData,
                onClearFilters: onClearFilters,
                onShowInactive: onShowInactive,
                onShowArchivedRecords: onShowArchivedRecords
            )
        }
    }
}
