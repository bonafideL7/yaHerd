import SwiftUI

struct AnimalListEmptyStateView: View {
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
    let onClearFilters: () -> Void
    let onShowInactive: () -> Void
    let onShowArchivedRecords: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(configuration.title, systemImage: configuration.systemImage)
        } description: {
            Text(configuration.description)
        } actions: {
            if !hasItems {
                Button("Add Animal", action: onAddAnimal)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)

                Button("Add Sample Data", action: onAddSampleData)
                    .buttonStyle(.bordered)
            } else {
                if filtersAreActive {
                    Button("Clear Filters", action: onClearFilters)
                }

                if !showRemovedStatuses && hasHiddenOffHerdAnimals {
                    Button("Show Inactive", action: onShowInactive)
                }

                if !showArchivedRecords && hasHiddenArchivedRecords {
                    Button("Show Archived Records", action: onShowArchivedRecords)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
