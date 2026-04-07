//
//  WorkingFinishSessionView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingFinishSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Bindable var session: WorkingSession

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    private var orderedItems: [WorkingQueueItem] {
        session.queueItems.sorted { $0.queueOrder < $1.queueOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Return") {
                    Text("Assign a destination pasture for each animal, then return them out of the working pen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Animals") {
                    ForEach(orderedItems) { item in
                        if let animal = item.animal {
                            HStack {
                                let def = tagColorLibrary.resolvedDefinition(for: animal)
                                AnimalTagView(
                                    tagNumber: animal.tagNumber,
                                    color: def.color,
                                    colorName: def.name,
                                    size: .compact
                                )
                                Spacer()
                                Picker("", selection: bindingDestination(for: item)) {
                                    Text("None").tag(Optional<Pasture>(nil))
                                    ForEach(pastures) { pasture in
                                        Text(pasture.name).tag(Optional(pasture))
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Finish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Return") {
                        returnAnimals()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("All to Source") {
                        assignAllToSource()
                    }
                    .disabled(session.sourcePasture == nil)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // default destinations
                if let source = session.sourcePasture {
                    for item in orderedItems where item.destinationPasture == nil {
                        item.destinationPasture = source
                    }
                }
            }
        }
    }

    private func bindingDestination(for item: WorkingQueueItem) -> Binding<Pasture?> {
        Binding<Pasture?>(
            get: { item.destinationPasture ?? session.sourcePasture },
            set: { newValue in
                item.destinationPasture = newValue
            }
        )
    }

    private func assignAllToSource() {
        guard let source = session.sourcePasture else { return }
        for item in orderedItems {
            item.destinationPasture = source
        }
    }

    private func returnAnimals() {
        var changedAny = false

        for item in orderedItems {
            guard let animal = item.animal else { continue }
            let destination = item.destinationPasture ?? session.sourcePasture
            let changed = AnimalMovementService.move(
                animal,
                to: destination,
                in: context,
                fromPastureName: item.collectedFromPasture?.name,
                save: false
            )
            changedAny = changedAny || changed
        }

        session.status = .finished
        try? context.save()
        dismiss()
    }
}
