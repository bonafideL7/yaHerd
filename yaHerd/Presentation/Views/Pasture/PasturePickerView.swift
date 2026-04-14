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
    @State private var errorMessage: String?
    @State private var showingError = false

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
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func applyPastureChange() {
        do {
            try AnimalMovementService.move(animal, to: selectedPasture, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
