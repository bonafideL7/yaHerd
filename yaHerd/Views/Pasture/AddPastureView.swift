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
    
    @AppStorage("targetHeadPerAcreDefault") private var targetHeadPerAcreDefault = 1.0
    @AppStorage("usableAcreagePercentDefault") private var usableAcreagePercentDefault = 100

    @State private var name = ""
    @State private var acreageString = ""
    @State private var acreage: Double? = nil

    var body: some View {
        NavigationStack {
            Form {

                // NAME
                TextField("Name", text: $name)

                // ACREAGE INPUT
                TextField("Acreage", text: $acreageString)
                    .keyboardType(.decimalPad)
                    .onChange(of: acreageString) { _, newValue in
                        acreage = Double(newValue)
                    }
            }
            .navigationTitle("Add Pasture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Validation
    private var canSave: Bool {
        !name.isEmpty && acreage != nil && acreage! > 0
    }

    // MARK: - Save Logic
    private func save() {
        guard let acres = acreage, acres > 0 else {
            dismiss()
            return
        }

        // Compute usable acreage
        let usable = acres * (Double(usableAcreagePercentDefault) / 100)

        let pasture = Pasture(
            name: name,
            acreage: acres,
            usableAcreage: usable,
            targetHeadPerAcre: targetHeadPerAcreDefault
        )

        context.insert(pasture)
        dismiss()
    }
}
