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
                        animal.pasture = selectedPasture
                        try? context.save()
                        dismiss()
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
}
