//
//  AnimalParentPickerView.swift
//  yaHerd
//
//  Created by mm on 12/31/25.
//

import SwiftUI

struct AnimalParentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.animalFeatureDependencies) private var animalDependencies
    @Environment(AppNavigationState.self) private var navigation
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var viewModel = AnimalParentPickerViewModel()
    @State private var pastureOptions: [PastureOption] = []
    @State private var showingQueryFilters = false

    let title: String
    let excludeAnimalID: UUID?
    let suggestedSexes: Set<Sex>
    let onSelect: (AnimalParentOption) -> Void

    private var repository: any AnimalListRepository { animalDependencies.listRepository }
    private var pastureReferenceReader: any PastureReferenceDataReader {
        animalDependencies.pastureReferenceReader
    }
    private var query: AnimalQueryState { navigation.animalQuery }

    private var filtered: [AnimalSummary] {
        viewModel.filtered(
            query: query.query,
            suggestedSexes: suggestedSexes,
            formattedTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    var body: some View {
        @Bindable var query = query

        NavigationStack {
            List {
                Section {
                    Toggle(
                        "Show all",
                        isOn: Binding(
                            get: { viewModel.showAllSexes },
                            set: { viewModel.showAllSexes = $0 }
                        )
                    )
                }

                Section {
                    if filtered.isEmpty {
                        Text("No animals found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { animal in
                            Button {
                                onSelect(
                                    AnimalParentOption(
                                        id: animal.id,
                                        name: animal.name,
                                        displayTagNumber: animal.displayTagNumber,
                                        displayTagColorID: animal.displayTagColorID,
                                        sex: animal.sex,
                                        isArchived: animal.isArchived
                                    )
                                )
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    let definition = tagColorLibrary.resolvedDefinition(
                                        tagColorID: animal.displayTagColorID
                                    )

                                    VStack(alignment: .leading, spacing: 6) {
                                        AnimalTagView(
                                            tagNumber: animal.displayTagNumber,
                                            color: definition.color,
                                            colorName: definition.name
                                        )

                                        if !animal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(animal.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                        }

                                        Text(animal.sex.label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query.searchText,
                prompt: "Search tag, visual ID, or name"
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PersistentAnimalQueryControls(
                    sortOrder: $query.sortOrder,
                    filtersAreActive: query.filtersAreActive,
                    activeFilterCount: query.activeFilterCount,
                    hasAnyActiveCriteria: query.hasAnyActiveCriteria,
                    onShowFilters: { showingQueryFilters = true },
                    onClearAllCriteria: { query.clearCriteria() }
                )
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .sheet(isPresented: $showingQueryFilters) {
                AnimalFilterView(
                    filter: $query.filter,
                    showRemovedStatuses: $query.showRemovedStatuses,
                    showArchivedRecords: $query.showArchivedRecords,
                    pastureOptions: pastureOptions
                )
            }
            .alert("Can’t Load Animals", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
        .task {
            viewModel.load(excluding: excludeAnimalID, using: repository)
            pastureOptions = (try? pastureReferenceReader.fetchPastureOptions()) ?? []
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}
