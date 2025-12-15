//
//  BatchMoveSheet.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//


import SwiftUI
import SwiftData

struct BatchMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let animals: [Animal]
    let onComplete: () -> Void

    @Query(sort: \Pasture.name) private var pastures: [Pasture]
    @State private var selectedPasture: Pasture?

    var body: some View {
        NavigationStack {
            Form {
                Section("Move \(animals.count) animals") {
                    Picker("Destination Pasture", selection: $selectedPasture) {
                        ForEach(pastures) { pasture in
                            Text(pasture.name).tag(Optional(pasture))
                        }
                    }
                }
            }
            .navigationTitle("Batch Move")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        if let pasture = selectedPasture {
                            moveAnimals(to: pasture)
                        }
                    }
                    .disabled(selectedPasture == nil)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func moveAnimals(to pasture: Pasture) {
        for animal in animals {
            let oldName = animal.pasture?.name
            animal.pasture = pasture

            // Movement record
            let record = MovementRecord(
                date: .now,
                fromPasture: oldName,
                toPasture: pasture.name,
                animal: animal
            )
            context.insert(record)
        }

        try? context.save()
        onComplete()
        dismiss()
    }
}
