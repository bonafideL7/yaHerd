//
//  AnimalParentPickerView.swift
//  yaHerd
//
//  Created by mm on 12/31/25.
//

import SwiftUI

struct AnimalParentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @Environment(\.animalFeatureDependencies) private var animalDependencies
    private var parentOptionQueryReader: (any AnimalParentOptionQueryReading)? {
        animalDependencies.parentOptionQueryReader
    }
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var viewModel = AnimalParentPickerViewModel()
    @State private var openedSelectionRevision: UInt64?

    let title: String
    let excludeAnimalID: UUID?
    let suggestedSexes: Set<Sex>
    let onSelect: (AnimalParentOption) -> Void


    private var filtered: [AnimalParentOption] {
        guard let openedSelectionRevision,
              viewModel.hasCurrentOptions(
                for: herdSelection,
                originatingSelectionRevision: openedSelectionRevision
              ) else { return [] }
        return viewModel.filtered(suggestedSexes: suggestedSexes) { animal in
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
                    if viewModel.isLoading {
                        ProgressView("Loading parent choices…")
                    } else if let error = viewModel.errorMessage {
                        ContentUnavailableView {
                            Label("Unable to Load Parents", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Retry") { refreshOptions() }
                        }
                    } else if viewModel.hasLoaded && filtered.isEmpty {
                        ContentUnavailableView(
                            "No Animals Found",
                            systemImage: "tag",
                            description: Text("No parent options match this search.")
                        )
                    } else if viewModel.hasLoaded {
                        ForEach(filtered) { animal in
                            Button {
                                guard let openedSelectionRevision,
                                      viewModel.hasCurrentOptions(
                                        for: herdSelection,
                                        originatingSelectionRevision: openedSelectionRevision
                                      ) else { return }
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
                    ToolbarCancelButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { refreshOptions() } label: {
                        Label("Refresh Parent Choices", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .task(id: excludeAnimalID) {
            // The lifetime of this sheet is tied to its opening Herd, not to
            // whatever Herd becomes current while an asynchronous read runs.
            let revision = openedSelectionRevision ?? herdSelection.selectionRevision
            openedSelectionRevision = revision
            await viewModel.load(
                excluding: excludeAnimalID,
                using: parentOptionQueryReader,
                selection: herdSelection,
                originatingSelectionRevision: revision
            )
        }
        .onChange(of: herdSelection.selectionRevision) { _, revision in
            if let openedSelectionRevision, revision != openedSelectionRevision {
                dismiss()
            }
        }
    }

    private func refreshOptions() {
        guard let openedSelectionRevision else { return }
        Task { @MainActor in
            await viewModel.load(
                excluding: excludeAnimalID,
                using: parentOptionQueryReader,
                selection: herdSelection,
                originatingSelectionRevision: openedSelectionRevision
            )
        }
    }
}
