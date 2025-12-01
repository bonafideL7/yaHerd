//
//  PregnancyCheckAddView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct PregnancyCheckAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State var animal: Animal

    @State private var date = Date()
    @State private var result: PregnancyResult = .unknown
    @State private var technician = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Check Date", selection: $date, displayedComponents: .date)

                Picker("Result", selection: $result) {
                    ForEach(PregnancyResult.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized)
                    }
                }

                TextField("Technician", text: $technician)
            }
            .navigationTitle("Add Pregnancy Check")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let check = PregnancyCheck(
            date: date,
            result: result,
            technician: technician.isEmpty ? nil : technician,
            animal: animal
        )

        context.insert(check)
        dismiss()
    }
}
