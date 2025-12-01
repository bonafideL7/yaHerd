//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//


import SwiftUI
import SwiftData

struct AddAnimalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var tagNumber = ""
    @State private var sex: Sex = .cow
    @State private var birthDate = Date()
    @State private var status: AnimalStatus = .alive
    @State private var sire = ""
    @State private var dam = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tag Number", text: $tagNumber)

                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized)
                    }
                }

                DatePicker("Birth Date", selection: $birthDate, displayedComponents: .date)

                Picker("Status", selection: $status) {
                    ForEach(AnimalStatus.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized)
                    }
                }

                TextField("Sire", text: $sire)
                TextField("Dam", text: $dam)
            }
            .navigationTitle("Add Animal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(tagNumber.isEmpty)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
        }
    }

    private func save() {
        let animal = Animal(
            tagNumber: tagNumber,
            sex: sex,
            birthDate: birthDate,
            status: status,
            sire: sire.isEmpty ? nil : sire,
            dam: dam.isEmpty ? nil : dam
        )

        context.insert(animal)
        dismiss()
    }
}
