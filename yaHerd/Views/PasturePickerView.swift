//
//  PasturePickerView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct PasturePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    @State var animal: Animal
    @State private var selectedPasture: Pasture?

    var body: some View {
        NavigationStack {
            List {
                Section("Assign Pasture") {
                    Picker("Pasture", selection: $selectedPasture) {
                        Text("None")
                            .tag(Pasture?.none)

                        ForEach(pastures) { pasture in
                            Text(pasture.name)
                                .tag(Optional(pasture))
                        }
                    }
                }
            }
            .navigationTitle("Change Pasture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyPastureChange()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                selectedPasture = animal.pasture
            }
        }
    }

    private func applyPastureChange() {
        let previousName = animal.pasture?.name
        let newName = selectedPasture?.name

        // Only log a movement if something actually changed
        if previousName != newName {
            // Update the animal
            animal.pasture = selectedPasture

            // Insert movement history record
            let movement = MovementRecord(
                date: Date(),
                fromPasture: previousName,
                toPasture: newName,
                animal: animal
            )
            context.insert(movement)
        }

        try? context.save()
        dismiss()
    }
}
