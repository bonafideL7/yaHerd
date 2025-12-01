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

    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tag Number", text: $tagNumber)
                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                DatePicker("Birth Date", selection: $birthDate, displayedComponents: .date)
                Picker("Status", selection: $status) {
                    ForEach(AnimalStatus.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                TextField("Sire", text: $sire)
                TextField("Dam", text: $dam)
            }
            .navigationTitle("Add Animal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { validateAndSave() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func validateAndSave() {
        do {
            try ValidationService.validateAnimal(
                tagNumber: tagNumber,
                birthDate: birthDate,
                context: context
            )

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

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
