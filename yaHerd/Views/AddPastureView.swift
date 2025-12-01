//
//  AddPastureView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct AddPastureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var acreage: Double? = nil
    @State private var acreageString = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)

                TextField("Acreage", text: $acreageString)
                    .keyboardType(.decimalPad)
                    .onChange(of: acreageString) { _, value in
                        acreage = Double(value)
                    }
            }
            .navigationTitle("Add Pasture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.isEmpty)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
        }
    }

    private func save() {
        let pasture = Pasture(
            name: name,
            acreage: acreage
        )

        context.insert(pasture)
        dismiss()
    }
}
