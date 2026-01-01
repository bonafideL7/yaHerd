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

    @Query(sort: \Animal.tagNumber) private var animals: [Animal]

    let title: String
    let excludeTagNumber: String
    let suggestedSexes: Set<Sex>
    let onSelect: (Animal) -> Void

    @State private var searchText = ""
    @State private var showAllSexes = false

    private var filtered: [Animal] {
        animals
            .filter { $0.tagNumber != excludeTagNumber }
            .filter { animal in
                guard !searchText.isEmpty else { return true }
                return animal.tagNumber.localizedCaseInsensitiveContains(searchText)
            }
            .filter { animal in
                guard !showAllSexes else { return true }
                // If the herd doesn't have any in the suggested sexes, still show everything.
                let hasSuggested = animals.contains { suggestedSexes.contains($0.sex) }
                guard hasSuggested else { return true }
                return suggestedSexes.contains(animal.sex)
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
                                    TagColorDot(tagColor: animal.tagColor ?? .yellow)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(animal.tagNumber)
                                        Text(animal.sex.rawValue.capitalized)
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
