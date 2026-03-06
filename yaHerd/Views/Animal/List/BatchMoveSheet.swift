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
    @State private var showingPasturePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Move \(animals.count) animals") {
                    Button("Choose Destination Pasture") {
                        showingPasturePicker = true
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
            .sheet(isPresented: $showingPasturePicker) {
                PastureTilePickerView { pasture in
                    moveAnimals(to: pasture)
                }
            }

        }
    }

    private func moveAnimals(to pasture: Pasture) {
        for animal in animals {
            let oldName = animal.pasture?.name
            animal.pasture = pasture
            animal.location = .pasture
            animal.activeWorkingSession = nil
            //pasture.lastGrazedDate = .now

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
