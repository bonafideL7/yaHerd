//
//  AnimalParentPickerView.swift
//  yaHerd
//
//  Created by mm on 12/31/25.
//

import SwiftUI
import SwiftData

/// Simple selector that lets the user pick an existing animal as a sire/dam.
/// This populates the parent's *tag number* onto the child record (no relationship required).
struct AnimalParentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Query(sort: \Animal.tagNumber) private var animals: [Animal]

    let title: String
    /// Exclude the current animal (self) from the picker.
    /// This must NOT be based on tag number, since tag numbers are not globally unique.
    let excludeAnimal: Animal?
    let suggestedSexes: Set<Sex>
    let onSelect: (Animal) -> Void

    @State private var searchText = ""
    @State private var showAllSexes = false

    private var filtered: [Animal] {
        animals
            .filter { animal in
                guard let excludeAnimal else { return true }
                return animal.persistentModelID != excludeAnimal.persistentModelID
            }
            .filter { animal in
                guard !searchText.isEmpty else { return true }
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return animal.tagNumber.localizedCaseInsensitiveContains(q)
                    || tagColorLibrary.formattedTag(for: animal).localizedCaseInsensitiveContains(q)
            }
            .filter { animal in
                guard !showAllSexes else { return true }
                // If the herd doesn't have any in the suggested sexes, still show everything.
                let hasSuggested = animals.contains { suggestedSexes.contains($0.sex ?? .female) }
                guard hasSuggested else { return true }
                return suggestedSexes.contains(animal.sex ?? .female)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show all", isOn: $showAllSexes)
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
                                    let def = tagColorLibrary.resolvedDefinition(for: animal)
                                    VStack(alignment: .leading, spacing: 6) {
                                        AnimalTagView(
                                            tagNumber: animal.tagNumber,
                                            color: def.color,
                                            colorName: def.name
                                        )
                                        Text((animal.sex ?? .female).label)
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
            .searchable(text: $searchText, prompt: "Search tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
