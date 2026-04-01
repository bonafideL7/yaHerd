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

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    @State private var name: String = ""
    @State private var tagNumber = ""
    @State private var tagColorID: UUID?
    @State private var sex: Sex = .unknown
    @State private var birthDate = Date()
    @State private var status: AnimalStatus = .alive
    @State private var selectedPasture: Pasture?
    @State private var sire = ""
    @State private var dam = ""
    @State private var distinguishingFeatures: [DistinguishingFeature] = []
    @State private var activeParentPicker: ParentPickerType?
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                AnimalFormView(
                    name: $name,
                    tagNumber: $tagNumber,
                    tagColorID: $tagColorID,
                    sex: $sex,
                    birthDate: $birthDate,
                    status: $status,
                    pasture: $selectedPasture,
                    sire: $sire,
                    dam: $dam,
                    distinguishingFeatures: $distinguishingFeatures,
                    activeParentPicker: $activeParentPicker,
                    pastures: pastures
                )
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
        }.sheet(item: $activeParentPicker) { picker in
            switch picker {
                
            case .sire:
                AnimalParentPickerView(
                    title: "Select Sire",
                    excludeAnimal: nil,
                    suggestedSexes: [.male]
                ) { picked in
                    sire = picked.displayTagNumber
                    try? context.save()
                    activeParentPicker = nil
                }
                
            case .dam:
                AnimalParentPickerView(
                    title: "Select Dam",
                    excludeAnimal: nil,
                    suggestedSexes: [.female]
                ) { picked in
                    dam = picked.displayTagNumber
                    try? context.save()
                    activeParentPicker = nil
                }
            }
        }
    }

    private func validateAndSave() {
        do {
            try ValidationService.validateAnimal(
                birthDate: birthDate
            )

            let animal = Animal(
                name: name,
                tagNumber: tagNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                tagColorID: tagColorID,
                birthDate: birthDate,
                status: status,
                sire: sire.isEmpty ? nil : sire,
                dam: dam.isEmpty ? nil : dam,
                pasture: selectedPasture,
                sex: sex,
                distinguishingFeatures: distinguishingFeatures.filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )

            context.insert(animal)
            if !animal.tagNumber.isEmpty {
                _ = animal.ensurePrimaryTagRecord()
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
