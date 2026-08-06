import SwiftUI

struct PersistentAnimalQueryControls: View {
    @Binding var sortOrder: AnimalSortOrder
    let filtersAreActive: Bool
    let activeFilterCount: Int
    let hasAnyActiveCriteria: Bool
    let onShowFilters: () -> Void
    let onClearAllCriteria: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(AnimalSortOrder.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.menuIcon)
                            .tag(option)
                    }
                }
            } label: {
                Label(sortOrder.menuLabel, systemImage: "arrow.up.arrow.down")
                    .lineLimit(1)
            }
            .accessibilityLabel("Sort animals")
            .accessibilityValue(sortOrder.label)

            Spacer(minLength: 0)

            Button(action: onShowFilters) {
                HStack(spacing: 6) {
                    Label(
                        "Filters",
                        systemImage: filtersAreActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )

                    if activeFilterCount > 0 {
                        Text(activeFilterCount, format: .number)
                            .font(.caption2.bold())
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityLabel(
                activeFilterCount > 0
                    ? "Filters, \(activeFilterCount) active"
                    : "Filters"
            )

            if hasAnyActiveCriteria {
                Button("Clear", systemImage: "xmark.circle", action: onClearAllCriteria)
                    .accessibilityLabel("Clear search, filters, and visibility options")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
