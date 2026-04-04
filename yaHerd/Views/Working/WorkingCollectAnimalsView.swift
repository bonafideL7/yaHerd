//
//  WorkingCollectAnimalsView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingCollectAnimalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Bindable var session: WorkingSession

    @Query(sort: \Animal.tagNumber) private var animals: [Animal]

    @State private var selected: Set<Animal> = []
    @State private var searchText: String = ""

    private var eligibleAnimals: [Animal] {
        let src = session.sourcePasture
        return animals
            .filter { $0.isActiveInHerd }
            .filter { $0.pasture === src }
            .filter { $0.location == .pasture }
            .filter { animal in
                guard !searchText.isEmpty else { return true }
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return animal.tagNumber.localizedCaseInsensitiveContains(q)
                    || tagColorLibrary.formattedTag(for: animal).localizedCaseInsensitiveContains(q)
            }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selected) {
                ForEach(eligibleAnimals) { animal in
                    HStack(spacing: 12) {
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
                    .tag(animal)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Collect")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search tag")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        collectSelected()
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func collectSelected() {
        let startOrder = (session.queueItems.map { $0.queueOrder }.max() ?? -1) + 1
        var order = startOrder
        let source = session.sourcePasture

        for animal in selected.sorted(by: { $0.tagNumber < $1.tagNumber }) {
            // Remove from pasture, mark as in working pen
            animal.pasture = nil
            animal.location = .workingPen
            animal.activeWorkingSession = session

            let item = WorkingQueueItem(
                queueOrder: order,
                status: .queued,
                collectedFromPasture: source,
                destinationPasture: nil,
                workNotes: nil,
                animal: animal,
                session: session
            )
            context.insert(item)
            session.queueItems.append(item)
            order += 1
        }

        try? context.save()
        dismiss()
    }
}
