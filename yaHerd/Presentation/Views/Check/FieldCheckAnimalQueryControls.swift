import SwiftUI

@MainActor
enum FieldCheckAnimalQuerySupport {
    static let sortOrders: [AnimalSortOrder] = [
        .tagAscending,
        .tagDescending,
        .sex,
        .animalType
    ]

    static func resolvedSortOrder(_ sortOrder: AnimalSortOrder) -> AnimalSortOrder {
        sortOrders.contains(sortOrder) ? sortOrder : .tagAscending
    }

    static func activeFilterCount(in query: AnimalQueryState) -> Int {
        (query.filter.sex == nil ? 0 : 1)
            + (query.filter.animalType == nil ? 0 : 1)
    }

    static func hasActiveFilters(in query: AnimalQueryState) -> Bool {
        activeFilterCount(in: query) > 0
    }

    static func hasActiveCriteria(in query: AnimalQueryState) -> Bool {
        !query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasActiveFilters(in: query)
    }

    static func clearCriteria(in query: AnimalQueryState) {
        query.searchText = ""
        query.filter.sex = nil
        query.filter.animalType = nil
    }
}

struct FieldCheckAnimalQueryControls: View {
    @Bindable var query: AnimalQueryState
    let onShowFilters: () -> Void

    private var resolvedSortOrder: Binding<AnimalSortOrder> {
        Binding(
            get: { FieldCheckAnimalQuerySupport.resolvedSortOrder(query.sortOrder) },
            set: { query.sortOrder = $0 }
        )
    }

    private var filterCount: Int {
        FieldCheckAnimalQuerySupport.activeFilterCount(in: query)
    }

    private var hasActiveCriteria: Bool {
        FieldCheckAnimalQuerySupport.hasActiveCriteria(in: query)
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort", selection: resolvedSortOrder) {
                    ForEach(FieldCheckAnimalQuerySupport.sortOrders, id: \.self) { option in
                        Label(option.label, systemImage: option.icon)
                            .tag(option)
                    }
                }
            } label: {
                Label(
                    FieldCheckAnimalQuerySupport.resolvedSortOrder(query.sortOrder).label,
                    systemImage: "arrow.up.arrow.down"
                )
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 24)

            Button(action: onShowFilters) {
                Label(
                    filterCount == 0 ? "All" : "\(filterCount) active",
                    systemImage: filterCount == 0
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .buttonStyle(.plain)

            if hasActiveCriteria {
                Divider()
                    .frame(height: 24)

                Button {
                    FieldCheckAnimalQuerySupport.clearCriteria(in: query)
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct FieldCheckAnimalFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var query: AnimalQueryState

    var body: some View {
        NavigationStack {
            Form {
                Section("Sex") {
                    Picker("Sex", selection: Binding(
                        get: { query.filter.sex },
                        set: { query.filter.sex = $0 }
                    )) {
                        Text("Any").tag(Sex?.none)
                        ForEach(Sex.allCases, id: \.self) { sex in
                            Text(sex.label).tag(Sex?.some(sex))
                        }
                    }
                }

                Section("Animal Type") {
                    Picker("Animal Type", selection: Binding(
                        get: { query.filter.animalType },
                        set: { query.filter.animalType = $0 }
                    )) {
                        Text("Any").tag(AnimalType?.none)
                        ForEach(AnimalType.allCases, id: \.self) { animalType in
                            Text(animalType.label).tag(AnimalType?.some(animalType))
                        }
                    }
                }
            }
            .navigationTitle("Roster Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        query.filter.sex = nil
                        query.filter.animalType = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    ToolbarDoneButton { dismiss() }
                }
            }
        }
    }
}
