//
//  AnimalParentPickerView.swift
//  yaHerd
//
//  Created by mm on 12/31/25.
//

import SwiftUI

struct AnimalParentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var viewModel = AnimalParentPickerViewModel()

    let title: String
    let excludeAnimalID: UUID?
    let suggestedSexes: Set<Sex>
    let onSelect: (AnimalParentOption) -> Void

    private var repository: any AnimalRepository {
        dependencies.animalRepository
    }

    private var filtered: [AnimalParentOption] {
        viewModel.filtered(suggestedSexes: suggestedSexes) { animal in
            tagColorLibrary.formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show all", isOn: Binding(
                        get: { viewModel.showAllSexes },
                        set: { viewModel.showAllSexes = $0 }
                    ))
                }

                Section {
                    if filtered.isEmpty {
                        Text("No animals found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { animal in
                            Button {
                                onSelect(animal)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    let def = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
                                    VStack(alignment: .leading, spacing: 6) {
                                        AnimalTagView(
                                            tagNumber: animal.displayTagNumber,
                                            color: def.color,
                                            colorName: def.name
                                        )
                                        if animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(animal.displayName)
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
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ),
                prompt: "Search tag or name"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            viewModel.load(excluding: excludeAnimalID, using: repository)
        }
    }
}
